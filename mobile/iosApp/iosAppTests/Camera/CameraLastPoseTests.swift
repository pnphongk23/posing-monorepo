import AVFoundation
import Combine
import GRDB
import XCTest
@testable import iosApp

/// BUG-261029-04 / -05: the camera remembers the last pose it drew, and closing it lands back on the
/// pose detail it was opened from.
///
/// These are the decisions, not the pixels: which guide an entry point opens with, what the camera
/// does when the stored reference cannot be drawn, what a session change does to it, and which route
/// the Poses tab is rebuilt on. The row is exercised against a real GRDB database in a temporary
/// directory (the same way `CameraSettingsPersistenceTests` proves the settings row) because
/// `CameraSnapshot` is a shared table with its own column contract.
@MainActor
final class CameraLastPoseTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("camera-last-pose-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Which guide the camera opens with (resolution)

    func testFirstLaunchOpensTheCameraWithNoPose() {
        XCTAssertNil(CameraGuidePolicy.openingGuide(explicit: nil, remembered: nil))
    }

    func testDockEntryDrawsTheRememberedPose() throws {
        let remembered = CameraLastPose(pose: samplePose())

        let guide = try XCTUnwrap(CameraGuidePolicy.openingGuide(explicit: nil, remembered: remembered))

        XCTAssertEqual(guide.id, "pose-1")
        XCTAssertEqual(guide.name, "Soft Standing")
        XCTAssertEqual(guide.category, "Standing")
        XCTAssertEqual(guide.cameraGuideURL?.absoluteString, "https://cdn.example.com/guides/pose-1.png")
        XCTAssertNil(guide.imageURL, "the source photo is never the camera reference")
    }

    func testAnExplicitlyChosenPoseAlwaysWins() throws {
        let remembered = CameraLastPose(pose: samplePose(id: "pose-old", name: "Old Pose"))
        let chosen = samplePose(id: "pose-new", name: "New Pose")

        let guide = try XCTUnwrap(CameraGuidePolicy.openingGuide(explicit: chosen, remembered: remembered))

        XCTAssertEqual(guide.id, "pose-new")
        XCTAssertEqual(guide.name, "New Pose")
    }

    /// Every shape of "cannot be resolved" has to behave like a first launch: no pose, no error.
    func testUnresolvableReferencesOpenTheCameraAsToday() {
        let noName = CameraLastPose(poseId: "pose-1", name: "   ", category: "Standing")
        let noId = CameraLastPose(poseId: "", name: "Soft Standing", category: "Standing")
        let halfWritten = CameraLastPose.decode(#"{"category":"Standing"}"#)

        XCTAssertNil(CameraGuidePolicy.openingGuide(explicit: nil, remembered: noName))
        XCTAssertNil(CameraGuidePolicy.openingGuide(explicit: nil, remembered: noId))
        XCTAssertNil(CameraGuidePolicy.openingGuide(explicit: nil, remembered: halfWritten))
    }

    /// A reference whose line art was never cached (or is gone) still resolves: the camera falls back
    /// to the stick figure named by the remembered name/category instead of reporting a missing asset.
    func testARowWithoutGuideArtStillDrawsTheFallbackFigure() throws {
        let remembered = CameraLastPose(poseId: "pose-1", name: "Warrior", category: "Standing")

        let guide = try XCTUnwrap(CameraGuidePolicy.openingGuide(explicit: nil, remembered: remembered))

        XCTAssertEqual(guide.name, "Warrior")
        XCTAssertNil(guide.cameraGuideURL)
    }

    // MARK: - The stored reference (codec)

    func testReferenceRoundTripsThroughJSON() throws {
        let original = CameraLastPose(pose: samplePose())

        let decoded = try XCTUnwrap(CameraLastPose.decode(try original.encodedJSON()))

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.pose, original.pose)
    }

    func testGarbageOrMissingJSONIsNilSoTheCameraOpensUnchanged() {
        XCTAssertNil(CameraLastPose.decode(nil))
        XCTAssertNil(CameraLastPose.decode(""))
        XCTAssertNil(CameraLastPose.decode("not json at all"))
        XCTAssertNil(CameraLastPose.decode("[]"))
    }

    // MARK: - The row (real GRDB, temporary file)

    func testRememberedPoseSurvivesARelaunch() async throws {
        let database = try makeDatabase()
        try await GRDBCameraLastPoseStore(database: database).save(CameraLastPose(pose: samplePose()))

        // A relaunch is a new store over the same file.
        let reloaded = try await GRDBCameraLastPoseStore(database: database).load()

        XCTAssertEqual(reloaded?.poseId, "pose-1")
        XCTAssertEqual(reloaded?.pose?.name, "Soft Standing")
        try await database.pool.read { db in try AppDatabaseSchema.XCTAssertSchemaParity(db) }
    }

    /// The remembered pose lives in `pose_json`, so a pose write must leave the settings payload
    /// (revision included) byte-identical — remembering a pose is not a settings edit.
    func testPoseWriteLeavesTheStoredSettingsByteIdentical() async throws {
        let database = try makeDatabase()
        let settings = CameraSettings(revision: 9, guideOpacity: 0.25, isGridVisible: true, flash: .on)
        try await GRDBCameraSettingsStore(database: database).save(settings)
        let storedBefore = try await snapshotRow(database)
        let settingsBefore = try XCTUnwrap(storedBefore).settingsJSON

        try await GRDBCameraLastPoseStore(database: database).save(CameraLastPose(pose: samplePose()))

        let storedAfter = try await snapshotRow(database)
        let row = try XCTUnwrap(storedAfter)
        XCTAssertEqual(row.settingsJSON, settingsBefore, "a pose write never rewrites the settings")
        XCTAssertEqual(CameraLastPose.decode(row.poseJSON)?.poseId, "pose-1")
        let count = try await database.pool.read { db in try CameraSnapshotRecord.fetchCount(db) }
        XCTAssertEqual(count, 1, "the table holds exactly one row")
    }

    /// The other direction, which already held before this feature (D8): saving settings keeps the
    /// pose the camera remembered.
    func testSettingsWriteKeepsTheRememberedPose() async throws {
        let database = try makeDatabase()
        try await GRDBCameraLastPoseStore(database: database).save(CameraLastPose(pose: samplePose()))

        try await GRDBCameraSettingsStore(database: database).save(CameraSettings(revision: 4, flash: .off))

        let stored = try await snapshotRow(database)
        let row = try XCTUnwrap(stored)
        XCTAssertEqual(CameraLastPose.decode(row.poseJSON)?.poseId, "pose-1")
        XCTAssertEqual(CameraSettings.decode(row.settingsJSON)?.flash, .off)
    }

    func testClearingThePoseKeepsTheRowAndTheSettings() async throws {
        let database = try makeDatabase()
        let store = GRDBCameraLastPoseStore(database: database)
        try await GRDBCameraSettingsStore(database: database).save(CameraSettings(revision: 2, zoom: .two))
        try await store.save(CameraLastPose(pose: samplePose()))

        try await store.save(nil)

        let stored = try await snapshotRow(database)
        let row = try XCTUnwrap(stored)
        XCTAssertNil(row.poseJSON)
        XCTAssertEqual(CameraSettings.decode(row.settingsJSON)?.zoom, .two)
    }

    /// A pose remembered before the camera ever stored a setting: the row is created with the
    /// documented defaults instead of a pose with no settings payload.
    func testPoseWriteOnAFreshDatabaseCreatesTheRowWithDefaultSettings() async throws {
        let database = try makeDatabase()

        try await GRDBCameraLastPoseStore(database: database).save(CameraLastPose(pose: samplePose()))

        let stored = try await snapshotRow(database)
        let row = try XCTUnwrap(stored)
        XCTAssertEqual(row.id, 1)
        XCTAssertEqual(CameraSettings.decode(row.settingsJSON), CameraSettings())
        XCTAssertEqual(CameraLastPose.decode(row.poseJSON)?.poseId, "pose-1")
    }

    /// Nothing remembered: no row is invented, so a first launch leaves the database untouched.
    func testClearingWithNoStoredRowWritesNothing() async throws {
        let database = try makeDatabase()

        try await GRDBCameraLastPoseStore(database: database).save(nil)

        let stored = try await snapshotRow(database)
        XCTAssertNil(stored)
    }

    // MARK: - The model (transitions)

    func testOpeningTheCameraReadsTheStoredPose() async {
        let model = makeModel(store: InMemoryCameraLastPoseStore(seed: CameraLastPose(pose: samplePose())))

        await model.cameraOpened(explicitPoseChosen: false)

        XCTAssertEqual(model.remembered?.poseId, "pose-1")
        XCTAssertEqual(CameraGuidePolicy.openingGuide(explicit: nil, remembered: model.remembered)?.name,
                       "Soft Standing")
    }

    func testThePoseTheUserTookBecomesTheRememberedOne() async {
        let store = InMemoryCameraLastPoseStore()
        let model = makeModel(store: store)
        await model.cameraOpened(explicitPoseChosen: false)
        XCTAssertNil(model.remembered)

        model.remember(samplePose(id: "pose-42", name: "Twist"))
        await waitUntil { await store.saves.count == 1 }

        XCTAssertEqual(model.remembered?.poseId, "pose-42")
        let saves = await store.saves
        XCTAssertEqual(saves.compactMap { $0 }.map(\.poseId), ["pose-42"])
    }

    /// The camera binding funnels the pose it is already drawing back through the model; that must not
    /// turn into a write per re-render.
    func testRememberingTheSamePoseTwiceWritesOnce() async {
        let store = InMemoryCameraLastPoseStore()
        let model = makeModel(store: store)

        model.remember(samplePose())
        await waitUntil { await store.saves.count == 1 }
        model.remember(samplePose())
        try? await Task.sleep(nanoseconds: 50_000_000)

        let saves = await store.saves
        XCTAssertEqual(saves.count, 1)
    }

    /// The first camera open of a run remembers the pose *and* starts the stored read in the same
    /// turn. If that read wins with an older (or empty) row, the guide would disappear on the next
    /// camera open — the pose the user just took is the fresher answer and has to survive the read.
    func testAPoseTakenWhileTheStoredReadIsInFlightIsNotOverwritten() async throws {
        let store = BlockingLastPoseStore()
        let model = makeModel(store: store)
        let load = Task { await model.cameraOpened(explicitPoseChosen: false) }
        await store.waitUntilLoadStarted()

        model.remember(samplePose(id: "pose-taken", name: "Taken Pose"))
        await store.completeLoad(nil)
        await load.value

        XCTAssertEqual(model.remembered?.poseId, "pose-taken")
    }

    func testTheStoredReadFillsInWhenNothingWasTaken() async throws {
        let store = BlockingLastPoseStore()
        let model = makeModel(store: store)
        let load = Task { await model.cameraOpened(explicitPoseChosen: false) }
        await store.waitUntilLoadStarted()

        await store.completeLoad(CameraLastPose(pose: samplePose(id: "pose-stored")))
        await load.value

        XCTAssertEqual(model.remembered?.poseId, "pose-stored")
    }

    func testASessionChangeDropsThePoseAndItsRow() async {
        let store = InMemoryCameraLastPoseStore(seed: CameraLastPose(pose: samplePose()))
        let model = makeModel(store: store)
        await model.cameraOpened(explicitPoseChosen: false)
        XCTAssertEqual(model.remembered?.poseId, "pose-1")

        model.resetForSessionChange(.signedOut)
        await waitUntil { await store.saves.contains { $0 == nil } }

        XCTAssertNil(model.remembered, "the next Account must not open the camera on this pose")
        let stored = (try? await store.load()) ?? nil
        XCTAssertNil(stored, "and a relaunch must not bring it back")
    }

    /// A read that was in flight when the Account moved belongs to the previous session: it must not
    /// paint that pose over the reset.
    func testAReadInFlightAcrossASessionChangeDoesNotResurrectThePose() async throws {
        let store = BlockingLastPoseStore()
        let model = makeModel(store: store)
        let load = Task { await model.cameraOpened(explicitPoseChosen: false) }
        await store.waitUntilLoadStarted()

        model.resetForSessionChange(.signedIn)
        await store.completeLoad(CameraLastPose(pose: samplePose()))
        await load.value

        XCTAssertNil(model.remembered)
    }

    /// After a session change nothing is remembered until a pose is used again, even if the clear
    /// could not reach the disk.
    func testTheNextCameraOpenAfterASessionChangeDoesNotReadTheOldRowBack() async {
        let store = InMemoryCameraLastPoseStore(seed: CameraLastPose(pose: samplePose()))
        let model = makeModel(store: store)
        model.resetForSessionChange(.signedOut)

        await model.cameraOpened(explicitPoseChosen: false)

        XCTAssertNil(model.remembered)
    }

    // MARK: - The remembered pose has to still exist (deleted / unsaved / unpublished)

    func testARememberedPoseThatStillExistsIsDrawn() async {
        let resolver = StubLastPoseResolver(resolvable: true)
        let model = makeModel(store: InMemoryCameraLastPoseStore(seed: CameraLastPose(pose: samplePose())),
                              resolver: resolver)

        await model.cameraOpened(explicitPoseChosen: false)

        XCTAssertEqual(model.remembered?.poseId, "pose-1")
        let checked = await resolver.checked
        XCTAssertEqual(checked, ["pose-1"], "the stored reference is what gets resolved")
    }

    /// The reported scenario: use pose A, A is deleted / unpublished, reopen the camera from Home —
    /// even after a relaunch. No guide, no error, and the stale reference is dropped.
    func testADeletedPoseOpensTheCameraWithoutAPoseAndClearsTheReference() async {
        let store = InMemoryCameraLastPoseStore(seed: CameraLastPose(pose: samplePose()))
        let model = makeModel(store: store, resolver: StubLastPoseResolver(resolvable: false))

        await model.cameraOpened(explicitPoseChosen: false)

        XCTAssertNil(model.remembered, "a pose that no longer exists must not be drawn")
        await waitUntil { await store.saves.contains { $0 == nil } }
        let stored = (try? await store.load()) ?? nil
        XCTAssertNil(stored, "the stale reference goes, so the next open does not re-check it")
    }

    func testTheCatalogueKeepsAPoseItStillHolds() async throws {
        let database = try makeDatabase()
        let repository = PoseRepository(database: database)
        try await repository.save(makePoseRecord(id: "pose-1"))
        let resolver = CatalogueCameraLastPoseResolver(
            repositoryProvider: { repository },
            isOutlineAvailable: { _ in false }
        )

        let resolvable = await resolver.isResolvable(CameraLastPose(pose: samplePose(id: "pose-1")))

        XCTAssertTrue(resolvable)
    }

    /// Deleted or unpublished since: the catalogue cache prunes the row, so a missing row in a
    /// catalogue that still knows other poses is the local signal that this pose is gone — and it
    /// beats the cached outline, which is exactly what was drawn before the pose was deleted.
    func testADeletedPoseIsNotResolvable() async throws {
        let database = try makeDatabase()
        let repository = PoseRepository(database: database)
        try await repository.save(makePoseRecord(id: "pose-1"))
        try await repository.save(makePoseRecord(id: "pose-2"))
        try await repository.delete(ids: ["pose-1"])
        let resolver = CatalogueCameraLastPoseResolver(
            repositoryProvider: { repository },
            isOutlineAvailable: { _ in true }
        )

        let deleted = await resolver.isResolvable(CameraLastPose(pose: samplePose(id: "pose-1")))
        let stillListed = await resolver.isResolvable(CameraLastPose(pose: samplePose(id: "pose-2")))

        XCTAssertFalse(deleted, "a row the catalogue no longer lists means deleted/unpublished")
        XCTAssertTrue(stillListed, "the pose the user still has keeps its guide")
    }

    /// Offline-safe: with nothing cached to compare against (a first launch, or a catalogue cleared by
    /// a session change), the outline that was drawn last time is local evidence enough.
    func testAnEmptyCatalogueFallsBackToTheCachedOutline() async throws {
        let database = try makeDatabase()
        let repository = PoseRepository(database: database)
        let checked = OutlineChecks()
        let resolver = CatalogueCameraLastPoseResolver(
            repositoryProvider: { repository },
            isOutlineAvailable: { url in
                Task { await checked.record(url) }
                return true
            }
        )

        let resolvable = await resolver.isResolvable(CameraLastPose(pose: samplePose()))
        await waitUntil { await checked.urls.count == 1 }

        XCTAssertTrue(resolvable)
        let urls = await checked.urls
        XCTAssertEqual(urls.map(\.absoluteString), ["https://cdn.example.com/guides/pose-1.png"])
    }

    func testAnEmptyCatalogueWithNoOutlineIsNotResolvable() async throws {
        let database = try makeDatabase()
        let repository = PoseRepository(database: database)
        let resolver = CatalogueCameraLastPoseResolver(
            repositoryProvider: { repository },
            isOutlineAvailable: { _ in false }
        )

        let resolvable = await resolver.isResolvable(CameraLastPose(pose: samplePose()))

        XCTAssertFalse(resolvable, "nothing local to draw and nothing cached: open as on a first launch")
    }

    func testACorruptReferenceIsNeverResolvable() async {
        let resolver = CatalogueCameraLastPoseResolver(
            repositoryProvider: { nil },
            isOutlineAvailable: { _ in true }
        )

        let resolvable = await resolver.isResolvable(CameraLastPose(poseId: "", name: "", category: ""))

        XCTAssertFalse(resolvable)
    }

    // MARK: - Reopening the camera revalidates (BUG-261029-04 review, round 2)

    /// The reported scenario: use pose A, close the camera, A becomes unresolvable (unsaved), open the
    /// camera from Home again — the guide and the stored reference must be gone, not wait for a relaunch.
    func testReopeningTheCameraDropsAPoseThatWentAway() async {
        let resolver = StubLastPoseResolver(resolvable: true)
        let store = InMemoryCameraLastPoseStore(seed: CameraLastPose(pose: samplePose()))
        let model = makeModel(store: store, resolver: resolver)
        await model.cameraOpened(explicitPoseChosen: false)
        XCTAssertEqual(model.remembered?.poseId, "pose-1")

        // The pose is unsaved / deleted while the camera is closed.
        await resolver.setResolvable(false)
        await model.cameraOpened(explicitPoseChosen: false)

        XCTAssertNil(model.remembered, "the stale guide must not survive a second open")
        await waitUntil { await store.saves.contains { $0 == nil } }
        let stored = (try? await store.load()) ?? nil
        XCTAssertNil(stored, "and the persisted reference goes with it")
    }

    /// The same scenario against the real resolver and a real catalogue: a *saved* pose that is unsaved
    /// keeps no row when the catalogue is pruned, so the next open resolves to nothing even though its
    /// outline is still cached (the cached art must not outvote what the catalogue knows).
    func testASavedPoseThatWasUnsavedIsDroppedOnTheNextOpen() async throws {
        let database = try makeDatabase()
        let repository = PoseRepository(database: database)
        try await repository.save(makePoseRecord(id: "pose-1"))
        try await repository.save(makePoseRecord(id: "pose-2"))
        let resolver = CatalogueCameraLastPoseResolver(
            repositoryProvider: { repository },
            isOutlineAvailable: { _ in true }
        )
        let store = InMemoryCameraLastPoseStore(seed: CameraLastPose(pose: samplePose(id: "pose-1")))
        let model = makeModel(store: store, resolver: resolver)

        await model.cameraOpened(explicitPoseChosen: false)
        XCTAssertEqual(model.remembered?.poseId, "pose-1", "the pose is still in the catalogue")

        // Unsave: the catalogue prunes its row (the pose is saved-only), its art stays cached.
        try await repository.delete(ids: ["pose-1"])
        await model.cameraOpened(explicitPoseChosen: false)

        XCTAssertNil(model.remembered)
        await waitUntil { await store.saves.contains { $0 == nil } }
        let stored = (try? await store.load()) ?? nil
        XCTAssertNil(stored, "and the persisted reference goes with it")
    }

    /// A pose the user just chose on a detail screen is not re-checked mid-session: the screen they
    /// pressed the CTA on is the proof, and a stale local cache must not remove the guide they are
    /// looking at.
    func testAnExplicitlyChosenPoseIsNotRevalidated() async {
        let resolver = StubLastPoseResolver(resolvable: false)
        let model = makeModel(store: InMemoryCameraLastPoseStore(), resolver: resolver)
        model.remember(samplePose(id: "pose-fresh"))

        await model.cameraOpened(explicitPoseChosen: true)

        XCTAssertEqual(model.remembered?.poseId, "pose-fresh")
        let checked = await resolver.checked
        XCTAssertTrue(checked.isEmpty, "an explicit choice is not second-guessed")
    }

    // MARK: - A private pose has its own source (BUG-261029-04 review, round 2)

    /// A private pose (Jobs / Add pose) never enters the public catalogue, so a catalogue lookup would
    /// always miss it. It is validated by its own extracted art instead — otherwise a pose the user
    /// still has would be dropped on the first open after a relaunch.
    func testAPrivatePoseIsValidatedByItsArtNotByCatalogueMembership() async throws {
        let database = try makeDatabase()
        let repository = PoseRepository(database: database)
        // A catalogue that knows other poses but not this one.
        try await repository.save(makePoseRecord(id: "pose-public"))
        let outlines = OutlineChecks()
        let resolver = CatalogueCameraLastPoseResolver(
            repositoryProvider: { repository },
            isOutlineAvailable: { url in
                Task { await outlines.record(url) }
                return true
            }
        )

        let privateReference = CameraLastPose(pose: samplePose(id: "pose-private"), isPrivate: true)
        let resolvable = await resolver.isResolvable(privateReference)
        let sameIdAsPublic = await resolver.isResolvable(
            CameraLastPose(pose: samplePose(id: "pose-private"), isPrivate: false)
        )
        await waitUntil { await outlines.urls.count == 1 }

        XCTAssertTrue(resolvable, "a private pose is looked up in its own lane, not the catalogue")
        let checked = await outlines.urls
        XCTAssertEqual(checked.map(\.lastPathComponent), ["pose-1.png"])
        XCTAssertFalse(sameIdAsPublic, "the same id as a public pose is still a catalogue miss")
    }

    func testAPrivatePoseWithNoArtLeftIsDropped() async throws {
        let database = try makeDatabase()
        let repository = PoseRepository(database: database)
        try await repository.save(makePoseRecord(id: "pose-public"))
        let resolver = CatalogueCameraLastPoseResolver(
            repositoryProvider: { repository },
            isOutlineAvailable: { _ in false }
        )

        let resolvable = await resolver.isResolvable(
            CameraLastPose(pose: samplePose(id: "pose-private"), isPrivate: true)
        )

        XCTAssertFalse(resolvable, "nothing local left to draw: open as on a first launch")
    }

    /// The full path for a private pose: use it from a private detail, relaunch, open the camera from
    /// Home — the cached art is enough, and the provenance survives the round trip through the row.
    func testAPrivatePoseSurvivesARelaunchThroughTheCatalogueItIsNotIn() async throws {
        let database = try makeDatabase()
        let repository = PoseRepository(database: database)
        try await repository.save(makePoseRecord(id: "pose-public"))
        let resolver = CatalogueCameraLastPoseResolver(
            repositoryProvider: { repository },
            isOutlineAvailable: { _ in true }
        )
        let store = InMemoryCameraLastPoseStore()
        let model = makeModel(store: store, resolver: resolver)

        model.remember(samplePose(id: "pose-private", name: "My Pose"), isPrivate: true)
        await waitUntil { await store.saves.count == 1 }
        let storedRow = (try? await store.load()) ?? nil
        let persisted = try XCTUnwrap(storedRow)
        XCTAssertTrue(persisted.isPrivate, "provenance is part of the stored reference")

        // A relaunch is a fresh model over the same row.
        let relaunched = makeModel(store: store, resolver: resolver)
        await relaunched.cameraOpened(explicitPoseChosen: false)

        XCTAssertEqual(relaunched.remembered?.poseId, "pose-private")
    }

    func testProvenanceRoundTripsAndOldRowsReadAsPublic() throws {
        let privateReference = CameraLastPose(pose: samplePose(), isPrivate: true)
        XCTAssertEqual(try XCTUnwrap(CameraLastPose.decode(try privateReference.encodedJSON())).isPrivate, true)

        // A row written before the flag existed.
        let legacy = try XCTUnwrap(CameraLastPose.decode(#"{"poseId":"pose-1","name":"Warrior"}"#))
        XCTAssertFalse(legacy.isPrivate)
    }

    // MARK: - Back target (routing)

    func testClosingTheCameraFromAPoseDetailRestoresThatDetail() throws {
        var slot = PosesResumeSlot()
        let pose = samplePose()

        slot.cameraClosed(after: .poseDetail(CameraPoseRequest(pose: pose)))

        XCTAssertEqual(try XCTUnwrap(slot.targetToRestore).pose.id, pose.id)
        XCTAssertFalse(try XCTUnwrap(slot.targetToRestore).isPrivate)
    }

    func testClosingTheCameraOpenedFromHomeShowsTheCatalogue() {
        var slot = PosesResumeSlot()

        slot.cameraClosed(after: .home)

        XCTAssertNil(slot.targetToRestore)
    }

    func testAHomeEntryClearsADetailTargetLeftFromAnEarlierVisit() {
        var slot = PosesResumeSlot()
        slot.cameraClosed(after: .poseDetail(CameraPoseRequest(pose: samplePose())))

        slot.cameraClosed(after: .home)

        XCTAssertNil(slot.targetToRestore, "the second visit goes back to Home, not to the old detail")
    }

    func testTheRestoredDetailIsConsumedOnce() {
        var slot = PosesResumeSlot()
        slot.cameraClosed(after: .poseDetail(CameraPoseRequest(pose: samplePose())))

        slot.consume()

        XCTAssertNil(slot.targetToRestore, "re-entering the tab later must not re-open the pose")
    }

    /// A private pose (Jobs / Add pose) only exists behind the account's own endpoints. Restoring it
    /// as a public detail would send it to the public catalogue, which answers 404 and shows "Pose
    /// unavailable" for the pose the user just used.
    func testAPrivateDetailIsRestoredPrivate() throws {
        var slot = PosesResumeSlot()
        let privatePose = samplePose(id: "pose-private", name: "My Extracted Pose")

        slot.cameraClosed(after: .poseDetail(CameraPoseRequest(pose: privatePose, isPrivate: true)))

        let restored = try XCTUnwrap(slot.targetToRestore)
        XCTAssertEqual(restored.pose.id, privatePose.id)
        XCTAssertTrue(restored.isPrivate, "the restored detail keeps skipping the public confirm")
    }

    func testTheUseThisPoseRouteCarriesTheLane() {
        var request: CameraPoseRequest?
        let pose = samplePose()

        routeTryPoseToCamera(pose, isPrivate: true) { request = $0 }
        XCTAssertEqual(request?.pose.id, pose.id)
        XCTAssertEqual(request?.isPrivate, true)

        routeTryPoseToCamera(pose, isPrivate: false) { request = $0 }
        XCTAssertEqual(request?.isPrivate, false)
    }

    // MARK: - The paid gate is untouched by the remembered pose

    /// The M02 gate still runs first, whichever way the guide was chosen: a remembered pose is not a
    /// way around the paywall, and an unentitled press never reaches the capture path.
    func testThePremiumGateStillAppliesToTheRememberedPose() throws {
        let remembered = CameraLastPose(pose: samplePose())
        let guide = try XCTUnwrap(CameraGuidePolicy.openingGuide(explicit: nil, remembered: remembered))
        let camera = FakeGateCamera()
        var paywallRequests = 0
        let model = CameraViewModel(
            guide: guide,
            camera: camera,
            photoMetadata: InMemoryCapturePhotoMetadata(),
            premiumGate: StubPaywallGate(.paywall(signIn: false)),
            onPremiumRequired: { _ in paywallRequests += 1 }
        )

        model.capture()

        XCTAssertEqual(paywallRequests, 1, "the remembered pose still asks for the paywall")
        XCTAssertEqual(camera.captureCalls, 0, "an unentitled press never reaches the camera")
        XCTAssertFalse(model.coordinator.state.isCaptureInFlight)
    }

    // MARK: - Fixtures and helpers

    /// A boundary per model: the fan-out is process-wide per boundary, so sharing the app's would let
    /// one test's session event reset another test's model. The resolver defaults to "still there",
    /// because these tests are about the model; the real resolution rules have their own tests below.
    private func makeModel(
        store: any CameraLastPoseStore,
        resolver: any CameraLastPoseResolving = StubLastPoseResolver()
    ) -> CameraLastPoseModel {
        CameraLastPoseModel(
            store: store,
            resolver: resolver,
            boundary: SessionBoundary(tokenStorage: TestTokenStorage())
        )
    }

    private func samplePose(
        id: String = "pose-1",
        name: String = "Soft Standing",
        category: String = "Standing",
        guideURL: URL? = URL(string: "https://cdn.example.com/guides/pose-1.png")
    ) -> NativePose {
        NativePose(
            id: id,
            name: name,
            category: category,
            imageURL: URL(string: "https://cdn.example.com/photos/\(id).jpg"),
            instructions: ["Relax your shoulders", "Turn slightly toward the light"],
            isSaved: false,
            guideURL: guideURL
        )
    }

    private func makePoseRecord(id: String) -> PoseRecord {
        PoseRecord(
            poseId: id,
            ownerAccountId: "account-1",
            name: "Soft Standing",
            description: nil,
            tags: "[]",
            difficulty: "Standing",
            bodyParts: "[]",
            status: "published",
            originalPath: "",
            skeletonPath: "/guides/\(id).png",
            thumbnailPath: "/photos/\(id).jpg",
            currentJobId: nil,
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z"
        )
    }

    private func makeDatabase() throws -> AppDatabase {
        let url = root.appendingPathComponent("aipose.db")
        return try AppDatabase(location: AppDatabaseLocation(url: url, kind: .freshInstall))
    }

    private func snapshotRow(_ database: AppDatabase) async throws -> CameraSnapshotRecord? {
        try await database.pool.read { db in try CameraSnapshotRecord.fetchOne(db, key: 1) }
    }

    /// The app is main-actor bound, so a test helper has to yield the main actor for the model's
    /// write tasks to make progress.
    private func waitUntil(
        timeout: TimeInterval = 3,
        _ condition: () async -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !(await condition()) {
            if Date() > deadline {
                XCTFail("condition not met within \(timeout)s", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }
}

// MARK: - Doubles

/// Resolver double: the model tests only need the answer — and the ability to flip it, so "the pose
/// went away between two camera opens" is a state change instead of a different fixture. The real
/// resolver is exercised against a real `Pose` table next to them.
private actor StubLastPoseResolver: CameraLastPoseResolving {
    private var resolvable: Bool
    private(set) var checked: [String] = []

    init(resolvable: Bool = true) {
        self.resolvable = resolvable
    }

    func setResolvable(_ value: Bool) {
        resolvable = value
    }

    func isResolvable(_ reference: CameraLastPose) async -> Bool {
        checked.append(reference.poseId)
        return resolvable
    }
}

/// Collects the outlines a resolver asked about (the closure has to stay `@Sendable`).
private actor OutlineChecks {
    private(set) var urls: [URL] = []
    func record(_ url: URL) { urls.append(url) }
}

/// Session double: these models only need a boundary to adopt, never credentials.
private final class TestTokenStorage: TokenStoring, @unchecked Sendable {
    private var credentials: SessionCredentials?

    func saveCredentials(_ credentials: SessionCredentials) { self.credentials = credentials }
    func loadCredentials() -> SessionCredentials? { credentials }
    func clearCredentials() { credentials = nil }
}

/// Store whose `load` does not return until the test says so — the only reliable way to hold a read
/// open while the session moves on.
private actor BlockingLastPoseStore: CameraLastPoseStore {
    private var loadStarted = false
    private var waiters: [CheckedContinuation<CameraLastPose?, Never>] = []
    private(set) var saves: [CameraLastPose?] = []

    func load() async throws -> CameraLastPose? {
        loadStarted = true
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func save(_ pose: CameraLastPose?) async throws {
        saves.append(pose)
    }

    func waitUntilLoadStarted() async {
        while !loadStarted {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    func completeLoad(_ pose: CameraLastPose?) {
        let pending = waiters
        waiters = []
        for waiter in pending { waiter.resume(returning: pose) }
    }
}

/// Gate answer for the "remembered pose still pays" test. The decision itself is proved in
/// `PremiumGateTests`; here only that the camera asks the gate before it ever touches the camera.
@MainActor
private final class StubPaywallGate: PremiumGateProviding {
    private let updates = PassthroughSubject<Void, Never>()
    private let outcome: CaptureGateOutcome

    var gateUpdates: AnyPublisher<Void, Never> { updates.eraseToAnyPublisher() }

    init(_ outcome: CaptureGateOutcome) {
        self.outcome = outcome
    }

    func captureOutcome(cameraReady: Bool) -> CaptureGateOutcome { outcome }
}

@MainActor
private final class FakeGateCamera: CameraSessionControlling {
    var permission: CameraPermissionState = .authorized
    private(set) var isSessionRunning = false
    private(set) var captureCalls = 0

    let session = AVCaptureSession()
    var facing: CameraFacing = .back

    func currentPermissionState() -> CameraPermissionState { permission }

    func requestPermission(onResult: @escaping @Sendable (CameraPermissionState) -> Void) {
        onResult(permission)
    }

    func capture(captureId: String, onResult: @escaping @Sendable (CameraCaptureResult) -> Void) {
        captureCalls += 1
    }

    func cancelCapture() {}
    func switchCamera() {}
    func setFlashMode(_ mode: CameraFlashSetting) {}
    func setTorchEnabled(_ enabled: Bool) {}
    func setZoomFactor(_ factor: CGFloat) {}

    func start() async throws { isSessionRunning = true }
    func stop() { isSessionRunning = false }
}
