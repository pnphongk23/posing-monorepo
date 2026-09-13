import ImageIO
import UIKit
import XCTest
@testable import iosApp

final class FeatureStateTests: XCTestCase {
    @MainActor func testEmptyPoseResultMapsToEmptyState() async {
        let model = PosesViewModel(service: StubPoseService(result: []))
        await model.load()
        guard case .empty = model.state else { return XCTFail("Expected empty") }
    }

    @MainActor func testFailedPoseLoadMapsToFailedState() async {
        let model = PosesViewModel(service: FailingPoseService())
        await model.load()
        guard case .failed = model.state else { return XCTFail("Expected failed") }
    }

    @MainActor func testSearchDebounceSchedulesLoad() async {
        let model = PosesViewModel(service: StubPoseService(result: [samplePose]), debounceNanoseconds: 50_000_000)
        model.query = "soft"
        model.scheduleSearch()
        try? await Task.sleep(nanoseconds: 80_000_000)
        guard case .loaded = model.state else { return XCTFail("Expected loaded after debounce") }
    }

    func testSearchScreenUsesPrototypeDiscoveryContract() {
        XCTAssertEqual(SearchScreenContract.recentSearches, ["Dancing", "Stretching", "Warrior"])
        XCTAssertEqual(SearchScreenContract.sourceFilters, [.all, .saved, .community])
        XCTAssertEqual(SearchScreenContract.sourceFilters.map(\.rawValue), ["All poses", "My poses", "Community"])
    }

    /// A recent-search chip must fill the field *and* search without waiting out the typing debounce.
    @MainActor func testRecentSearchChipFillsQueryAndSearchesImmediately() async {
        let model = PosesViewModel(
            service: StubPoseService(result: [
                samplePose,
                NativePose(id: "warrior-1", name: "Warrior", category: "Standing", imageURL: nil, instructions: [], isSaved: false),
            ]),
            debounceNanoseconds: 10_000_000_000
        )
        await model.startSearch(for: "Warrior")
        XCTAssertEqual(model.query, "Warrior")
        XCTAssertEqual(model.filter, .all)
        guard case .loaded(let poses) = model.state else { return XCTFail("Expected loaded without debounce") }
        XCTAssertEqual(poses.map(\.name), ["Warrior"])
    }

    /// Typing still debounces: the field binding drives `updateQuery`, nothing loads until it fires.
    @MainActor func testTypingThroughUpdateQueryDebounces() async {
        let model = PosesViewModel(service: StubPoseService(result: [samplePose]), debounceNanoseconds: 50_000_000)
        model.updateQuery("soft")
        XCTAssertEqual(model.query, "soft")
        guard case .idle = model.state else { return XCTFail("Expected idle immediately after typing") }
        try? await Task.sleep(nanoseconds: 120_000_000)
        guard case .loaded = model.state else { return XCTFail("Expected loaded after debounce") }
    }

    /// Prototype `.nb-search-kicker` / `.nb-search-results-count` copy: no "Source" heading, and the
    /// heading only carries the query once it is confirmed.
    func testSearchResultsCopyMatchesPrototype() {
        XCTAssertEqual(SearchResultsCopy.screenTitle, "Search")
        XCTAssertEqual(SearchResultsCopy.kicker, "YOUR MATCHES")
        XCTAssertEqual(SearchResultsCopy.heading(query: "   "), "Results")
        XCTAssertEqual(SearchResultsCopy.heading(query: "Warrior"), "Results for “Warrior”")
        XCTAssertEqual(SearchResultsCopy.countLabel(for: .loaded([samplePose])), "1 pose")
        XCTAssertEqual(SearchResultsCopy.countLabel(for: .loaded([samplePose, samplePose])), "2 poses")
        XCTAssertEqual(SearchResultsCopy.countLabel(for: .empty), "0 poses")
    }

    /// `app.js createPoseCard` cycles `.nb-card--aspect-{tall,square,short}`; the two-column grid
    /// lands one aspect per visual row, which is what the reference shots show.
    func testPoseGridAspectRatiosCyclePerRow() {
        XCTAssertEqual(PoseGridMetrics.aspectRatio(forRow: 0), 1 / 1.25, accuracy: 0.0001)
        XCTAssertEqual(PoseGridMetrics.aspectRatio(forRow: 1), 1, accuracy: 0.0001)
        XCTAssertEqual(PoseGridMetrics.aspectRatio(forRow: 2), 1.25, accuracy: 0.0001)
        XCTAssertEqual(PoseGridMetrics.aspectRatio(forRow: 3), 1 / 1.25, accuracy: 0.0001)
    }

