import AVFoundation
import XCTest
@testable import iosApp

@MainActor
final class CameraCoordinatorTests: XCTestCase {
    @MainActor
    private final class FakeCameraController: CameraControllerPort {
        var permission: CameraPermissionState = .notDetermined
        var captureCalls = 0
        var cancelCaptureCalls = 0
        let session = AVCaptureSession()
        var facing: CameraFacing = .back
        private var permissionCallback: ((CameraPermissionState) -> Void)?
        private var captureCallback: ((CameraCaptureResult) -> Void)?

        func currentPermissionState() -> CameraPermissionState { permission }
        func requestPermission(onResult: @escaping @Sendable (CameraPermissionState) -> Void) {
            permissionCallback = onResult
        }
        func capture(captureId: String, onResult: @escaping @Sendable (CameraCaptureResult) -> Void) {
            captureCalls += 1
            if captureCallback != nil {
                onResult(.failure)
                return
            }
            captureCallback = onResult
        }
        func cancelCapture() {
            cancelCaptureCalls += 1
            captureCallback = nil
        }
        func switchCamera() {}
        func setFlashMode(_ mode: CameraFlashSetting) {}
        func setTorchEnabled(_ enabled: Bool) {}

        func grant(_ permission: CameraPermissionState) {
            self.permission = permission
            permissionCallback?(permission)
            permissionCallback = nil
        }

        func deliverSuccess(_ bytes: Data) {
            captureCallback?(.success(bytes))
            captureCallback = nil
        }

        func deliverFailure() {
            captureCallback?(.failure)
            captureCallback = nil
        }
    }

    private final class FakeImageWriter: CaptureImageWriter, @unchecked Sendable {
        var files: [String: Data] = [:]
        var failNextWrite = false
        var failNextVerify = false
        var deleted: [String] = []

        func writeJpeg(_ bytes: Data, captureId: String) -> String? {
            if failNextWrite {
                failNextWrite = false
                return nil
            }
            let name = "capture_\(captureId).jpg"
            files[name] = bytes
            return name
        }

        func verify(filename: String) -> Bool {
            if failNextVerify {
                failNextVerify = false
                return false
            }
            return files[filename]?.isEmpty == false
        }

        func delete(filename: String) {
            files.removeValue(forKey: filename)
            deleted.append(filename)
        }
    }

    private final class FakeClock: CameraClock, @unchecked Sendable {
        var now: Int64 = 1_000
        func nowMillis() -> Int64 { now }
        func advance(_ ms: Int64) { now += ms }
    }

    private final class FixedIdGenerator: CameraIdGenerator, @unchecked Sendable {
        private var ids: [String]
        init(ids: [String]) { self.ids = ids }
        func nextCaptureId() -> String { ids.isEmpty ? "id-0" : ids.removeFirst() }
    }

    private func makeCoordinator(
        writer: FakeImageWriter = FakeImageWriter(),
        metadata: InMemoryCapturePhotoMetadata = InMemoryCapturePhotoMetadata(),
        clock: FakeClock = FakeClock(),
        ids: [String] = ["cap-1"]
    ) -> (CameraCoordinator, FakeCameraController, FakeImageWriter, InMemoryCapturePhotoMetadata, FakeClock) {
        makeCoordinator(controller: FakeCameraController(), writer: writer, metadata: metadata, clock: clock, ids: ids)
    }

    private func makeCoordinator<C: CameraControllerPort>(
        controller: C,
        writer: FakeImageWriter = FakeImageWriter(),
        metadata: InMemoryCapturePhotoMetadata = InMemoryCapturePhotoMetadata(),
        clock: FakeClock = FakeClock(),
        ids: [String] = ["cap-1"]
    ) -> (CameraCoordinator, C, FakeImageWriter, InMemoryCapturePhotoMetadata, FakeClock) {
        let coordinator = CameraCoordinator(
            controller: controller,
            imageStorage: writer,
            photoMetadata: metadata,
            clock: clock,
            idGenerator: FixedIdGenerator(ids: ids),
            captureTimeoutMillis: 10_000
        )
        return (coordinator, controller, writer, metadata, clock)
    }

    private final class CaptureCallbackBox: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var callbackCount = 0
        private(set) var received: CameraCaptureResult?

