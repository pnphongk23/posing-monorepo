import XCTest
import ImageIO
import Kingfisher
import UIKit
@testable import iosApp

/// Baseline costs behind the reported performance complaints. These are measurements, not
/// assertions about thresholds: the point is to attribute the app's latency to concrete
/// operations, so a fix can be justified by a before/after number.
///
/// Run: xcodebuild test -scheme Dev -configuration Debug-Dev \
///        -only-testing:iosAppTests/PerformanceBaselineTests
final class PerformanceBaselineTests: XCTestCase {

    private func ms(_ block: () -> Void) -> Double {
        let start = CFAbsoluteTimeGetCurrent()
        block()
        return (CFAbsoluteTimeGetCurrent() - start) * 1000
    }

    /// Opening the database runs the migrator. This happens on the main thread at app launch
    /// (`AppDelegate.didFinishLaunching` -> `GalleryStoreBootstrap.make`) and again on the first
    /// camera tap (`CameraViewModel.init` -> `try? AppDatabase()`).
    func testAppDatabaseOpenAndMigrateCost() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("perf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var cold: [Double] = []
        for index in 0..<3 {
            let url = root.appendingPathComponent("aipose\(index).db")
            let location = AppDatabaseLocation(url: url, kind: .freshInstall)
            var database: AppDatabase?
            cold.append(ms { database = try? AppDatabase(location: location) })
            XCTAssertNotNil(database)
        }
        print("PERF appDatabase.open+migrate(ms, fresh container each) = \(cold.map { String(format: "%.1f", $0) })")

        // Re-opening an existing database (what a second `AppDatabase()` call costs).
        let url = root.appendingPathComponent("aipose0.db")
        let location = AppDatabaseLocation(url: url, kind: .existingLegacy)
        var warm: [Double] = []
        for _ in 0..<3 {
            var database: AppDatabase?
            warm.append(ms { database = try? AppDatabase(location: location) })
            XCTAssertNotNil(database)
        }
        print("PERF appDatabase.reopen(ms) = \(warm.map { String(format: "%.1f", $0) })")
    }

    /// `GalleryLocalImage` decodes with `UIImage(contentsOfFile:)` inside a SwiftUI `body`, i.e.
    /// synchronously on the main thread, with no cache. `UIImage(contentsOfFile:)` is lazy: it
    /// returns in microseconds and defers the decode to first DRAW, which is why the cost shows up
    /// as a stall while the grid renders. So measure the forced draw, not just the load.
    func testFullResolutionDecodeCostVersusDownsample() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("perf-capture-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        try Self.writeJPEG(width: 4032, height: 3024, to: url)
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)??.intValue ?? 0

        // Same call the gallery grid and the gallery viewer make today: a lazy load ...
        var lazyLoads: [Double] = []
        for _ in 0..<3 {
            var image: UIImage?
            lazyLoads.append(ms { image = UIImage(contentsOfFile: url.path) })
            XCTAssertNotNil(image)
        }

        // ... followed by the real decode during draw, at the size a 130pt grid cell needs @3x.
        let cellSide = 390.0
        var fullDraws: [Double] = []
        for _ in 0..<3 {
            var image: UIImage?
            fullDraws.append(ms {
                image = UIImage(contentsOfFile: url.path)
                Self.forceDraw(image, side: cellSide)
            })
            XCTAssertNotNil(image)
        }

