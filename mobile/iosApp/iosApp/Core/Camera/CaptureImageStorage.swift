import Foundation

final class CaptureImageStorage: CaptureImageWriter, @unchecked Sendable {
    private let fileManager: FileManager
    private let directoryURL: URL?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let folder = support?.appendingPathComponent("aipose", isDirectory: true)
        if let folder {
            try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        directoryURL = folder
    }

    func writeJpeg(_ bytes: Data, captureId: String) -> String? {
        guard !bytes.isEmpty, let directoryURL else { return nil }
        let filename = "capture_\(captureId).jpg"
        let url = directoryURL.appendingPathComponent(filename)
        do {
            try bytes.write(to: url, options: .atomic)
            return filename
        } catch {
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

    func delete(filename: String) {
        guard let directoryURL else { return }
        let url = directoryURL.appendingPathComponent(filename)
        try? fileManager.removeItem(at: url)
    }

    func fullPath(for filename: String) -> String? {
        directoryURL?.appendingPathComponent(filename).path
    }
}