        func record(_ result: CameraCaptureResult) {
            lock.lock()
            callbackCount += 1
            received = result
            lock.unlock()
        }
    }

    private func awaitCoordinatorPhase(
        _ coordinator: CameraCoordinator,
        timeoutNanoseconds: UInt64 = 500_000_000,
        matches: (CameraPhase) -> Bool,
        file: StaticString = #file,
        line: UInt = #line
    ) async {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if matches(coordinator.state.phase) { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Timed out waiting for coordinator phase: \(coordinator.state.phase)", file: file, line: line)
    }

    func testLaunchRequestsPermissionWhenNotDetermined() async {
        let (coordinator, controller, _, _, _) = makeCoordinator()
        coordinator.onLaunch()
        controller.grant(.authorized)
        await awaitCoordinatorPhase(coordinator) { phase in
            if case .previewReady = phase { return true }
            return false
        }
        XCTAssertEqual(coordinator.state.phase, .previewReady)
    }

    func testDeniedPermissionStaysGated() {
        let controller = FakeCameraController()
        controller.permission = .denied
        let (coordinator, _, _, _, _) = makeCoordinator(controller: controller)
        coordinator.onLaunch()
        XCTAssertEqual(coordinator.state.phase, .permissionRequired)
    }

    func testCaptureSuccessPersistsMetadata() async {
        let (coordinator, controller, writer, metadata, _) = makeCoordinator()
        coordinator.onPermissionResult(.authorized)
        XCTAssertTrue(coordinator.onCaptureRequested())
        controller.deliverSuccess(Data([0xFF, 0xD8, 0xFF]))
        try? await Task.sleep(nanoseconds: 100_000_000)
        guard case .captureSucceeded(_, let photo) = coordinator.state.phase else {
            return XCTFail("expected success, got \(coordinator.state.phase)")
        }
        XCTAssertEqual(photo.imagePath, "capture_cap-1.jpg")
        XCTAssertEqual(writer.files.count, 1)
        let latest = try? await metadata.getLatestPhotoPath()
        XCTAssertEqual(latest, photo.imagePath)
    }

    func testEmptyBytesFailsWithoutWrite() async {
        let (coordinator, controller, writer, _, _) = makeCoordinator()
        coordinator.onPermissionResult(.authorized)
        coordinator.onCaptureRequested()
        controller.deliverSuccess(Data())
        await awaitCoordinatorPhase(coordinator) { phase in
            if case .captureError = phase { return true }
            return false
        }
        guard case .captureError(_, let failure) = coordinator.state.phase else {
            return XCTFail("expected capture error, got \(coordinator.state.phase)")
        }
        XCTAssertEqual(failure, .emptyBytes)
        XCTAssertTrue(writer.files.isEmpty)
    }

    func testWriteFailureSurfacesError() async {
        let writer = FakeImageWriter()
        writer.failNextWrite = true
        let (coordinator, controller, _, _, _) = makeCoordinator(writer: writer)
        coordinator.onPermissionResult(.authorized)
        coordinator.onCaptureRequested()
        controller.deliverSuccess(Data([1, 2, 3]))
        try? await Task.sleep(nanoseconds: 100_000_000)
        guard case .captureError(_, let failure) = coordinator.state.phase else {
            return XCTFail("expected write failure")
        }
        XCTAssertEqual(failure, .writeFailed)
    }

    func testMetadataFailureDeletesFile() async {
        let metadata = InMemoryCapturePhotoMetadata()
        await metadata.setFailNextInsert(true)
        let (coordinator, controller, writer, _, _) = makeCoordinator(metadata: metadata)
        coordinator.onPermissionResult(.authorized)
        coordinator.onCaptureRequested()
        controller.deliverSuccess(Data([9, 8, 7]))
        try? await Task.sleep(nanoseconds: 100_000_000)
        guard case .captureError(_, let failure) = coordinator.state.phase else {
            return XCTFail("expected metadata failure")
        }
        XCTAssertEqual(failure, .metadataInsertFailed)
        XCTAssertEqual(writer.deleted, ["capture_cap-1.jpg"])
    }

    func testCaptureTimeoutCancelsNativeCapture() {
        let (coordinator, controller, _, _, clock) = makeCoordinator()
        coordinator.onPermissionResult(.authorized)
        coordinator.onCaptureRequested()
        clock.advance(10_001)
        coordinator.onCaptureTimeoutTick()
        XCTAssertEqual(controller.cancelCaptureCalls, 1)
        guard case .captureError(_, let failure) = coordinator.state.phase else {
            return XCTFail("expected timeout")
        }
        XCTAssertEqual(failure, .timeout)
    }

    func testBackgroundDuringCaptureCancelsAndReturnsToPreview() {
        let (coordinator, controller, _, _, _) = makeCoordinator()
        coordinator.onPermissionResult(.authorized)
        XCTAssertTrue(coordinator.onCaptureRequested())
        coordinator.onBackground()
        XCTAssertEqual(controller.cancelCaptureCalls, 1)
        XCTAssertEqual(coordinator.state.phase, .previewReady)
        XCTAssertEqual(coordinator.state.lifecycle, .inactive)
    }

    func testNativeCaptureFailsImmediatelyWhenSessionNotRunning() {
        let controller = NativeCameraController()
        let box = CaptureCallbackBox()
        controller.capture(captureId: "unavailable") { result in
            box.record(result)
        }
        XCTAssertEqual(box.callbackCount, 1)
        XCTAssertEqual(box.received, .failure)
        XCTAssertFalse(controller.isRunning)
    }

    func testSecondCaptureBlockedWhileCapturing() {
        let (coordinator, controller, _, _, _) = makeCoordinator()
        coordinator.onPermissionResult(.authorized)
        XCTAssertTrue(coordinator.onCaptureRequested())
        XCTAssertFalse(coordinator.onCaptureRequested())
        XCTAssertEqual(controller.captureCalls, 1)
    }

    func testUnavailableNativeCaptureSurfacesCoordinatorError() async {
        let controller = NativeCameraController()
        let (coordinator, _, writer, _, _) = makeCoordinator(controller: controller)
        coordinator.onPermissionResult(CameraPermissionState.authorized)
        XCTAssertTrue(coordinator.onCaptureRequested())
        await awaitCoordinatorPhase(coordinator) { phase in
            if case .captureError = phase { return true }
            return false
        }
        guard case .captureError(_, let failure) = coordinator.state.phase else {
            return XCTFail("expected capture error, got \(coordinator.state.phase)")
        }
        XCTAssertEqual(failure, CaptureFailure.emptyBytes)
        XCTAssertTrue(writer.files.isEmpty)
    }

    func testGuideOpacityAndFlipDefaults() {
        let model = CameraViewModel()
        // Prototype default is 50%: `camera-live.html` renders `<output id="pose-opacity-value">50%</output>`
        // for `<input id="pose-opacity-slider" min="0.1" max="1" step="0.05" value="0.5">`, and
        // `camera-viewport.css` / the Camera Tools popup spec in UI-CHANGE-260913 §3.2 keep it at 50%.
        // The previous 0.55 was not traceable to the prototype. Synced by DL-A in the merge gate.
        XCTAssertEqual(model.guideOpacity, 0.5, accuracy: 0.001)
        XCTAssertFalse(model.guideFlipped)
        model.guideFlipped = true
        model.guideOpacity = 0.2
        XCTAssertTrue(model.guideFlipped)
        XCTAssertEqual(model.guideOpacity, 0.2, accuracy: 0.001)
    }
}

