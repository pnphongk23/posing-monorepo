import Foundation
import Kingfisher
import SwiftUI

/// The app's single image-loading entry point, backed by **Kingfisher** (off-the-shelf, two-tier
/// memory + disk cache, downsampling, request coalescing, background decode).
///
/// Why a library instead of a hand-rolled cache: this repository shipped no image cache at all.
/// Every grid cell called `UIImage(contentsOfFile:)` or `AsyncImage` inside a view body, so the
/// decode happened at draw time on the main thread — measured at ~19-37ms per 12MP cell
/// (~440ms of main-thread work for one 12-cell screenful), repeated on every re-render.
/// See `iosAppTests/Performance/PerformanceBaselineTests.swift` for the numbers.
///
/// Rules for call sites (keep them boring):
/// - SwiftUI: `KFImage(url).setProcessor(AppImage.downsample(points:).processor)...`
/// - UIKit/manual: `KingfisherManager.shared.retrieveImage(with:options:)`
/// - never call `UIImage(contentsOfFile:)` or `AsyncImage` from a view body again
enum AppImage {

    // MARK: - Budgets

    /// Decoded-bitmap budget. The library evicts on memory pressure by itself.
    static let memoryBudgetBytes = 64 * 1024 * 1024
    static let memoryCountLimit = 400

    /// On-disk budget in the system Caches directory (Kingfisher's default location, which iOS is
    /// free to purge — never point this at Application Support).
    static let diskBudgetBytes = 200 * 1024 * 1024
    static let diskExpiration: StorageExpiration = .days(30)

    // MARK: - Setup

    @MainActor private static var isConfigured = false

    /// Call once, as early as possible in the launch path.
    @MainActor
    static func configure() {
        guard !isConfigured else { return }
        isConfigured = true

        ImageCache.default.memoryStorage.config.totalCostLimit = memoryBudgetBytes
        ImageCache.default.memoryStorage.config.countLimit = memoryCountLimit
        ImageCache.default.diskStorage.config.sizeLimit = UInt(diskBudgetBytes)
        ImageCache.default.diskStorage.config.expiration = diskExpiration

        // `.backgroundDecode` does the bitmap decode off the main thread — the exact cost that made
        // the gallery stall. `.scaleFactor` keeps images crisp on 3x screens.
        KingfisherManager.shared.defaultOptions = [
            .backgroundDecode,
            .scaleFactor(UIScreen.main.scale),
        ]

        // Reclaim anything past its expiration from a previous launch, off the launch path.
        DispatchQueue.global(qos: .utility).async {
            ImageCache.default.cleanExpiredDiskCache()
        }
    }

    // MARK: - Downsampling

    /// Downsample to the size the caller will actually draw, so a 12MP capture never becomes a
    /// 130pt thumbnail's worth of decoded bitmap.
    ///
    /// `DownsamplingImageProcessor.size` is a **point** size — Kingfisher multiplies it by the
    /// pipeline's `.scaleFactor` itself (`KingfisherWrapper.downsampledImage(data:to:scale:)`). The box
    /// this computes is in pixels, so it is converted back to points before it reaches the processor;
    /// handing the processor pre-multiplied pixels decodes a bitmap whose long edge is `scale`× longer
    /// than the cell draws (9× the pixels at 3x), which defeats most of the savings.
    @MainActor
    static func downsample(
        points: CGSize,
        scale: CGFloat? = nil,
        contentMode: SwiftUI.ContentMode = .fill
    ) -> DownsamplingImageProcessor {
        let scale = scale ?? UIScreen.main.scale
        let box = pixelSize(for: points, scale: scale, contentMode: contentMode)
        return DownsamplingImageProcessor(size: CGSize(
            width: (box.width / scale).rounded(),
            height: (box.height / scale).rounded()
        ))
    }

    /// Square shortcut for the many grid cells that draw into a square (`.scaledToFill()`): the box
    /// grows to the square's long edge so a non-square photo still covers the cell.
    @MainActor
    static func downsample(squarePoints: CGFloat, scale: CGFloat? = nil) -> DownsamplingImageProcessor {
        downsample(
            points: CGSize(width: squarePoints, height: squarePoints),
            scale: scale,
            contentMode: .fill
        )
    }

    /// `.fill` must cover the target, so the shorter edge has to be grown to cover it; `.fit`
    /// only ever needs the target box. Pixel math only — `downsample(points:)` converts the result
    /// back to the point size the processor wants.
    static func pixelSize(for points: CGSize, scale: CGFloat, contentMode: SwiftUI.ContentMode) -> CGSize {
        let box = CGSize(width: points.width * scale, height: points.height * scale)
        guard contentMode == .fill, points.width > 0, points.height > 0 else {
            return CGSize(width: max(1, box.width.rounded()), height: max(1, box.height.rounded()))
        }
        // Cover a square-ish cell from an arbitrary aspect ratio: keep the long edge.
        let longEdge = max(box.width, box.height)
        return CGSize(width: max(1, longEdge.rounded()), height: max(1, longEdge.rounded()))
    }

    // MARK: - Diagnostics (used by tests and the debug screen)

    /// Total bytes currently held in the disk tier. Synchronous and blocking: call it from a test
    /// or a debug screen, not from a view body.
    @MainActor
    static func diskCacheSizeBytes() -> Int {
        (try? ImageCache.default.diskStorage.totalSize()).map { Int($0) } ?? 0
    }

    @MainActor
    static func clearCaches() {
        ImageCache.default.clearMemoryCache()
        ImageCache.default.clearDiskCache()
    }

    static func isCached(_ url: URL, processor: ImageProcessor? = nil) -> Bool {
        ImageCache.default.isCached(
            forKey: url.cacheKey,
            processorIdentifier: processor?.identifier ?? ""
        )
    }

    // MARK: - Manual (non-SwiftUI) loads

    /// A finished pipeline load.
    struct Loaded {
        let image: UIImage
        /// `true` when the bitmap was served by the memory or disk tier instead of the network — i.e.
        /// the app has already decoded this pose at this size and payed for it once.
        let servedFromCache: Bool
    }

    /// The `UIKit`/manual entry point this type's doc comment mentions: loads `url` through the exact
    /// pipeline the views use (same cache, same options, same drawn-size downsample). `KFImage` is
    /// sugar over this; tests use it so they never have to reach into the library.
    @MainActor
    static func load(
        from url: URL,
        points: CGSize,
        contentMode: SwiftUI.ContentMode = .fill
    ) async throws -> Loaded {
        let result = try await KingfisherManager.shared.retrieveImage(
            with: url,
            options: [.processor(downsample(points: points, contentMode: contentMode))]
        )
        return Loaded(image: result.image, servedFromCache: result.cacheType != .none)
    }

    /// Cache probe for a draw size: `true` means the exact bitmap a cell of that drawn size needs is
    /// already resident in memory or on disk, so drawing it costs no download and no decode.
    @MainActor
    static func isCached(
        _ url: URL,
        points: CGSize,
        contentMode: SwiftUI.ContentMode = .fill
    ) -> Bool {
        isCached(url, processor: downsample(points: points, contentMode: contentMode))
    }
}
