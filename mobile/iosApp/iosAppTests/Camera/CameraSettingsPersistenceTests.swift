import AVFoundation
import GRDB
import XCTest
@testable import iosApp

/// FEAT-012 — camera settings survive a relaunch.
///
/// These tests are written from the user's side of the screen: set something, relaunch, expect the
/// same thing, with the flash and zoom actually re-applied to the capture hardware. The settings
/// live in `CameraSnapshot.settings_json`, so the codec and the row are exercised against a real
/// GRDB database in a temporary directory, not a stub.
@MainActor
final class CameraSettingsPersistenceTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("camera-settings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Codec

    func testRoundTripPreservesEveryField() throws {
        let original = CameraSettings(
            revision: 12,
            guideOpacity: 0.35,
            guideFlipped: true,
            isGridVisible: true,
            flash: .off,
            isPoseGuideVisible: false,
            lineColor: .black,
            transform: .init(scale: 2.5, rotationDegrees: 32, offsetX: 14, offsetY: -20),
            zoom: .three
        )

        let decoded = try XCTUnwrap(CameraSettings.decode(try original.encodedJSON()))

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.version, CameraSettings.currentVersion)
        XCTAssertEqual(decoded.zoom, .three)
        XCTAssertEqual(decoded.flash, .off)
        XCTAssertEqual(decoded.guideTransform.scale, 2.5, accuracy: 0.001)
        XCTAssertEqual(decoded.guideTransform.rotation.degrees, 32, accuracy: 0.001)
        XCTAssertEqual(decoded.guideTransform.offset, CGSize(width: 14, height: -20))
    }

    /// A partial object is what a half-written or hand-edited row looks like. Every missing field has
    /// to come back at its default instead of the whole payload being thrown away.
    func testPartialJSONFillsTheRestWithDefaults() throws {
        let decoded = try XCTUnwrap(CameraSettings.decode(#"{"guideOpacity":0.8}"#))

        XCTAssertEqual(decoded.guideOpacity, 0.8, accuracy: 0.001)
        XCTAssertEqual(decoded.flash, .auto)
          XCTAssertEqual(decoded.lineColor.rawValue, "white", "the sheet's default swatch")
        XCTAssertEqual(decoded.zoom, .one)
        XCTAssertTrue(decoded.isPoseGuideVisible)
        XCTAssertFalse(decoded.isGridVisible)
        XCTAssertEqual(decoded.guideTransform, GuideTransform())
    }

    func testOutOfRangeAndCorruptNumbersAreClampedOrDefaulted() throws {
        let decoded = try XCTUnwrap(CameraSettings.decode("""
        {
          "guideOpacity": 7,
          "transform": { "scale": 0.01, "rotationDegrees": "nan", "offsetX": null, "offsetY": 1e9 }
        }
        """))

        XCTAssertEqual(decoded.guideOpacity, 1, accuracy: 0.001, "opacity is clamped to 0...1")
        XCTAssertEqual(decoded.guideTransform.scale, GuideTransform.scaleRange.lowerBound, accuracy: 0.001)
        XCTAssertEqual(decoded.guideTransform.rotation.degrees, 0, "a non-finite rotation falls back to 0")
        XCTAssertEqual(decoded.guideTransform.offset.width, 0, "a null offset falls back to 0")
        XCTAssertEqual(decoded.guideTransform.offset.height, 1e9)
    }

    func testUnknownEnumValuesFallBackToDefaults() throws {
        let decoded = try XCTUnwrap(CameraSettings.decode(
            #"{"flash":"strobe","lineColor":"neon","zoom":9}"#
        ))

        XCTAssertEqual(decoded.flash, .auto)
          XCTAssertEqual(decoded.lineColor.rawValue, "white", "the sheet's default swatch")
        XCTAssertEqual(decoded.zoom, .one)
    }

    func testLegacyGuideColorsDefaultToWhiteAndKeepOtherSettings() throws {
        for legacy in ["pink", "yellow", "green", "violet"] {
            let payload = """
            {"lineColor":"\(legacy)","guideOpacity":0.73,"guideFlipped":true,
             "transform":{"scale":1.6,"rotationDegrees":12,"offsetX":24,"offsetY":-8}}
            """
            let decoded = try XCTUnwrap(CameraSettings.decode(payload), "legacy \(legacy) should not discard the record")
            XCTAssertEqual(decoded.lineColor.rawValue, "white", "legacy \(legacy) maps to the white default")
            XCTAssertEqual(decoded.guideOpacity, 0.73, accuracy: 0.001)
            XCTAssertTrue(decoded.guideFlipped)
            XCTAssertEqual(decoded.guideTransform.scale, 1.6, accuracy: 0.001)
            XCTAssertEqual(decoded.guideTransform.offset, CGSize(width: 24, height: -8))
        }
    }

    func testGarbageJSONIsNilSoTheCallerCanFallBackToDefaults() {
        XCTAssertNil(CameraSettings.decode("not json at all"))
        XCTAssertNil(CameraSettings.decode("[]"))
        XCTAssertNil(CameraSettings.decode(""))
    }

    /// A legacy Compose-era snapshot: an object with keys this build has never heard of. It must not
    /// crash and must not leak a bogus value into the UI.
    func testLegacySnapshotShapeYieldsDefaults() throws {
        let decoded = try XCTUnwrap(CameraSettings.decode("""
        {"cameraFacing":"FRONT","flashMode":"ON","overlayOffset":{"x":10,"y":20},"zoomValue":0.5}
        """))

        XCTAssertEqual(decoded, CameraSettings())
    }

    // MARK: - Repository / store (real GRDB, temporary file)

    func testSaveSettingsCreatesTheSingletonRowWithoutAPose() async throws {
        let database = try makeDatabase()
        let store = GRDBCameraSettingsStore(database: database)

        try await store.save(makeSettings(revision: 3, opacity: 0.25, flash: .on))

        let storedRow = try await snapshotRow(database)
        let row = try XCTUnwrap(storedRow)
        XCTAssertEqual(row.id, 1)
        XCTAssertEqual(row.schemaVersion, Int64(CameraSettings.currentVersion))
        XCTAssertNil(row.poseJSON, "a settings save never writes a pose")
        XCTAssertEqual(CameraSettings.decode(row.settingsJSON)?.guideOpacity ?? 0, 0.25, accuracy: 0.001)
        XCTAssertEqual(CameraSettings.decode(row.settingsJSON)?.flash, .on)
    }

    /// D8 in one assertion: saving settings is not a pose clear. The stored `pose_json` text has to
    /// come back byte-identical.
    func testSaveSettingsKeepsStoredPoseByteIdentical() async throws {
        let database = try makeDatabase()
        let poseJSON = #"{"poseId":"pose-legacy-01","name":"Warrior"}"#
        try await database.pool.write { db in
            try CameraSnapshotRecord(schemaVersion: 1, settingsJSON: #"{"guideOpacity":0.1}"#, poseJSON: poseJSON)
                .save(db)
        }
        let store = GRDBCameraSettingsStore(database: database)

        try await store.save(makeSettings(revision: 9, opacity: 0.9, grid: true))

        let storedRow = try await snapshotRow(database)
        let row = try XCTUnwrap(storedRow)
        XCTAssertEqual(row.poseJSON, poseJSON)
        XCTAssertEqual(CameraSettings.decode(row.settingsJSON)?.isGridVisible, true)
        let rows = try await countRows(database)
        XCTAssertEqual(rows, 1, "the table holds exactly one row")
        try await database.pool.read { db in try AppDatabaseSchema.XCTAssertSchemaParity(db) }
    }

    func testOlderRevisionCannotReplaceNewer() async throws {
        let database = try makeDatabase()
        let writer = CameraSettingsWriter(store: GRDBCameraSettingsStore(database: database))

        await writer.write(makeSettings(revision: 7, opacity: 0.7))
        await writer.write(makeSettings(revision: 6, opacity: 0.6))

        let storedRow = try await snapshotRow(database)
        let row = try XCTUnwrap(storedRow)
        let stored = try XCTUnwrap(CameraSettings.decode(row.settingsJSON))
        XCTAssertEqual(stored.revision, 7)
        XCTAssertEqual(stored.guideOpacity, 0.7, accuracy: 0.001)
    }

    /// Writes can arrive in any order once the debounce and the background flush race. Whatever the
    /// order, the row must end up holding the newest payload, never an older one.
    func testConcurrentWritesStoreTheHighestRevision() async throws {
        let database = try makeDatabase()
        let writer = CameraSettingsWriter(store: GRDBCameraSettingsStore(database: database))
        let payloads = Array(1...50).shuffled().map { revision in
            makeSettings(revision: Int64(revision), opacity: Double(revision) / 100)
        }

        await withTaskGroup(of: Void.self) { group in
            for payload in payloads {
                group.addTask { await writer.write(payload) }
            }
        }

        let storedRow = try await snapshotRow(database)
        let row = try XCTUnwrap(storedRow)
        let stored = try XCTUnwrap(CameraSettings.decode(row.settingsJSON))
        let rows = try await countRows(database)
        XCTAssertEqual(stored.revision, 50)
        XCTAssertEqual(stored.guideOpacity, 0.5, accuracy: 0.001, "revision 50 carries opacity 0.50")
        XCTAssertEqual(rows, 1)
    }

    // MARK: - Restore into the view model

    func testRestoreAppliesBeforePermissionResolves() async throws {
        let camera = FakeSessionCamera()
        camera.permission = .notDetermined
        let store = MemorySettingsStore(seed: makeSettings(
            opacity: 0.2, flipped: true, grid: true, flash: .off,
              guideVisible: false, lineColor: .black, zoom: .three
        ))
        let model = makeModel(camera: camera, store: store)

        await waitUntil { model.initialMergeDone }

        XCTAssertEqual(model.guideOpacity, 0.2, accuracy: 0.001)
        XCTAssertTrue(model.guideFlipped)
        XCTAssertTrue(model.isGridVisible)
        XCTAssertEqual(model.flashSetting, .off)
        XCTAssertFalse(model.isPoseGuideVisible)
          XCTAssertEqual(model.guideLineColor, .black)
        XCTAssertEqual(model.zoomLevel, .three)
        XCTAssertFalse(model.cameraControlsEnabled, "the setters stay gated; the restore does not")
    }

    func testUserEditBeforeTheLateRestoreWins() async throws {
        let camera = FakeSessionCamera()
        let store = BlockingSettingsStore()
        let model = makeModel(camera: camera, store: store)
        await store.waitUntilLoadStarted()

        model.setGuideOpacity(0.9)

        await store.completeLoad(makeSettings(opacity: 0.2, grid: true))
        await waitUntil { model.initialMergeDone }

        XCTAssertEqual(model.guideOpacity, 0.9, accuracy: 0.001, "the user's edit beats a late restore")
        XCTAssertTrue(model.isGridVisible, "the untouched settings are still restored")
    }

    func testMissingSnapshotKeepsTheDocumentedDefaults() async throws {
        let camera = FakeSessionCamera()
        let model = makeModel(camera: camera, store: MemorySettingsStore(seed: nil))

        await waitUntil { model.initialMergeDone }

        XCTAssertEqual(model.guideOpacity, 0.5, accuracy: 0.001)
        XCTAssertEqual(model.flashSetting, .auto)
          XCTAssertEqual(model.guideLineColor.rawValue, "white", "the sheet's default swatch")
        XCTAssertEqual(model.zoomLevel, .one)
        XCTAssertTrue(model.isPoseGuideVisible)
        XCTAssertFalse(model.isGridVisible)
        XCTAssertEqual(model.guideTransform, GuideTransform())
    }

    // MARK: - Hardware (flash and zoom really re-applied)

    func testLoadThenSessionAppliesFlashAndZoomOnce() async throws {
        let camera = FakeSessionCamera()
        let model = makeModel(camera: camera, store: MemorySettingsStore(
            seed: makeSettings(flash: .on, zoom: .three)
        ))
        await waitUntil { model.initialMergeDone }
        XCTAssertEqual(camera.flashCalls, [], "nothing is applied while the session is down")

        await model.onAppear()

        XCTAssertEqual(camera.flashCalls, [.on])
        XCTAssertEqual(camera.zoomCalls, [3])
    }

    func testSessionThenLoadAppliesFlashAndZoomOnceWithoutAPriorAuto() async throws {
        let camera = FakeSessionCamera()
        let store = BlockingSettingsStore()
        let model = makeModel(camera: camera, store: store)
        await store.waitUntilLoadStarted()

        await model.onAppear()
        XCTAssertEqual(camera.flashCalls, [], "the defaults must not reach the hardware before the merge")

        await store.completeLoad(makeSettings(flash: .on, zoom: .three))
        await waitUntil { model.initialMergeDone }

        XCTAssertEqual(camera.flashCalls, [.on])
        XCTAssertEqual(camera.zoomCalls, [3])
    }

    /// Fresh install: there is nothing stored, and today the label says `Auto` while the device sits
    /// at `Off` because nothing re-applies the flash after the session starts.
    func testFreshInstallAppliesTheAutoDefaultToTheHardware() async throws {
        let camera = FakeSessionCamera()
        let model = makeModel(camera: camera, store: MemorySettingsStore(seed: nil))
        await waitUntil { model.initialMergeDone }

        await model.onAppear()

        XCTAssertEqual(model.flashSetting, .auto)
        XCTAssertEqual(camera.flashCalls, [.auto])
        XCTAssertEqual(camera.zoomCalls, [1])
    }

    func testDeniedPermissionAppliesNothingButKeepsTheValuesOnScreen() async throws {
        let camera = FakeSessionCamera()
        camera.permission = .denied
        let model = makeModel(camera: camera, store: MemorySettingsStore(
            seed: makeSettings(opacity: 0.3, flash: .on, zoom: .two)
        ))

        await waitUntil { model.initialMergeDone }
        await model.onAppear()

        XCTAssertEqual(camera.flashCalls, [])
        XCTAssertEqual(camera.zoomCalls, [])
        XCTAssertEqual(model.guideOpacity, 0.3, accuracy: 0.001)
        XCTAssertEqual(model.flashSetting, .on)
        XCTAssertEqual(model.zoomLevel, .two)
    }

    func testReconcileIsIdempotent() async throws {
        let camera = FakeSessionCamera()
        let model = makeModel(camera: camera, store: MemorySettingsStore(
            seed: makeSettings(flash: .on, zoom: .two)
        ))
        await waitUntil { model.initialMergeDone }
        await model.onAppear()

        model.reconcileHardware()
        model.reconcileHardware()

        XCTAssertEqual(camera.flashCalls, [.on])
        XCTAssertEqual(camera.zoomCalls, [2])
    }

    func testFlashAndZoomChangesReachTheHardwareOnceEach() async throws {
        let camera = FakeSessionCamera()
        let model = makeModel(camera: camera, store: MemorySettingsStore(seed: nil))
        await waitUntil { model.initialMergeDone }
        await model.onAppear()

        model.setFlash(.on)
        model.setFlash(.off)
        model.setZoomFactor(2)

        XCTAssertEqual(camera.flashCalls, [.auto, .on, .off], "the launch reconcile, then each chip change once")
        XCTAssertEqual(camera.zoomCalls, [1, 2])
    }

    // MARK: - Restored placement vs the pose-change reset (C3-Q1 option a)

    func testRestoredTransformAppliesToTheGuideAlreadyShownAtLaunch() async throws {
        let camera = FakeSessionCamera()
        let model = makeModel(camera: camera, store: MemorySettingsStore(
            seed: makeSettings(transform: .init(scale: 1.8, rotationDegrees: 20, offsetX: 30, offsetY: -10))
        ))
        await waitUntil { model.initialMergeDone }

        model.guideAppeared(hasGuide: true)

        XCTAssertEqual(model.guideTransform.scale, 1.8, accuracy: 0.001)
        XCTAssertEqual(model.guideTransform.rotation.degrees, 20, accuracy: 0.001)
        XCTAssertEqual(model.guideTransform.offset, CGSize(width: 30, height: -10))
    }

    func testGuideChosenBeforeTheLoadGetsTheRestoredTransform() async throws {
        let camera = FakeSessionCamera()
        let store = BlockingSettingsStore()
        let model = makeModel(camera: camera, store: store)
        await store.waitUntilLoadStarted()

        model.guideDidChange(hasGuide: true)
        XCTAssertEqual(model.guideTransform, GuideTransform(), "no pose is restored, so the reset still runs")

        await store.completeLoad(makeSettings(transform: .init(scale: 2, rotationDegrees: 0, offsetX: 0, offsetY: 0)))
        await waitUntil { model.initialMergeDone }

        XCTAssertEqual(model.guideTransform.scale, 2, accuracy: 0.001)
    }

    func testUserPinchBeforeTheLoadDiscardsThePendingTransform() async throws {
        let camera = FakeSessionCamera()
        let store = BlockingSettingsStore()
        let model = makeModel(camera: camera, store: store)
        await store.waitUntilLoadStarted()
        model.guideDidChange(hasGuide: true)

        model.commitGuideGesture(.init(scale: 1.5, rotation: .zero, translation: CGSize(width: 10, height: 0)))
        let userPlacement = model.guideTransform

        await store.completeLoad(makeSettings(transform: .init(scale: 3, rotationDegrees: 45, offsetX: 90, offsetY: 90)))
        await waitUntil { model.initialMergeDone }
        model.guideAppeared(hasGuide: true)

        XCTAssertEqual(model.guideTransform, userPlacement, "the user's placement is the one that survives")
    }

    func testSecondGuideChangeResetsTheRestoredTransform() async throws {
        let camera = FakeSessionCamera()
        let model = makeModel(camera: camera, store: MemorySettingsStore(
            seed: makeSettings(transform: .init(scale: 1.8, rotationDegrees: 20, offsetX: 30, offsetY: -10))
        ))
        await waitUntil { model.initialMergeDone }

        model.guideDidChange(hasGuide: true)
        XCTAssertEqual(model.guideTransform.scale, 1.8, accuracy: 0.001, "the first guide keeps the placement")

        model.guideDidChange(hasGuide: true)
        XCTAssertEqual(model.guideTransform, GuideTransform(), "later pose changes reset, as today")
    }

    func testWithoutARestoredTransformTheFirstGuideChangeResets() async throws {
        let camera = FakeSessionCamera()
        let model = makeModel(camera: camera, store: MemorySettingsStore(seed: nil))
        await waitUntil { model.initialMergeDone }
        model.commitGuideGesture(.init(scale: 2, rotation: .degrees(15), translation: CGSize(width: 12, height: 8)))

        model.guideDidChange(hasGuide: true)

        XCTAssertEqual(model.guideTransform, GuideTransform())
    }

    func testDoubleTapResetStillResetsAfterARestore() async throws {
        let camera = FakeSessionCamera()
        let model = makeModel(camera: camera, store: MemorySettingsStore(
            seed: makeSettings(transform: .init(scale: 2, rotationDegrees: 10, offsetX: 5, offsetY: 5))
        ))
        await waitUntil { model.initialMergeDone }
        model.guideDidChange(hasGuide: true)

        model.resetGuideTransform()

        XCTAssertEqual(model.guideTransform, GuideTransform())
    }

    func testResetGuideTransformPersistsIdentityPlacement() async throws {
        let database = try makeDatabase()
        let camera = FakeSessionCamera()
        let store = GRDBCameraSettingsStore(database: database)
        let model = makeModel(camera: camera, store: store, debounce: 10_000_000_000)
        await waitUntil { model.initialMergeDone }
        model.commitGuideGesture(.init(scale: 1.8, rotation: .degrees(15), translation: CGSize(width: 24, height: -9)))
        await model.flushSettings()

        model.resetGuideTransform()
        await model.flushSettings()

        XCTAssertEqual(model.guideTransform, GuideTransform())
        let storedRow = try await snapshotRow(database)
        let row = try XCTUnwrap(storedRow)
        let reloaded = try XCTUnwrap(CameraSettings.decode(row.settingsJSON))
        XCTAssertEqual(reloaded.guideTransform, GuideTransform(), "Reset persists the identity placement")
    }

    func testBlackGuideLineColorPersistsAcrossStoreReload() async throws {
        let database = try makeDatabase()
        let store = GRDBCameraSettingsStore(database: database)
        let first = makeModel(camera: FakeSessionCamera(), store: store)
        first.coordinator.onPermissionResult(.authorized)
        await waitUntil { first.initialMergeDone }
        first.setGuideLineColor(.black)
        await first.flushSettings()

        let reloaded = makeModel(camera: FakeSessionCamera(), store: store)
        await waitUntil { reloaded.initialMergeDone }
        XCTAssertEqual(reloaded.guideLineColor.rawValue, "black")
    }

    func testWhiteGuideLineColorPersistsAcrossStoreReload() async throws {
        let database = try makeDatabase()
        let store = GRDBCameraSettingsStore(database: database)
        let first = makeModel(camera: FakeSessionCamera(), store: store)
        first.coordinator.onPermissionResult(.authorized)
        await waitUntil { first.initialMergeDone }
        first.setGuideLineColor(GuideLineColor.stored("white"))
        await first.flushSettings()

        let reloaded = makeModel(camera: FakeSessionCamera(), store: store)
        await waitUntil { reloaded.initialMergeDone }
        XCTAssertEqual(reloaded.guideLineColor.rawValue, "white")
    }

    // MARK: - Saving

    func testRapidEditsCollapseIntoOneWriteWithTheLastValue() async throws {
        let camera = FakeSessionCamera()
        let store = MemorySettingsStore(seed: nil)
        let model = makeModel(camera: camera, store: store, debounce: 20_000_000)
        await waitUntil { model.initialMergeDone }

        for value in [0.1, 0.2, 0.3, 0.4, 0.6] { model.setGuideOpacity(value) }
        try await Task.sleep(nanoseconds: 250_000_000)

        let saved = await store.saved
        XCTAssertEqual(saved.count, 1, "the debounce collapses the spiral of a slider")
        XCTAssertEqual(saved.first?.guideOpacity ?? 0, 0.6, accuracy: 0.001)
    }

    /// The first save must never be "the defaults": on a slow launch the user's edit and the stored
    /// row have to meet first, then the merged state is what lands on disk.
    func testNoSaveHappensBeforeTheMergeAndTheFirstSaveHoldsTheMergedState() async throws {
        let camera = FakeSessionCamera()
        let store = BlockingSettingsStore()
        let model = makeModel(camera: camera, store: store, debounce: 20_000_000)
        await store.waitUntilLoadStarted()

        model.setGuideOpacity(0.9)
        try await Task.sleep(nanoseconds: 100_000_000)
        let savesBeforeMerge = await store.saved.count
        XCTAssertEqual(savesBeforeMerge, 0, "nothing is written while the load is in flight")

        await store.completeLoad(makeSettings(revision: 4, opacity: 0.2, grid: true, flash: .on))
        await waitUntil { model.initialMergeDone }
        try await Task.sleep(nanoseconds: 250_000_000)

        let saved = await store.saved
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.guideOpacity ?? 0, 0.9, accuracy: 0.001)
        XCTAssertTrue(saved.first?.isGridVisible ?? false)
        XCTAssertEqual(saved.first?.flash, .on)
        XCTAssertEqual(saved.first?.revision, 5, "the relaunch keeps counting above the stored revision")
    }

    func testBackgroundFlushWritesImmediately() async throws {
        let camera = FakeSessionCamera()
        let store = MemorySettingsStore(seed: nil)
        let model = makeModel(camera: camera, store: store, debounce: 10_000_000_000)
        await waitUntil { model.initialMergeDone }
        model.setGuideOpacity(0.4)

        await model.flushSettings()

        let saved = await store.saved
        XCTAssertEqual(saved.count, 1, "the background flush does not wait for the debounce")
        XCTAssertEqual(saved.first?.guideOpacity ?? 0, 0.4, accuracy: 0.001)
    }

    /// The flush and the debounced write both fire; the row must keep the newest payload once.
    func testFlushThenDebounceKeepsTheNewestRevision() async throws {
        let database = try makeDatabase()
        let camera = FakeSessionCamera()
        let model = makeModel(
            camera: camera,
            store: GRDBCameraSettingsStore(database: database),
            debounce: 60_000_000
        )
        await waitUntil { model.initialMergeDone }

        model.setGuideOpacity(0.2)
        model.setGuideOpacity(0.7)
        await model.flushSettings()

        try await Task.sleep(nanoseconds: 250_000_000)

        let storedRow = try await snapshotRow(database)
        let row = try XCTUnwrap(storedRow)
        let stored = try XCTUnwrap(CameraSettings.decode(row.settingsJSON))
        XCTAssertEqual(stored.guideOpacity, 0.7, accuracy: 0.001)
        let rows = try await countRows(database)
        XCTAssertEqual(rows, 1)
    }

    /// P2-a: the restored placement is not on screen yet (no guide), but it is still the placement
    /// the user left behind. Changing an unrelated setting must not turn it into identity on disk,
    /// otherwise the next launch restores nothing.
    func testAnUnrelatedEditBeforeAnyGuideKeepsTheRestoredPlacementOnDisk() async throws {
        let database = try makeDatabase()
        let placement = CameraSettings.Transform(scale: 1.7, rotationDegrees: 12, offsetX: 24, offsetY: -8)
        try await GRDBCameraSettingsStore(database: database)
            .save(makeSettings(revision: 3, transform: placement))

        let camera = FakeSessionCamera()
        let model = makeModel(camera: camera, store: GRDBCameraSettingsStore(database: database))
        await waitUntil { model.initialMergeDone }
        XCTAssertEqual(model.guideTransform, GuideTransform(), "the placement waits for a guide")

        model.toggleGrid()
        await model.flushSettings()

        let storedRow = try await snapshotRow(database)
        let stored = try XCTUnwrap(CameraSettings.decode(try XCTUnwrap(storedRow).settingsJSON))
        XCTAssertTrue(stored.isGridVisible, "the untouched setting still changed")
        XCTAssertEqual(stored.transform, placement, "the pending placement survives an unrelated edit")

        // And it is still the placement the next launch applies to its first guide.
        let relaunched = makeModel(camera: FakeSessionCamera(), store: GRDBCameraSettingsStore(database: database))
        await waitUntil { relaunched.initialMergeDone }
        relaunched.guideDidChange(hasGuide: true)
        XCTAssertEqual(relaunched.guideTransform.scale, 1.7, accuracy: 0.001)
        XCTAssertEqual(relaunched.guideTransform.offset, CGSize(width: 24, height: -8))
    }

    /// P2-b: resetting on a pose change is what the user sees, so the row has to follow it. Before
    /// this was fixed the reset was invisible to persistence and the old placement came back on the
    /// next launch even though the screen showed the reference reset.
    func testSelectingAnotherGuidePersistsTheVisibleReset() async throws {
        let database = try makeDatabase()
        try await GRDBCameraSettingsStore(database: database).save(makeSettings(
            revision: 2,
            transform: .init(scale: 1.8, rotationDegrees: 20, offsetX: 30, offsetY: -10)
        ))

        let camera = FakeSessionCamera()
        let model = makeModel(camera: camera, store: GRDBCameraSettingsStore(database: database))
        await waitUntil { model.initialMergeDone }

        model.guideDidChange(hasGuide: true)
        XCTAssertEqual(model.guideTransform.scale, 1.8, accuracy: 0.001, "the first guide keeps the placement")

        model.guideDidChange(hasGuide: true)
        XCTAssertEqual(model.guideTransform, GuideTransform(), "a later pose change resets, as today")
        await model.flushSettings()

        let storedRow = try await snapshotRow(database)
        let stored = try XCTUnwrap(CameraSettings.decode(try XCTUnwrap(storedRow).settingsJSON))
        XCTAssertEqual(stored.transform, CameraSettings.Transform(), "what is on screen is what comes back")
    }

    func testThrowingStoreDoesNotBreakTheCamera() async throws {
        let camera = FakeSessionCamera()
        let store = MemorySettingsStore(seed: nil)
        let model = makeModel(camera: camera, store: store, debounce: 20_000_000)
        await waitUntil { model.initialMergeDone }
        await store.setFailing(true)

        model.setGuideOpacity(0.8)
        model.toggleGrid()
        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(model.guideOpacity, 0.8, accuracy: 0.001)
        XCTAssertTrue(model.isGridVisible)
        XCTAssertTrue(model.cameraControlsEnabled)
    }

    func testRelaunchKeepsTheRevisionCounterMonotonic() async throws {
        let database = try makeDatabase()
        let store = GRDBCameraSettingsStore(database: database)
        try await store.save(makeSettings(revision: 5, opacity: 0.7, flash: .on))

        let camera = FakeSessionCamera()
        let model = makeModel(camera: camera, store: store, debounce: 5_000_000)
        await waitUntil { model.initialMergeDone }
        XCTAssertEqual(model.guideOpacity, 0.7, accuracy: 0.001)

        model.setGuideOpacity(0.15)
        await model.flushSettings()

        let storedRow = try await snapshotRow(database)
        let row = try XCTUnwrap(storedRow)
        let stored = try XCTUnwrap(CameraSettings.decode(row.settingsJSON))
        XCTAssertEqual(stored.guideOpacity, 0.15, accuracy: 0.001)
        XCTAssertEqual(stored.flash, .on, "the untouched settings are still on disk")
        XCTAssertEqual(stored.revision, 6)
    }

    // MARK: - Fixtures and helpers

    private func makeSettings(
        revision: Int64 = 0,
        opacity: Double = 0.5,
        flipped: Bool = false,
        grid: Bool = false,
        flash: CameraFlashSetting = .auto,
        guideVisible: Bool = true,
        lineColor: GuideLineColor = .black,
        transform: CameraSettings.Transform = .init(),
        zoom: CameraZoomLevel = .one
    ) -> CameraSettings {
        CameraSettings(
            revision: revision,
            guideOpacity: opacity,
            guideFlipped: flipped,
            isGridVisible: grid,
            flash: flash,
            isPoseGuideVisible: guideVisible,
            lineColor: lineColor,
            transform: transform,
            zoom: zoom
        )
    }

    private func makeModel(
        camera: FakeSessionCamera,
        store: any CameraSettingsStore,
        debounce: UInt64 = 5_000_000
    ) -> CameraViewModel {
        CameraViewModel(
            camera: camera,
            photoMetadata: InMemoryCapturePhotoMetadata(),
            settingsStore: store,
            saveDebounceNanoseconds: debounce
        )
    }

    private func makeDatabase() throws -> AppDatabase {
        let url = root.appendingPathComponent("aipose.db")
        return try AppDatabase(location: AppDatabaseLocation(url: url, kind: .freshInstall))
    }

    private func snapshotRow(_ database: AppDatabase) async throws -> CameraSnapshotRecord? {
        try await database.pool.read { db in try CameraSnapshotRecord.fetchOne(db, key: 1) }
    }

    private func countRows(_ database: AppDatabase) async throws -> Int {
        try await database.pool.read { db in try CameraSnapshotRecord.fetchCount(db) }
    }

    /// The app is main-actor bound; a test helper has to yield the main actor for the restore and
    /// debounce tasks to make progress.
    private func waitUntil(
        timeout: TimeInterval = 3,
        _ condition: () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("condition not met within \(timeout)s", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }
}

// MARK: - Doubles

@MainActor
private final class FakeSessionCamera: CameraSessionControlling {
    var permission: CameraPermissionState = .authorized
    private(set) var isSessionRunning = false
    private(set) var flashCalls: [CameraFlashSetting] = []
    private(set) var zoomCalls: [CGFloat] = []
    private(set) var startCalls = 0

    let session = AVCaptureSession()
    var facing: CameraFacing = .back

    func currentPermissionState() -> CameraPermissionState { permission }

    func requestPermission(onResult: @escaping @Sendable (CameraPermissionState) -> Void) {
        onResult(permission)
    }

    func capture(captureId: String, onResult: @escaping @Sendable (CameraCaptureResult) -> Void) {}
    func cancelCapture() {}
    func switchCamera() {}

    func setFlashMode(_ mode: CameraFlashSetting) { flashCalls.append(mode) }
    func setTorchEnabled(_ enabled: Bool) {}
    func setZoomFactor(_ factor: CGFloat) { zoomCalls.append(factor) }

    func start() async throws {
        startCalls += 1
        isSessionRunning = true
    }

    func stop() { isSessionRunning = false }
}

private enum StoreFailure: Error {
    case unavailable
}

/// In-memory store that records every write, so a test can count them.
private actor MemorySettingsStore: CameraSettingsStore {
    private var stored: CameraSettings?
    private var failing = false
    private(set) var saved: [CameraSettings] = []

    init(seed: CameraSettings?) {
        stored = seed
    }

    func setFailing(_ value: Bool) {
        failing = value
    }

    func load() async throws -> CameraSettings? { stored }

    func save(_ settings: CameraSettings) async throws {
        if failing { throw StoreFailure.unavailable }
        saved.append(settings)
        stored = settings
    }
}

/// Store whose `load` does not return until the test says so — the only reliable way to hold a
/// restore open while the user (or the session) moves on.
private actor BlockingSettingsStore: CameraSettingsStore {
    private var stored: CameraSettings?
    private var loadStarted = false
    private var waiters: [CheckedContinuation<CameraSettings?, Never>] = []
    private(set) var saved: [CameraSettings] = []

    init(seed: CameraSettings? = nil) {
        stored = seed
    }

    func load() async throws -> CameraSettings? {
        loadStarted = true
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func save(_ settings: CameraSettings) async throws {
        saved.append(settings)
        stored = settings
    }

    func waitUntilLoadStarted() async {
        while !loadStarted {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    func completeLoad(_ settings: CameraSettings?) {
        stored = settings
        let pending = waiters
        waiters = []
        for waiter in pending { waiter.resume(returning: settings) }
    }
}
