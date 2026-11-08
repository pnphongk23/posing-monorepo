import AVFoundation
import UIKit

enum CameraFailure: LocalizedError {
    case permissionDenied, unavailable, captureFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Camera access is required."
        case .unavailable: return "Camera is unavailable."
        case .captureFailed: return "Could not take the photo."
        }
    }
}

/// Everything that belongs to the capture session, and nothing else.
///
/// Why this exists: `AVCaptureSession` is not thread-safe, and the session-shaped calls are
/// *blocking* — `beginConfiguration()`/`commitConfiguration()`, `startRunning()` (waits for the
/// hardware to spin up), `stopRunning()`, the `videoZoomFactor` ramp and the torch switch. All of
/// them used to run inside `@MainActor` methods, i.e. on the main thread, which is exactly what made
/// the first tap on the Camera tab feel like a freeze: SwiftUI could not finish the tab transition
/// until the session had configured and started.
///
/// The safety rule that makes the unchecked `Sendable` conformance honest: `NativeCameraController.sessionQueue`
/// is the only thread that touches this box. The one exception is reading the immutable `session`
/// reference on the main thread, because `AVCaptureVideoPreviewLayer` has to be given the session
/// object itself — the layer observes the session internally, and that is the pattern Apple's own
/// AVCam sample uses.
private final class CameraSessionBox: @unchecked Sendable {
    let session = AVCaptureSession()
    let output = AVCapturePhotoOutput()
    var deviceInput: AVCaptureDeviceInput?
    var facing: CameraFacing = .back
    var flashSetting: CameraFlashSetting = .off
    /// How a display zoom reaches this device's `videoZoomFactor` (see `CameraLensProfile`).
    var zoomProfile: CameraLensProfile = .wideOnly

    var isPhotoCaptureReady: Bool {
        guard session.isRunning else { return false }
        guard session.outputs.contains(where: { $0 === output }) else { return false }
        guard let connection = output.connection(with: .video) else { return false }
        return connection.isEnabled && connection.isActive
    }

    func configure(position: AVCaptureDevice.Position) throws {
        guard let device = CameraLensDiscovery.device(for: position) else {
            throw CameraFailure.unavailable
        }
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        // The preview and the still must describe the same picture: the photo preset keeps the video
        // stream on the still's 4:3 sensor field of view, so the ratio crop contains only what the user
        // framed instead of the extra content a 16:9 stream would hide behind the frame.
        CameraSessionPreset.pinPhotoPreset(on: session)
        session.inputs.forEach(session.removeInput)
        if session.outputs.isEmpty, session.canAddOutput(output) {
            session.addOutput(output)
        }
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw CameraFailure.unavailable
        }
        session.addInput(input)
        deviceInput = input
        // Which lens set is running decides how a display factor reaches the hardware: on a virtual
        // multi-camera device 1.0 *is* the ultra-wide, so 1× means 2.0.
        zoomProfile = CameraLensDiscovery.profile(for: device)
        facing = position == .back ? .back : .front
        // The photo connection only exists once the configuration is committed.
        session.commitConfiguration()
        applyPhotoMirroringOnQueue()
        applyTorchOnQueue()
    }

    /// WYSIWYG: the saved frame carries the same mirror the preview shows (front) or none (back).
    func applyPhotoMirroringOnQueue() {
        CameraCaptureMirroring.configure(output.connection(with: .video), facing: facing)
    }

    func startRunningOnQueue() {
        logged("startRunning") {
            if !session.isRunning { session.startRunning() }
        }
        // The video connection is live by now; re-assert the mirror for the lens that ended up running.
        applyPhotoMirroringOnQueue()
    }

    func stopRunningOnQueue() {
        logged("stopRunning") {
            if session.isRunning { session.stopRunning() }
        }
    }

    func setZoomOnQueue(_ factor: CGFloat) {
        guard let device = deviceInput?.device else { return }
        logged("setZoomFactor") {
            try? device.lockForConfiguration()
            let minZ = device.minAvailableVideoZoomFactor
            let maxZ = min(device.maxAvailableVideoZoomFactor, 5.0 * zoomProfile.deviceMultiplier)
            device.videoZoomFactor = max(minZ, min(CameraZoomScale.lensFactor(forDisplay: factor, in: zoomProfile), maxZ))
            device.unlockForConfiguration()
        }
    }

    func setTorchOnQueue(enabled: Bool) {
        guard let device = deviceInput?.device, device.hasTorch else { return }
        logged("setTorch") {
            try? device.lockForConfiguration()
            device.torchMode = enabled ? .on : .off
            device.unlockForConfiguration()
        }
    }

    func applyTorchOnQueue() {
        guard let device = deviceInput?.device, device.hasTorch else { return }
        logged("torch") {
            try? device.lockForConfiguration()
            if facing == .back, flashSetting == .on {
                try? device.setTorchModeOn(level: 1)
            } else {
                device.torchMode = .off
            }
            device.unlockForConfiguration()
        }
    }

    /// Runs `body` on the queue it was called from and reports *which thread* ran it plus how long
    /// it took. That log is the checkable form of "no session work is left on the main thread";
    /// on the simulator `startRunning()` is a no-op (there is no camera device), so only a real
    /// device can say how long the hardware takes.
    @discardableResult
    func logged<T>(_ operation: String, _ body: () throws -> T) rethrows -> T {
        #if DEBUG
        let startedAt = Date()
        defer {
            NSLog(
                "%@",
                "AIPOSE_PERF camera_session op=\(operation) on_main=\(Thread.isMainThread) ms=\(Int(Date().timeIntervalSince(startedAt) * 1000))"
            )
        }
        return try body()
        #else
        return try body()
        #endif
    }
}

