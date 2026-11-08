import AVFoundation
import Foundation

@MainActor
protocol CameraControllerPort: AnyObject {
    func currentPermissionState() -> CameraPermissionState
    func requestPermission(onResult: @escaping @Sendable (CameraPermissionState) -> Void)
    func capture(captureId: String, onResult: @escaping @Sendable (CameraCaptureResult) -> Void)
    func cancelCapture()
    func switchCamera()
    func setFlashMode(_ mode: CameraFlashSetting)
    func setTorchEnabled(_ enabled: Bool)
    func setZoomFactor(_ factor: CGFloat)
    var session: AVCaptureSession { get }
    var facing: CameraFacing { get }
    /// What lenses this camera has, in display zoom space: the stops the UI offers come from here.
    var lensProfile: CameraLensProfile { get }
}

/// The camera as the view model drives it: the port above plus the session lifecycle. Readiness is
/// the return of `start()` together with `isSessionRunning`, which is the point where settings that
/// live on the hardware (flash, zoom) can actually be applied.
@MainActor
protocol CameraSessionControlling: CameraControllerPort {
    func start() async throws
    func stop()
    var isSessionRunning: Bool { get }
}

extension CameraControllerPort {
    func setZoomFactor(_ factor: CGFloat) {}

    /// What lenses this camera has, in display zoom space — which decides the stops the UI offers and how a
    /// display factor reaches the lens. The default reads the hardware; a stub camera overrides it, because the
    /// simulator has no capture device (it then falls back to `CameraLensProfile.wideOnly`, 1×…2×).
    var lensProfile: CameraLensProfile { CameraLensDiscovery.currentProfile(for: facing) }
}

protocol CaptureImageWriter: Sendable {
    func writeJpeg(_ bytes: Data, captureId: String) -> String?
    func verify(filename: String) -> Bool
    func delete(filename: String)
}

protocol CapturePhotoMetadata: Sendable {
    func insertCapturedPhoto(imagePath: String, poseId: String?, poseName: String) async throws -> Int64
    func getLatestPhotoPath() async throws -> String?
}

protocol CameraClock: Sendable {
    func nowMillis() -> Int64
}

protocol CameraIdGenerator: Sendable {
    func nextCaptureId() -> String
}

struct SystemClock: CameraClock, Sendable {
    func nowMillis() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
}

final class TimestampCounterIdGenerator: CameraIdGenerator, @unchecked Sendable {
    private let clock: CameraClock
    private var counter: Int64 = 0

    init(clock: CameraClock = SystemClock()) { self.clock = clock }

    func nextCaptureId() -> String {
        let id = "\(clock.nowMillis())-\(counter)"
        counter += 1
        return id
    }
}

actor InMemoryCapturePhotoMetadata: CapturePhotoMetadata {
    private var rows: [CapturedPhotoRecord] = []
    private var nextId: Int64 = 1
    var failNextInsert = false

    func insertCapturedPhoto(imagePath: String, poseId: String?, poseName: String) async throws -> Int64 {
        if failNextInsert {
            failNextInsert = false
            throw NSError(domain: "test", code: 1)
        }
        let id = nextId
        nextId += 1
        rows.append(CapturedPhotoRecord(id: id, imagePath: imagePath))
        return id
    }

    func getLatestPhotoPath() async throws -> String? {
        rows.last?.imagePath
    }

    func setFailNextInsert(_ value: Bool) {
        failNextInsert = value
    }
}

struct PhotoRepositoryMetadataAdapter: CapturePhotoMetadata, Sendable {
    let repository: PhotoRepository

    func insertCapturedPhoto(imagePath: String, poseId: String?, poseName: String) async throws -> Int64 {
        let record = PhotoRecord(
            id: nil,
            imagePath: imagePath,
            poseId: poseId,
            poseName: poseName,
            createdAt: String(Int64(Date().timeIntervalSince1970 * 1000)),
            isFavorite: 0
        )
        return try await repository.insert(record)
    }

    func getLatestPhotoPath() async throws -> String? {
        try await repository.all().first?.imagePath
    }
}