        // What an image pipeline should do instead: decode a thumbnail of the display size, once.
        var thumbDraws: [Double] = []
        for _ in 0..<3 {
            thumbDraws.append(ms {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return XCTFail("no source") }
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: Int(cellSide),
                ]
                guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return }
                Self.forceDraw(UIImage(cgImage: cg), side: cellSide)
            })
        }

        // A 3-column grid renders a screenful at once: 12 cells is a conservative screenful.
        let cells = 12
        print("PERF capturedJpeg(bytes) = \(bytes), size = 4032x3024")
        print("PERF uiImage(contentsOfFile) lazy load(ms) = \(lazyLoads.map { String(format: "%.2f", $0) })")
        print("PERF full-res load+draw one cell(ms) = \(fullDraws.map { String(format: "%.1f", $0) })  -> x\(cells) cells = \(String(format: "%.0f", (fullDraws.max() ?? 0) * Double(cells)))ms")
        print("PERF thumb(390px) decode+draw one cell(ms) = \(thumbDraws.map { String(format: "%.1f", $0) })  -> x\(cells) cells = \(String(format: "%.0f", (thumbDraws.max() ?? 0) * Double(cells)))ms")
        if let worst = fullDraws.max(), let best = thumbDraws.min(), best > 0 {
            print("PERF ratio full/thumb per cell = \(String(format: "%.1f", worst / best))x")
        }
    }

    /// Answers "why isn't the image cached by its URL alone?" with the library's real behaviour.
    ///
    /// Kingfisher keys the cache on the **image URL** and appends the decode size:
    /// `Resource.cacheKey` = `isFileURL ? localFileCacheKey : absoluteString` (`Resource.swift:98`),
    /// and `ImageCache.computedKey(with:)` returns `key` when there is no processor, or
    /// `key + "@" + processor.identifier` when there is one (`ImageCache.swift:1466`).
    ///
    /// The suffix is not redundancy: a 130pt thumbnail and a full-screen bitmap are different
    /// bitmaps. Serving one in place of the other is either blurry (thumbnail on a full screen) or
    /// the exact pathology this work removed (a 9.6MP decode per 130pt cell).
    @MainActor
    func testImageCacheIsKeyedByURLAndDecodeSize() async throws {
        AppImage.configure()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cachekey-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        try Self.writeJPEG(width: 1200, height: 1600, to: url)

        // The cache key *is* the image URL (its path for a local file).
        XCTAssertTrue(
            url.cacheKey.contains(url.lastPathComponent),
            "Kingfisher's base cache key must be the image URL/path, got: \(url.cacheKey)"
        )

        let thumb = AppImage.downsample(squarePoints: 130)
        let full = AppImage.downsample(points: CGSize(width: 390, height: 700), contentMode: .fit)
        print("PERF cacheKey(url) = \(url.cacheKey)")
        print("PERF cacheKey(url+thumb) = \(url.cacheKey)@\(thumb.identifier)")

        XCTAssertFalse(AppImage.isCached(url, processor: thumb), "nothing cached before the first load")

        _ = try await KingfisherManager.shared.retrieveImage(with: url, options: [.processor(thumb)])
        XCTAssertTrue(AppImage.isCached(url, processor: thumb), "URL + decode size is the stored entry")

        // A different draw size is a different entry, and the bare URL is not an entry at all.
        XCTAssertFalse(AppImage.isCached(url, processor: full), "another decode size must not reuse this bitmap")
        XCTAssertFalse(AppImage.isCached(url), "the URL alone is not the storage key when a processor was used")

        // Same URL + same size again: served from the cache, never re-decoded from the file.
        let again = try await KingfisherManager.shared.retrieveImage(with: url, options: [.processor(thumb)])
        XCTAssertNotEqual(again.cacheType, .none, "the second load of the same size must come from cache")
        print("PERF second load cacheType = \(again.cacheType)")
    }

    private static func forceDraw(_ image: UIImage?, side: Double) {
        guard let image else { return }
        let size = CGSize(width: side, height: side)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 3
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        _ = renderer.image { _ in
            // `aspectRatio(.fill)` equivalent: cover the cell, which is what the grid asks for.
            let scale = max(size.width / image.size.width, size.height / image.size.height)
            let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(
                x: (size.width - drawn.width) / 2,
                y: (size.height - drawn.height) / 2,
                width: drawn.width,
                height: drawn.height
            ))
        }
    }

    /// `CaptureImageStorage.init` touches the filesystem (`createDirectory`) — it runs on the main
    /// thread whenever a `CameraViewModel` is built.
    func testCaptureImageStorageInitCost() {
        var durations: [Double] = []
        for _ in 0..<5 {
            var storage: CaptureImageStorage?
            durations.append(ms { storage = CaptureImageStorage() })
            XCTAssertNotNil(storage)
        }
        print("PERF captureImageStorage.init(ms) = \(durations.map { String(format: "%.2f", $0) })")
    }

    private static func writeJPEG(width: Int, height: Int, to url: URL) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw XCTSkip("could not create bitmap context") }
        context.setFillColor(UIColor.systemPink.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(UIColor.systemBlue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 3))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)
        else { throw XCTSkip("could not encode jpeg") }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