/// The mirroring the *saved* photo carries.
///
/// WYSIWYG selfie: `AVCaptureVideoPreviewLayer` mirrors the front camera (AVFoundation's own default), so the
/// photo connection has to mirror too — otherwise the frame the user lined up against the guide is saved
/// flipped, and the gallery shows the opposite of what the shutter froze. The back camera is left exactly as
/// the sensor delivers it. The tool popover's Mirror switch is unrelated: it flips the pose reference only
/// (`CameraViewModel.toggleGuideMirror`) and never reaches the capture pipeline.
enum CameraCaptureMirroring {
    static func isMirrored(facing: CameraFacing) -> Bool { facing == .front }

    /// Takes the decision away from AVFoundation (`automaticallyAdjustsVideoMirroring = false`) and applies
    /// it, so nothing re-adjusts the mirror when the input is swapped or the session restarts.
    static func configure(_ connection: VideoMirroringConnection?, facing: CameraFacing) {
        guard let connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = isMirrored(facing: facing)
    }
}

/// The two flags `CameraCaptureMirroring` owns, so the decision stays unit-testable without a capture
/// device: the simulator has none, and `AVCaptureConnection` cannot be constructed by hand.
protocol VideoMirroringConnection: AnyObject {
    var isVideoMirroringSupported: Bool { get }
    var automaticallyAdjustsVideoMirroring: Bool { get set }
    var isVideoMirrored: Bool { get set }
}

extension AVCaptureConnection: VideoMirroringConnection {}

// MARK: - Lens discovery (the AVFoundation side)

/// The hardware side of `CameraLensDiscovery`: which device to run, and what the UI may offer for it.
///
/// The virtual multi-camera devices are tried in order of field of view, because they are the only ones whose
/// `videoZoomFactor` can reach the ultra-wide: preferring `builtInWideAngleCamera` (the build-25 behaviour) hides
/// the 0.5× stop on a phone whose system camera has it. The front camera has no ultra-wide, so it falls through
/// to the wide (TrueDepth) device and the UI offers 1×…, exactly as before.
extension CameraLensDiscovery {
    /// Widest first: a device that includes the ultra-wide can also serve every stop above it.
    static let preferredDeviceTypes: [AVCaptureDevice.DeviceType] = [
        .builtInTripleCamera,
        .builtInDualWideCamera,
        .builtInWideAngleCamera,
    ]

    static func device(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        for type in preferredDeviceTypes {
            if let device = AVCaptureDevice.default(type, for: .video, position: position) {
                return device
            }
        }
        return AVCaptureDevice.default(for: .video)
    }

    /// Whether a device type's widest constituent is the ultra-wide. A `.builtInDualCamera` (wide + tele)
    /// reports a switch-over factor of 2 as well, but its 1.0 is the wide lens — it must never offer 0.5×.
    static func includesUltraWide(_ type: AVCaptureDevice.DeviceType) -> Bool {
        switch type {
        case .builtInTripleCamera, .builtInDualWideCamera, .builtInUltraWideCamera:
            return true
        default:
            return false
        }
    }

