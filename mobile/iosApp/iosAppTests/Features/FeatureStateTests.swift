import ImageIO
import SwiftUI
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

    // MARK: - Shared state adoption (UI-CHANGE-260913, report §3.4–§3.8)

    /// §3.4: the Poses library loads/empties/fails through the shared component with the
    /// prototype's exact copy; the empty state has no personal Create CTA.
    func testPosesListStateCopyMatchesPrototype() {
        XCTAssertEqual(PosesListStateCopy.loadingTitle, "Loading poses")
        XCTAssertEqual(PosesListStateCopy.loadingMessage, "Getting the pose library ready.")
        XCTAssertEqual(PosesListStateCopy.emptyTitle, "No poses yet")
        XCTAssertEqual(PosesListStateCopy.emptyMessage, "New poses will appear here when they're available.")
        XCTAssertEqual(PosesListStateCopy.errorTitle, "Couldn't load poses")
        XCTAssertEqual(PosesListStateCopy.errorMessage, "Check your connection and try again.")
        XCTAssertEqual(PosesListStateCopy.retryActionTitle, "Try again")
    }

    /// §3.5 vs §3.8: Search and Saved render the same component with per-surface copy.
    func testPoseResultsStateCopyMatchesSearchAndSavedPrototypes() {
        XCTAssertEqual(PoseResultsStateCopy.retryActionTitle, "Try again")

        XCTAssertEqual(PoseResultsStateCopy.searchLoadingTitle, "Searching")
        XCTAssertEqual(PoseResultsStateCopy.searchLoadingMessage, "Looking through your library and the community.")
        XCTAssertEqual(PoseResultsStateCopy.searchErrorTitle, "Search is paused")
        XCTAssertEqual(PoseResultsStateCopy.searchErrorMessage, "We could not load results right now. Your query is still here.")

        XCTAssertEqual(PoseResultsStateCopy.savedLoadingTitle, "Loading saved poses")
        XCTAssertEqual(PoseResultsStateCopy.savedLoadingMessage, "Getting your saved collection ready.")
        XCTAssertEqual(PoseResultsStateCopy.savedErrorTitle, "Couldn't load saved poses")
        XCTAssertEqual(PoseResultsStateCopy.savedErrorMessage, "Check your connection and try again.")
        XCTAssertEqual(PoseResultsStateCopy.savedEmptyTitle, "No saved poses yet")
        XCTAssertEqual(PoseResultsStateCopy.savedEmptyMessage, "Save poses from Community to find them here.")
        XCTAssertEqual(PoseResultsStateCopy.browseCommunityActionTitle, "Browse Community")
    }

    /// §3.7: gallery all-empty vs filter-empty are two different states with distinct copy, and
    /// only the all-empty branch carries the `Open Camera` action.
    func testGalleryStateCopyMatchesPrototype() {
        XCTAssertEqual(GalleryStateCopy.emptyAllTitle, "No photos yet")
        XCTAssertEqual(GalleryStateCopy.emptyAllMessage, "Capture a pose to start your gallery.")
        XCTAssertEqual(GalleryStateCopy.openCameraActionTitle, "Open Camera")
        XCTAssertEqual(GalleryStateCopy.emptyFilterTitle, "No photos in this filter")
        XCTAssertEqual(GalleryStateCopy.emptyFilterMessage, "Try another filter.")
        XCTAssertEqual(GalleryStateCopy.errorTitle, "Couldn't load gallery")
        XCTAssertEqual(GalleryStateCopy.retryActionTitle, "Try again")
    }

    /// §3.8: account signed-out success and sign-in-prompt failure share the component copy.
    func testAccountAndSignInStateCopyMatchPrototypes() {
        XCTAssertEqual(AccountStateCopy.signedOutTitle, "Signed out")
        XCTAssertEqual(AccountStateCopy.signedOutMessage, "Sign in again to access your Saved poses.")
        XCTAssertEqual(SignInPromptStateCopy.failureTitle, "Sign-in failed")
        XCTAssertEqual(SignInPromptStateCopy.failureMessage, "Try again to continue.")
        XCTAssertEqual(SignInPromptStateCopy.failureActionTitle, "Try again")
    }

    /// §3.6: a detail route is only invalid on the definitive `poseNotFound` signal; an
    /// inconclusive failure (offline) must never demote a working detail to "unavailable".
    @MainActor func testPoseDetailAvailabilityFollowsDefinitiveCatalogSignal() async {
        let gone = PosesViewModel(service: MissingPoseService())
        let offline = PosesViewModel(service: OfflinePoseService())
        let live = PosesViewModel(service: StubPoseService(result: [samplePose]))

        let confirmed = await live.confirmPublished(samplePose)
        XCTAssertTrue(confirmed, "a resolvable pose stays available")

        let missing = await gone.confirmPublished(samplePose)
        XCTAssertFalse(missing, "poseNotFound flips the detail to the unavailable state")

        let inconclusive = await offline.confirmPublished(samplePose)
        XCTAssertTrue(inconclusive, "an inconclusive failure must not render the unavailable state")
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

/// The definitive unavailable signal: the pose is not in the published catalogue.
private struct MissingPoseService: PoseServing {
    func poses(query: String?) async throws -> [NativePose] { [] }
    func pose(id: String) async throws -> NativePose { throw PoseAdapterError.poseNotFound(id) }
}

/// An inconclusive failure (offline): availability stays unconfirmed, not denied.
private struct OfflinePoseService: PoseServing {
    func poses(query: String?) async throws -> [NativePose] { throw URLError(.notConnectedToInternet) }
    func pose(id: String) async throws -> NativePose { throw URLError(.notConnectedToInternet) }
}

private final class StubGalleryStore: GalleryStoring, @unchecked Sendable {
    var items: [GalleryItem]
    init(items: [GalleryItem] = [GalleryItem(id: 1, fileURL: URL(fileURLWithPath: "/tmp/a.jpg"), createdAt: .now)]) {
        self.items = items
    }
    func photos() async throws -> [GalleryItem] { items }
    func delete(id: Int64) async throws { items.removeAll { $0.id == id } }
}

// MARK: - Shared state component: tone mapping (UI-CHANGE-260913)

/// Tone-mapping coverage for the shared `FeatureStateView` card.
///
/// The report lists states that the unauthenticated parity rig cannot drive — Saved signed-in
/// empty/error/loading (`GET /api/me/saved` → 401) and the camera pose picker's offline notice — so
/// these assertions are the substitute evidence for the missing screenshot verdicts. They read the
/// same pure mappers production reads (`Loadable.stateTone`, `SavedSurfaceStage`,
/// `PosePickerViewModel.stateTone`) and never assert on a rendered pixel.
final class FeatureStateToneMappingTests: XCTestCase {

    // MARK: Six-tone contract (styles/tokens.css + scripts/empty-state.js)

    /// `tokens.css`: error `#FFF4F5`; warning/offline `#FED766`; success `#B5E2B9`; empty/loading white.
    func testEveryToneMapsToItsPrototypeSurfaceToken() {
        let expected: [FeatureStateTone: UInt] = [
            .empty: 0xFFFFFF,
            .loading: 0xFFFFFF,
            .error: 0xFFF4F5,
            .offline: 0xFED766,
            .warning: 0xFED766,
            .success: 0xB5E2B9,
        ]
        XCTAssertEqual(Set(expected.keys), Set(FeatureStateTone.allCases), "every tone must be covered")
        for tone in FeatureStateTone.allCases {
            assertColor(tone.surface, expected[tone]!, "surface for .\(tone)")
        }
    }

    /// `empty-state.css`: base `color: var(--nb-color-dark)`; `.nb-empty-state--loading` tints it
    /// `--nb-color-gray` while the title is explicitly reset to dark.
    func testOnlyLoadingToneDimsTheCopy() {
        for tone in FeatureStateTone.allCases {
            assertColor(tone.copyColor, tone == .loading ? 0x6B7280 : 0x121212, "copy for .\(tone)")
        }
    }

    /// `empty-state.js` `ROLE_BY_STATE` / `LIVE_BY_STATE`: only `error` is an assertive alert.
    func testOnlyErrorToneIsAnAssertiveAlert() {
        for tone in FeatureStateTone.allCases {
            XCTAssertEqual(tone.isAssertive, tone == .error, "alert semantics for .\(tone)")
        }
    }

    // MARK: Pure mapper production reads

    func testLoadableStateToneMapping() {
        XCTAssertEqual(Loadable<[NativePose]>.idle.stateTone, .loading)
        XCTAssertEqual(Loadable<[NativePose]>.loading.stateTone, .loading)
        XCTAssertEqual(Loadable<[NativePose]>.empty.stateTone, .empty)
        XCTAssertEqual(Loadable<[NativePose]>.failed("boom").stateTone, .error)
        XCTAssertNil(Loadable<[NativePose]>.loaded([]).stateTone, "loaded draws content, not a card")
    }

    // MARK: Poses library

    @MainActor func testPosesLibraryTonePerCondition() async {
        let empty = PosesViewModel(service: StubPoseService(result: []))
        XCTAssertEqual(empty.state.stateTone, .loading, "idle renders the loading card")
        await empty.load()
        XCTAssertEqual(empty.state.stateTone, .empty)

        let failed = PosesViewModel(service: FailingPoseService())
        await failed.load()
        XCTAssertEqual(failed.state.stateTone, .error)

        let loaded = PosesViewModel(service: StubPoseService(result: [samplePose]))
        await loaded.load()
        XCTAssertNil(loaded.state.stateTone)
    }

    // MARK: Search + Saved list (Saved signed-in states are undrivable in the parity rig)

    @MainActor func testSearchAndSavedResultsListTonePerCondition() async {
        let loadingModel = PosesViewModel(service: StubPoseService(result: []))
        XCTAssertEqual(PoseResultsList(model: loadingModel, context: .saved).stateTone, .loading)

        let emptyModel = PosesViewModel(service: StubPoseService(result: []))
        await emptyModel.load()
        XCTAssertEqual(PoseResultsList(model: emptyModel, context: .saved).stateTone, .empty)
        XCTAssertEqual(PoseResultsList(model: emptyModel, context: .search).stateTone, .empty)
        // Search draws its own inline `#search-state-message` banner instead of the card.
        XCTAssertNil(PoseResultsList(model: emptyModel, context: .search, emptyPresentation: .hidden).stateTone)

        let failedModel = PosesViewModel(service: FailingPoseService())
        await failedModel.load()
        XCTAssertEqual(PoseResultsList(model: failedModel, context: .saved).stateTone, .error)
        XCTAssertEqual(PoseResultsList(model: failedModel, context: .search).stateTone, .error)

        let loadedModel = PosesViewModel(service: StubPoseService(result: [samplePose]))
        await loadedModel.load()
        XCTAssertNil(PoseResultsList(model: loadedModel, context: .saved).stateTone)
    }

    // MARK: Saved surface stage (session gate + signed-in list)

    func testSavedSurfaceStageAndTonePerCondition() {
        XCTAssertEqual(SavedSurfaceStage.resolve(isSessionResolved: false, isSignedIn: false), .resolvingSession)
        XCTAssertEqual(SavedSurfaceStage.resolve(isSessionResolved: true, isSignedIn: false), .signInRequired)
        XCTAssertEqual(SavedSurfaceStage.resolve(isSessionResolved: true, isSignedIn: true), .list)

        XCTAssertEqual(SavedSurfaceStage.resolvingSession.tone, .loading)
        XCTAssertEqual(SavedSurfaceStage.signInRequired.tone, .empty, "the FEAT-013 auth gate is the empty card")
        XCTAssertNil(SavedSurfaceStage.list.tone, "the list derives its own tone from Loadable.stateTone")
    }

    // MARK: Camera pose picker — the only `.offline` producer in the app

    @MainActor func testPosePickerTonePerCondition() async {
        let failing = PosePickerViewModel(service: FailingPoseService())
        XCTAssertEqual(failing.stateTone, .loading, "idle renders the loading card")
        await failing.load()
        XCTAssertEqual(failing.stateTone, .error)
        failing.setOfflineForTesting(true)
        XCTAssertEqual(failing.stateTone, .offline, "a failed load while offline is the offline card")
        failing.setOfflineForTesting(false)

        let loaded = PosePickerViewModel(service: StubPoseService(result: [samplePose]))
        await loaded.load()
        XCTAssertNil(loaded.stateTone, "a loaded grid draws no card")
        loaded.query = "no-such-pose"
        XCTAssertEqual(loaded.stateTone, .empty)
        XCTAssertTrue(loaded.emptyIsNoMatch)
        loaded.query = ""
        loaded.setOfflineForTesting(true)
        // R5 (`guide-picker.js:145-148`): offline over a populated grid is a NOTICE above the grid,
        // not a card replacing it — the grid has to survive a connectivity drop.
        XCTAssertNil(loaded.stateTone, "a populated grid keeps the content area")
        XCTAssertTrue(loaded.showsOfflineNotice)
        // R4 (`guide-picker.js:130-140`): the prototype returns early on an empty result set, so the
        // no-match card wins over the offline notice even while offline. Checking `isOffline` first
        // inverted that precedence.
        loaded.query = "no-such-pose"
        XCTAssertEqual(loaded.stateTone, .empty, "an empty result beats offline")
        XCTAssertTrue(loaded.emptyIsNoMatch)
        XCTAssertFalse(loaded.showsOfflineNotice, "the empty branch hides the grid and never reaches the notice")

        // R6: the prototype's offline card has no retry action, so dismissal must drop the result —
        // otherwise a failed fetch while offline strands the sheet with no way to re-run it.
        loaded.query = ""
        loaded.prepareForDismissal()
        XCTAssertEqual(loaded.stateTone, .loading, "dismissal resets to the retrying idle state")
        XCTAssertFalse(loaded.showsOfflineNotice, "R7: monitoring stops and the offline reading is cleared")

        let emptyCatalogue = PosePickerViewModel(service: StubPoseService(result: []))
        await emptyCatalogue.load()
        XCTAssertEqual(emptyCatalogue.stateTone, .empty)
        XCTAssertFalse(emptyCatalogue.emptyIsNoMatch)
        emptyCatalogue.setOfflineForTesting(true)
        XCTAssertEqual(emptyCatalogue.stateTone, .empty, "an empty catalogue is not an offline state")
    }

    // MARK: Account — the only `.success` producer (drivable, gets a real screenshot too)

    func testAccountSignedOutUsesSuccessTone() {
        XCTAssertEqual(AccountScreen.signedOutTone, .success)
    }

    // MARK: Helpers

    private func assertColor(_ color: Color, _ hex: UInt, _ label: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, CGFloat((hex >> 16) & 0xff) / 255, accuracy: 0.004, "\(label) red", file: file, line: line)
        XCTAssertEqual(g, CGFloat((hex >> 8) & 0xff) / 255, accuracy: 0.004, "\(label) green", file: file, line: line)
        XCTAssertEqual(b, CGFloat(hex & 0xff) / 255, accuracy: 0.004, "\(label) blue", file: file, line: line)
    }
}
