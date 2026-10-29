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

        await model.loadIfNeeded()

        XCTAssertEqual(model.remembered?.poseId, "pose-1")
        XCTAssertEqual(CameraGuidePolicy.openingGuide(explicit: nil, remembered: model.remembered)?.name,
                       "Soft Standing")
    }

    func testThePoseTheUserTookBecomesTheRememberedOne() async {
        let store = InMemoryCameraLastPoseStore()
        let model = makeModel(store: store)
        await model.loadIfNeeded()
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
        let load = Task { await model.loadIfNeeded() }
        await store.waitUntilLoadStarted()

        model.remember(samplePose(id: "pose-taken", name: "Taken Pose"))
        await store.completeLoad(nil)
        await load.value

        XCTAssertEqual(model.remembered?.poseId, "pose-taken")
    }

    func testTheStoredReadFillsInWhenNothingWasTaken() async throws {
        let store = BlockingLastPoseStore()
        let model = makeModel(store: store)
        let load = Task { await model.loadIfNeeded() }
        await store.waitUntilLoadStarted()

        await store.completeLoad(CameraLastPose(pose: samplePose(id: "pose-stored")))
        await load.value

        XCTAssertEqual(model.remembered?.poseId, "pose-stored")
    }

    func testASessionChangeDropsThePoseAndItsRow() async {
        let store = InMemoryCameraLastPoseStore(seed: CameraLastPose(pose: samplePose()))
        let model = makeModel(store: store)
        await model.loadIfNeeded()
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
        let load = Task { await model.loadIfNeeded() }
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

        await model.loadIfNeeded()

        XCTAssertNil(model.remembered)
    }

    // MARK: - Back target (routing)

    func testClosingTheCameraFromAPoseDetailRestoresThatDetail() throws {
        var slot = PosesResumeSlot()
        let pose = samplePose()

        slot.cameraClosed(after: .poseDetail(pose))

        XCTAssertEqual(try XCTUnwrap(slot.poseToRestore).id, pose.id)
    }

    func testClosingTheCameraOpenedFromHomeShowsTheCatalogue() {
        var slot = PosesResumeSlot()

        slot.cameraClosed(after: .home)

        XCTAssertNil(slot.poseToRestore)
    }

    func testAHomeEntryClearsADetailTargetLeftFromAnEarlierVisit() {
        var slot = PosesResumeSlot()
        slot.cameraClosed(after: .poseDetail(samplePose()))

        slot.cameraClosed(after: .home)

        XCTAssertNil(slot.poseToRestore, "the second visit goes back to Home, not to the old detail")
    }

    func testTheRestoredDetailIsConsumedOnce() {
        var slot = PosesResumeSlot()
        slot.cameraClosed(after: .poseDetail(samplePose()))

        slot.consume()

        XCTAssertNil(slot.poseToRestore, "re-entering the tab later must not re-open the pose")
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

    private func makeModel(store: any CameraLastPoseStore) -> CameraLastPoseModel {
        // A boundary per model: the fan-out is process-wide per boundary, so sharing the app's would
        // let one test's session event reset another test's model.
        CameraLastPoseModel(store: store, boundary: SessionBoundary(tokenStorage: TestTokenStorage()))
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