// MARK: - Front-lens mirroring (the saved photo is the frame the preview showed)

/// The preview layer mirrors the front camera (AVFoundation's own default), so the photo connection has to
/// mirror as well. Without it a selfie is saved flipped against the frame — and the pose guide — the user
/// lined up on screen.
@MainActor
final class CameraCaptureMirroringTests: XCTestCase {
    /// Stands in for `AVCaptureConnection`, which cannot be built without a real capture device (the
    /// simulator has none).
    private final class FakeConnection: VideoMirroringConnection {
        var isVideoMirroringSupported = true
        var automaticallyAdjustsVideoMirroring = true
        var isVideoMirrored = false
    }

    func testTheFrontLensSavesTheMirrorThePreviewShows() {
        XCTAssertTrue(CameraCaptureMirroring.isMirrored(facing: .front))
        XCTAssertFalse(
            CameraCaptureMirroring.isMirrored(facing: .back),
            "the back lens is saved exactly as the sensor delivers it"
        )

        let front = FakeConnection()
        CameraCaptureMirroring.configure(front, facing: .front)
        XCTAssertTrue(front.isVideoMirrored)
        XCTAssertFalse(
            front.automaticallyAdjustsVideoMirroring,
            "the decision is ours: AVFoundation may not re-adjust it behind the app"
        )

        let back = FakeConnection()
        CameraCaptureMirroring.configure(back, facing: .back)
        XCTAssertFalse(back.isVideoMirrored)
        XCTAssertFalse(back.automaticallyAdjustsVideoMirroring)

        // Switching lenses re-decides the mirror instead of stacking another one.
        CameraCaptureMirroring.configure(front, facing: .back)
        XCTAssertFalse(front.isVideoMirrored, "no double flip after a switch back to the rear lens")
    }

    /// A connection that cannot mirror is left alone rather than told to.
    func testAnUnsupportedConnectionKeepsItsOwnMirroring() {
        let connection = FakeConnection()
        connection.isVideoMirroringSupported = false
        CameraCaptureMirroring.configure(connection, facing: .front)
        XCTAssertTrue(connection.automaticallyAdjustsVideoMirroring)
        XCTAssertFalse(connection.isVideoMirrored)
    }
}
