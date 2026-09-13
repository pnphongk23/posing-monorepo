import Foundation

@MainActor
final class CameraCoordinator: ObservableObject {
    @Published private(set) var state = CameraCoordinatorState()
    let captureTimeoutMillis: Int64

    private let controller: CameraControllerPort
    private let imageStorage: CaptureImageWriter
    private let photoMetadata: CapturePhotoMetadata
    private let clock: CameraClock
    private let idGenerator: CameraIdGenerator
    private var captureStartedAtMillis: Int64 = 0
    private let poseId: String?
    private let poseName: String

    init(
        controller: CameraControllerPort,
        imageStorage: CaptureImageWriter,
        photoMetadata: CapturePhotoMetadata,
        clock: CameraClock = SystemClock(),
        idGenerator: CameraIdGenerator = TimestampCounterIdGenerator(),
        captureTimeoutMillis: Int64 = 10_000,
        poseId: String? = nil,
        poseName: String = ""
    ) {
        self.controller = controller
        self.imageStorage = imageStorage
        self.photoMetadata = photoMetadata
        self.clock = clock
        self.idGenerator = idGenerator
        self.captureTimeoutMillis = captureTimeoutMillis
        self.poseId = poseId
        self.poseName = poseName
        state.permission = controller.currentPermissionState()
    }

    func onLaunch() {
        let permission = controller.currentPermissionState()
        state.permission = permission
        switch permission {
        case .notDetermined:
            controller.requestPermission { [weak self] result in
                Task { @MainActor in self?.onPermissionResult(result) }
            }
        case .authorized:
            state.phase = .previewReady
        case .denied, .restricted:
            state.phase = .permissionRequired
        }
    }

    func onPermissionResult(_ permission: CameraPermissionState) {
        state.permission = permission
        state.phase = permission == .authorized ? .previewReady : .permissionRequired
    }

    @discardableResult
    func onCaptureRequested() -> Bool {
        guard state.captureEnabled else { return false }
        let captureId = idGenerator.nextCaptureId()
        captureStartedAtMillis = clock.nowMillis()
        state.lastFailure = nil
        state.phase = .capturing(captureId: captureId)
        controller.capture(captureId: captureId) { [weak self] result in
            Task { @MainActor in self?.onCaptureResult(captureId: captureId, result: result) }
        }
        return true
    }

    func onCaptureResult(captureId: String, result: CameraCaptureResult) {
        guard case .capturing(let activeId) = state.phase, activeId == captureId else { return }
        switch result {
        case .failure:
            failCapture(captureId: captureId, failure: .emptyBytes)
        case .success(let data):
            if data.isEmpty {
                failCapture(captureId: captureId, failure: .emptyBytes)
            } else {
                state.phase = .persisting(captureId: captureId)
                Task { await persist(captureId: captureId, bytes: data) }
            }
        }
    }

    func onCaptureTimeoutTick() {
        guard case .capturing(let captureId) = state.phase else { return }
        guard clock.nowMillis() - captureStartedAtMillis >= captureTimeoutMillis else { return }
        controller.cancelCapture()
        state.phase = .captureError(captureId: captureId, failure: .timeout)
        state.lastFailure = .timeout
    }

    func onBackground() {
        let dropped = state.isCaptureInFlight
        if dropped { controller.cancelCapture() }
        state.lifecycle = .inactive
        if dropped { state.phase = .previewReady }
    }

    func onForeground() {
        state.lifecycle = .active
    }

    func dismissResult() {
        switch state.phase {
        case .captureSucceeded, .captureError:
            state.phase = .previewReady
        default:
            break
        }
    }

    func refreshLatestThumbnail() async {
        if let path = try? await photoMetadata.getLatestPhotoPath() {
            state.thumbnailPath = path
        }
    }

    private func failCapture(captureId: String, failure: CaptureFailure) {
        state.phase = .captureError(captureId: captureId, failure: failure)
        state.lastFailure = failure
    }

    private func persist(captureId: String, bytes: Data) async {
        guard let filename = imageStorage.writeJpeg(bytes, captureId: captureId) else {
            failCapture(captureId: captureId, failure: .writeFailed)
            return
        }
        guard imageStorage.verify(filename: filename) else {
            imageStorage.delete(filename: filename)
            failCapture(captureId: captureId, failure: .writeFailed)
            return
        }
        do {
            let id = try await photoMetadata.insertCapturedPhoto(
                imagePath: filename,
                poseId: poseId,
                poseName: poseName
            )
            guard id > 0 else {
                imageStorage.delete(filename: filename)
                failCapture(captureId: captureId, failure: .metadataInsertFailed)
                return
            }
            let record = CapturedPhotoRecord(id: id, imagePath: filename)
            state.phase = .captureSucceeded(captureId: captureId, photo: record)
            state.thumbnailPath = filename
            state.lastFailure = nil
        } catch {
            imageStorage.delete(filename: filename)
            failCapture(captureId: captureId, failure: .metadataInsertFailed)
        }
    }
}