    func testTryPoseRoutesToPaywallWithoutPremium() {
        XCTAssertEqual(poseTryPoseDestination(hasPremiumAccess: false), .paywall)
    }

    func testTryPosePreservesCameraRouteWithPremium() {
        XCTAssertEqual(poseTryPoseDestination(hasPremiumAccess: true), .camera)
    }

    @MainActor func testGalleryDeleteReloadsItems() async {
        let store = StubGalleryStore()
        let model = GalleryViewModel(store: store)
        await model.load()
        guard case .loaded(let items) = model.state, let item = items.first else { return XCTFail("Expected item") }
        await model.delete(item)
        guard case .empty = model.state else { return XCTFail("Expected empty after delete") }
    }

    @MainActor func testGalleryNavigationSelectionIndex() async {
        let store = StubGalleryStore(items: [
            GalleryItem(id: 1, fileURL: URL(fileURLWithPath: "/tmp/a.jpg"), createdAt: .now),
            GalleryItem(id: 2, fileURL: URL(fileURLWithPath: "/tmp/b.jpg"), createdAt: .now.addingTimeInterval(-60)),
        ])
        let model = GalleryViewModel(store: store)
        await model.load()
        guard case .loaded(let items) = model.state else { return XCTFail("Expected loaded") }
        model.select(items[1])
        XCTAssertEqual(model.selectedIndex, 1)
    }

    @MainActor func testAppTabSelection() {
        var tab = AppTab.poses
        tab = .gallery
        XCTAssertEqual(tab, .gallery)
        tab = .camera
        XCTAssertEqual(tab, .camera)
    }

    @MainActor func testGalleryTimeFilterToday() async {
        let store = StubGalleryStore(items: [
            GalleryItem(id: 1, fileURL: URL(fileURLWithPath: "/tmp/a.jpg"), createdAt: .now),
            GalleryItem(id: 2, fileURL: URL(fileURLWithPath: "/tmp/b.jpg"), createdAt: Date(timeIntervalSince1970: 0)),
        ])
        let model = GalleryViewModel(store: store)
        await model.load()
        model.timeFilter = .today
        model.applyFilter()
        guard case .loaded(let items) = model.state else { return XCTFail("Expected loaded") }
        XCTAssertEqual(items.count, 1)
    }

    // MARK: - Pose artwork cache (Feature 012)

