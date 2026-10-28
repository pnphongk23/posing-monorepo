import Foundation

final class CaptureImageStorage: CaptureImageWriter, @unchecked Sendable {
    private let fileManager: FileManager
    private let directoryURL: URL?
    private let imageStore: PhotoImageStore

    init(fileManager: FileManager = .default, directoryURL: URL? = nil) {
        self.fileManager = fileManager
        let resolvedDirectory: URL?
        if let directoryURL {
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            resolvedDirectory = directoryURL
        } else {
            let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            let folder = support?.appendingPathComponent("aipose", isDirectory: true)
            if let folder {
                try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            }
            resolvedDirectory = folder
        }
        self.directoryURL = resolvedDirectory
        imageStore = PhotoImageStore(directoryURL: resolvedDirectory, fileManager: fileManager)
    }

    func writeJpeg(_ bytes: Data, captureId: String) -> String? {
        guard !bytes.isEmpty, let directoryURL else { return nil }
        let filename = "capture_\(captureId).jpg"
        let url = directoryURL.appendingPathComponent(filename)
        // Claim the file before it exists. The gallery's orphan sweep refuses to touch a claimed
        // file, so a capture in flight cannot be mistaken for an orphan no matter how long the
        // metadata insert takes. The claim is released on commit (the row lands) or rollback.
        imageStore.beginCapture(imagePath: filename)
        do {
            try bytes.write(to: url, options: .atomic)
            return filename
        } catch {
            imageStore.endCapture(imagePath: filename)
            return nil
        }
    }

    func verify(filename: String) -> Bool {
        guard let directoryURL else { return false }
        let url = directoryURL.appendingPathComponent(filename)
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else { return false }
        return size.int64Value > 0
    }

    /// Rollback: the failed capture leaves nothing behind, claim included.
    func delete(filename: String) {
        imageStore.endCapture(imagePath: filename)
        guard let directoryURL else { return }
        let url = directoryURL.appendingPathComponent(filename)
        try? fileManager.removeItem(at: url)
    }

    func fullPath(for filename: String) -> String? {
        directoryURL?.appendingPathComponent(filename).path
    }
}
