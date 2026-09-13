import Photos
import UIKit

enum PhotosExportAuthorization: Equatable {
    case authorized, denied, restricted, notDetermined
}

enum PhotosExporter {
    static func authorizationStatus() -> PhotosExportAuthorization {
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .authorized, .limited: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    static func requestAuthorization() async -> PhotosExportAuthorization {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        switch status {
        case .authorized, .limited: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    static func saveImage(at fileURL: URL) async -> Bool {
        let auth = authorizationStatus() == .notDetermined
            ? await requestAuthorization()
            : authorizationStatus()
        guard auth == .authorized else { return false }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
            }, completionHandler: { success, _ in
                continuation.resume(returning: success)
            })
        }
    }

    static func confirmation(saved: Bool) -> String {
        saved ? "Saved to Photos." : "Save failed"
    }
}