    static func profile(for device: AVCaptureDevice) -> CameraLensProfile {
        profile(
            minimumVideoZoom: device.minAvailableVideoZoomFactor,
            maximumVideoZoom: device.maxAvailableVideoZoomFactor,
            switchOverFactors: device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat($0.doubleValue) },
            includesUltraWide: includesUltraWide(device.deviceType)
        )
    }

    /// The profile of the lens set the camera would run for a facing, for a caller that only has the facing
    /// (the view model, deciding which buttons to draw).
    static func currentProfile(for facing: CameraFacing) -> CameraLensProfile {
        let position: AVCaptureDevice.Position = facing == .front ? .front : .back
        guard let device = device(for: position) else { return fallback }
        return profile(for: device)
    }
}

/// The preview's field of view, pinned to the still's.
///
/// `CameraSessionBox.configure` never set `sessionPreset`, so the video stream could be 16:9 while
/// `AVCapturePhotoOutput` returned full-sensor 4:3 stills: the ratio setting crops the still, and the
/// preview (aspect-filled into the frame) shows the centre of the 16:9 stream — the saved photo then holds
/// content around the frame that the user never saw. `.photo` makes both 4:3 of the same sensor.
///
/// The decision is separable from the session (the same shape as `CameraCaptureMirroring`) because a
/// session cannot be configured in a unit test: the simulator has no capture device to add.
enum CameraSessionPreset {
    /// The one preset the camera configures: the stills' own.
    static let photo: AVCaptureSession.Preset = .photo

    /// Pins the session to `.photo` when it can serve it, and leaves it exactly as it is otherwise — a
    /// device that refuses the preset keeps its current stream instead of losing the camera.
    static func pinPhotoPreset(on session: PhotoPresetSession) {
        guard session.sessionPreset != photo, session.canSetSessionPreset(photo) else { return }
        session.sessionPreset = photo
    }
}

/// The two `AVCaptureSession` members `CameraSessionPreset` owns, so the preset decision is
/// unit-testable without a capture device.
protocol PhotoPresetSession: AnyObject {
    var sessionPreset: AVCaptureSession.Preset { get set }
    func canSetSessionPreset(_ preset: AVCaptureSession.Preset) -> Bool
}

extension AVCaptureSession: PhotoPresetSession {}

/// Lets a `sessionQueue` closure hand a result back to the main-actor controller without capturing
/// the controller itself (which is not `Sendable`) inside a `@Sendable` closure.
private final class CameraOwnerTrampoline: @unchecked Sendable {
    weak var owner: NativeCameraController?
}

@MainActor
final class NativeCameraController: NSObject, ObservableObject, CameraSessionControlling {
    /// The only thread allowed to touch `CameraSessionBox`. Serial, so session configuration can
    /// never interleave with itself.
    private static let sessionQueue = DispatchQueue(label: "app.aipose.camera.session")

    private let box = CameraSessionBox()
    private let trampoline = CameraOwnerTrampoline()

    @Published private(set) var isRunning = false
    @Published private(set) var facing: CameraFacing = .back
    @Published var flashSetting: CameraFlashSetting = .off

    private var activeCaptureId: String?
    private var captureCallback: (@Sendable (CameraCaptureResult) -> Void)?

    override init() {
        super.init()
        trampoline.owner = self
    }

    /// Immutable reference; see `CameraSessionBox` for why reading it on the main thread is safe.
    var session: AVCaptureSession { box.session }

    /// `CameraSessionControlling` readiness: only a value the session itself reported counts, so a
    /// settings apply never runs against a session that is not up.
    var isSessionRunning: Bool { isRunning }

    func currentPermissionState() -> CameraPermissionState { .current() }