    /// The pose grid used to draw `AsyncImage`, i.e. decode at file resolution inside the view body —
    /// on the main thread, on every re-render, with nothing cached (measured ~19-37ms per 12MP cell =
    /// ~440ms for one 12-cell screenful; see `PerformanceBaselineTests`).
    ///
    /// This is the fix end to end, through the same pipeline the grid installs (`AppImage` →
    /// Kingfisher: shared cache, `.backgroundDecode`, drawn-size processor): one load puts the
    /// *downsampled* bitmap in the memory+disk cache, the bitmap that comes back is the size the cell
    /// draws rather than the 12MP file, and the next load is served from cache without touching disk.
    @MainActor func testPoseArtworkIsCachedAtDrawnSizeNotFileSize() async throws {
        AppImage.configure()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pose-artwork-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        try Self.writeJPEG(width: 4032, height: 3024, to: url)

        // Exactly what `PoseCard.artwork` installs, for the box a card's artwork is drawn in.
        let drawn = PoseGridMetrics.cardArtworkPoints
        let processor = AppImage.downsample(points: drawn, contentMode: .fit)
        // `DownsamplingImageProcessor.size` is a point size (Kingfisher applies the pipeline's
        // `.scaleFactor` on top of it), so the processor must be asked for the drawn box — passing
        // pre-multiplied pixels would decode a 3x-larger bitmap for the same cell.
        XCTAssertEqual(processor.size.width, drawn.width, accuracy: 0.5)
        XCTAssertEqual(processor.size.height, drawn.height, accuracy: 0.5)
        XCTAssertLessThan(drawn.width, 200, "a grid cell is small; the assertion below depends on it")

        XCTAssertFalse(AppImage.isCached(url, points: drawn, contentMode: .fit), "expected a cold cache")

        let coldStart = CFAbsoluteTimeGetCurrent()
        let cold = try await AppImage.load(from: url, points: drawn, contentMode: .fit)
        let coldMS = (CFAbsoluteTimeGetCurrent() - coldStart) * 1000
        XCTAssertFalse(cold.servedFromCache, "the first load has to read the file")

        // Downsampled, not the file's resolution: ImageIO was asked for the drawn pixel box, so the
        // decoded bitmap's long edge is that box (points x scale), nowhere near the 4032px original.
        let longEdge = max(cold.image.size.width, cold.image.size.height)
        let requested = max(processor.size.width, processor.size.height)
        XCTAssertEqual(longEdge, requested, accuracy: 1, "decoded at the drawn size, not the file's")
        let decodedPixels = max(cold.image.cgImage?.width ?? 0, cold.image.cgImage?.height ?? 0)
        XCTAssertLessThan(decodedPixels, 4032 / 5, "a 12MP file must not be decoded for one cell")

        XCTAssertTrue(AppImage.isCached(url, points: drawn, contentMode: .fit), "one load must fill the cache")

        let warmStart = CFAbsoluteTimeGetCurrent()
        let warm = try await AppImage.load(from: url, points: drawn, contentMode: .fit)
        let warmMS = (CFAbsoluteTimeGetCurrent() - warmStart) * 1000
        XCTAssertTrue(warm.servedFromCache, "the second load must be served from the cache")

        // Same measurement shape as the baseline, so the two numbers are comparable: the old path was
        // `UIImage(contentsOfFile:)` in the view body plus the draw that forces the full-res decode.
        // The very first pipeline run of the process also pays one-off setup, so a second cold file
        // reports the steady-state cold cost.
        let secondURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pose-artwork-\(UUID().uuidString).jpg")
        try Self.writeJPEG(width: 4032, height: 3024, to: secondURL)
        defer { try? FileManager.default.removeItem(at: secondURL) }
        let secondStart = CFAbsoluteTimeGetCurrent()
        _ = try await AppImage.load(from: secondURL, points: drawn, contentMode: .fit)
        let secondColdMS = (CFAbsoluteTimeGetCurrent() - secondStart) * 1000

        let oldPathMS = Self.measureLegacyFullResolutionDraw(of: url, cell: drawn)
        print("PERF pose cell drawn at \(Int(drawn.width))x\(Int(drawn.height))pt (source image 4032x3024)")
        print("PERF   before: UIImage(contentsOfFile:) + full-res decode+draw on the main thread, one cell(ms) = \(String(format: "%.1f", oldPathMS))")
        print("PERF   after:  kingfisher downsample, cached load on the main thread, one cell(ms) = \(String(format: "%.2f", warmMS))")
        print("PERF   after:  kingfisher downsample, cold load (off the main thread)(ms) = \(String(format: "%.1f", coldMS)) first run, \(String(format: "%.1f", secondColdMS)) steady state")
        print("PERF   decoded bitmap px = \(decodedPixels) (requested box \(Int(requested))pt at scale \(cold.image.scale) = \(Int(requested) * Int(cold.image.scale))px), isCached = \(AppImage.isCached(url, points: drawn, contentMode: .fit))")
    }

    /// The pre-fix path verbatim: `UIImage(contentsOfFile:)` returns lazily and the draw forces the
    /// whole 12MP decode on the calling (main) thread.
    @MainActor
    private static func measureLegacyFullResolutionDraw(of url: URL, cell: CGSize) -> Double {
        let start = CFAbsoluteTimeGetCurrent()
        if let image = UIImage(contentsOfFile: url.path) {
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = UIScreen.main.scale
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(size: cell, format: format)
            _ = renderer.image { _ in
                let scale = max(cell.width / image.size.width, cell.height / image.size.height)
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                image.draw(in: CGRect(
                    x: (cell.width - size.width) / 2,
                    y: (cell.height - size.height) / 2,
                    width: size.width,
                    height: size.height
                ))
            }
        }
        return (CFAbsoluteTimeGetCurrent() - start) * 1000
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

private let samplePose = NativePose(
    id: "standing-1",
    name: "Soft Standing",
    category: "Standing",
    imageURL: nil,
    instructions: ["Relax"],
    isSaved: true
)

private struct StubPoseService: PoseServing {
    let result: [NativePose]
    func poses(query: String?) async throws -> [NativePose] {
        guard let query, !query.isEmpty else { return result }
        return result.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
    func pose(id: String) async throws -> NativePose { result[0] }
}

private struct FailingPoseService: PoseServing {
    func poses(query: String?) async throws -> [NativePose] { throw NSError(domain: "test", code: 1) }
    func pose(id: String) async throws -> NativePose { throw NSError(domain: "test", code: 1) }
}

private final class StubGalleryStore: GalleryStoring, @unchecked Sendable {
    var items: [GalleryItem]
    init(items: [GalleryItem] = [GalleryItem(id: 1, fileURL: URL(fileURLWithPath: "/tmp/a.jpg"), createdAt: .now)]) {
        self.items = items
    }
    func photos() async throws -> [GalleryItem] { items }
    func delete(id: Int64) async throws { items.removeAll { $0.id == id } }
}
