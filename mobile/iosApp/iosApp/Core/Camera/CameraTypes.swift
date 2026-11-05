import AVFoundation
import Foundation

enum CameraPermissionState: Equatable, Sendable {
    case notDetermined, authorized, denied, restricted

    static func current() -> CameraPermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }
}

enum CameraFlashSetting: Equatable, Sendable {
    case off, on, auto

    var avFlashMode: AVCaptureDevice.FlashMode {
        switch self {
        case .off: return .off
        case .on: return .on
        case .auto: return .auto
        }
    }

    func next() -> CameraFlashSetting {
        switch self {
        case .off: return .on
        case .on: return .auto
        case .auto: return .off
        }
    }

    var symbolName: String {
        switch self {
        case .off: return "bolt.slash.fill"
        case .on: return "bolt.fill"
        case .auto: return "bolt.badge.automatic.fill"
        }
    }

    /// The three choices the tools popover offers, in the order the artboard reads them.
    static let toolsChoices: [CameraFlashSetting] = [.off, .auto, .on]

    /// The handle suffix for a choice's chip (`camera.tools.flash.<slug>`).
    var toolsSlug: String {
        switch self {
        case .off: return "off"
        case .auto: return "auto"
        case .on: return "on"
        }
    }
}

enum CameraFacing: Equatable, Sendable {
    case back, front
}

enum CameraCaptureResult: Equatable, Sendable {
    case success(Data)
    case failure
}

enum CaptureFailure: Equatable, Sendable {
    case emptyBytes, timeout, writeFailed, metadataInsertFailed

    var userMessage: String {
        switch self {
        case .emptyBytes, .timeout: return "Capture unavailable"
        case .writeFailed, .metadataInsertFailed: return "Failed to save photo"
        }
    }
}

enum CameraPhase: Equatable, Sendable {
    case permissionRequired
    case previewReady
    case capturing(captureId: String)
    case persisting(captureId: String)
    case captureSucceeded(captureId: String, photo: CapturedPhotoRecord)
    case captureError(captureId: String, failure: CaptureFailure)
}

enum CameraLifecycle: Equatable, Sendable {
    case active, inactive
}

struct CapturedPhotoRecord: Equatable, Sendable {
    let id: Int64
    let imagePath: String
}

struct CameraCoordinatorState: Equatable, Sendable {
    var phase: CameraPhase = .permissionRequired
    var permission: CameraPermissionState = .notDetermined
    var lifecycle: CameraLifecycle = .active
    var thumbnailPath: String?
    var lastFailure: CaptureFailure?

    var isCaptureInFlight: Bool {
        switch phase {
        case .capturing, .persisting: return true
        default: return false
        }
    }

    var captureEnabled: Bool {
        phase == .previewReady && lifecycle == .active
    }

    func statusText() -> String? {
        switch phase {
        case .captureSucceeded: return "Saved"
        case .captureError(_, let failure): return failure.userMessage
        default: return lastFailure?.userMessage
        }
    }

    func thumbnailPathValue() -> String? {
        if case .captureSucceeded(_, let photo) = phase { return photo.imagePath }
        return thumbnailPath
    }
}