    func requestPermission(onResult: @escaping @Sendable (CameraPermissionState) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { _ in
                DispatchQueue.main.async { onResult(.current()) }
            }
        default:
            onResult(.current())
        }
    }

    /// Configures (if needed) and starts the session **on `sessionQueue`**, then publishes the
    /// result on the main actor. Nothing here blocks the main thread; `isRunning` is only set to a
    /// value that the session actually reports.
    func start() async throws {
        let permission = currentPermissionState()
        guard permission == .authorized else {
            throw CameraFailure.permissionDenied
        }
        let box = self.box
        let snapshot = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CameraSessionSnapshot, Error>) in
            Self.sessionQueue.async {
                do {
                    if box.session.inputs.isEmpty {
                        try box.logged("configure_start") {
                            try box.configure(position: box.facing == .back ? .back : .front)
                        }
                    }
                    box.startRunningOnQueue()
                    continuation.resume(returning: CameraSessionSnapshot(isRunning: box.session.isRunning, facing: box.facing))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        isRunning = snapshot.isRunning
        facing = snapshot.facing
    }

    func stop() {
        cancelCapture()
        isRunning = false
        let box = self.box
        Self.sessionQueue.async {
            box.stopRunningOnQueue()
        }
    }

    func switchCamera() {
        let previous = facing
        let target: CameraFacing = facing == .back ? .front : .back
        // `facing` keeps its old synchronous contract: it reflects the requested camera right away
        // and is rolled back if the session cannot switch. Only the blocking work moved to the queue.
        facing = target
        let box = self.box
        let trampoline = self.trampoline
        Self.sessionQueue.async {
            do {
                try box.logged("configure_switch") {
                    try box.configure(position: target == .back ? .back : .front)
                }
            } catch {
                Task { @MainActor in
                    trampoline.owner?.facing = previous
                }
            }
        }
    }

    func setFlashMode(_ mode: CameraFlashSetting) {
        flashSetting = mode
        let box = self.box
        Self.sessionQueue.async {
            box.flashSetting = mode
            box.applyTorchOnQueue()
        }
    }

    func setTorchEnabled(_ enabled: Bool) {
        let box = self.box
        Self.sessionQueue.async {
            box.setTorchOnQueue(enabled: enabled)
        }
    }

    func setZoomFactor(_ factor: CGFloat) {
        let box = self.box
        Self.sessionQueue.async {
            box.setZoomOnQueue(factor)
        }
    }

    /// Deliberately stays on the main actor. `capturePhoto(with:delegate:)` is not a blocking
    /// session-configuration call — it hands a request to AVFoundation — and this method's contract
    /// is that an unusable session reports `.failure` to `onResult` *inline*, which existing tests
    /// assert. Everything that can actually block the main thread (configuration, start/stop, zoom,
    /// torch) lives on `sessionQueue`.
    func capture(captureId: String, onResult: @escaping @Sendable (CameraCaptureResult) -> Void) {
        if captureCallback != nil {
            onResult(.failure)
            return
        }
        guard isPhotoCaptureReady else {
            onResult(.failure)
            return
        }
        activeCaptureId = captureId
        captureCallback = onResult
        let settings = AVCapturePhotoSettings()
        if box.output.supportedFlashModes.contains(flashSetting.avFlashMode) {
            settings.flashMode = flashSetting.avFlashMode
        }
        box.output.capturePhoto(with: settings, delegate: self)
    }

    func cancelCapture() {
        captureCallback = nil
        activeCaptureId = nil
    }

    func capture() async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            capture(captureId: "legacy") { result in
                switch result {
                case .success(let bytes):
                    guard let image = UIImage(data: bytes) else {
                        continuation.resume(throwing: CameraFailure.captureFailed)
                        return
                    }
                    continuation.resume(returning: image)
                case .failure:
                    continuation.resume(throwing: CameraFailure.captureFailed)
                }
            }
        }
    }

    private var isPhotoCaptureReady: Bool {
        guard isRunning, box.session.isRunning else { return false }
        guard box.session.outputs.contains(where: { $0 === box.output }) else { return false }
        guard let connection = box.output.connection(with: .video) else { return false }
        return connection.isEnabled && connection.isActive
    }
}

/// Snapshot handed back from `sessionQueue`, so the main actor never reads queue-owned state.
private struct CameraSessionSnapshot: Sendable {
    let isRunning: Bool
    let facing: CameraFacing
}

extension NativeCameraController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let hasError = error != nil
        let data = hasError ? nil : photo.fileDataRepresentation()
        Task { @MainActor in
            let callback = captureCallback
            captureCallback = nil
            activeCaptureId = nil
            if hasError {
                callback?(.failure)
                return
            }
            guard let data, !data.isEmpty else {
                callback?(.failure)
                return
            }
            callback?(.success(data))
        }
    }
}
