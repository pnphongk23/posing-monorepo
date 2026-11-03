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

    /// Search copy: the screen title and the confirmed-query heading (F3 removed the result count).
    func testSearchResultsCopyMatchesPrototype() {
        XCTAssertEqual(SearchResultsCopy.screenTitle, "Search")
        XCTAssertEqual(SearchResultsCopy.kicker, "YOUR MATCHES")
        XCTAssertEqual(SearchResultsCopy.heading(query: "   "), "Results")
        XCTAssertEqual(SearchResultsCopy.heading(query: "Warrior"), "Results for “Warrior”")
    }

    func testPoseMasonryAssignsNextCardToShortestColumn() {
        let assignments = PoseGridMetrics.columnAssignments(
            for: [0.5, 1, 0.5, 1, 0.5],
            columnWidth: 100,
            itemSpacing: 0,
            labelHeight: 0,
            labelSpacing: 0
        )

        XCTAssertEqual(assignments, [0, 1, 1, 0, 0])
    }

    @MainActor func testPoseAspectRatioCacheKeepsRealImageRatio() {
        let cache = PoseAspectRatioCache.shared
        cache.resetForTesting()
        defer { cache.resetForTesting() }

        XCTAssertEqual(cache.ratio(for: "portrait"), 1, accuracy: 0.0001)
        cache.updateRatio(width: 300, height: 400, for: "portrait")
        XCTAssertEqual(cache.ratio(for: "portrait"), 0.75, accuracy: 0.0001)
        cache.updateRatio(width: 0, height: 400, for: "portrait")
        XCTAssertEqual(cache.ratio(for: "portrait"), 0.75, accuracy: 0.0001)
    }

    @MainActor func testPoseArtworkDownsampleBoundsUseUnpaddedColumnWidth() {
        let points = PoseGridMetrics.cardArtworkPoints
        XCTAssertEqual(points.width, PoseGridMetrics.columnWidth, accuracy: 0.5)
        XCTAssertEqual(
            points.height,
            points.width / PoseGridMetrics.minimumDownsampleAspectRatio,
            accuracy: 0.5
        )
    }

    @MainActor func testPoseHeroCardMetricsUseFullBleedWidthAndFillArtwork() {
        // S2: the detail hero is full-bleed (artboard 04-pose-detail-loaded), not an inset card.
        XCTAssertEqual(
            PoseDetailLayoutMetrics.heroCardWidth,
            UIScreen.main.bounds.width,
            accuracy: 0.5
        )
        XCTAssertEqual(
            PoseDetailLayoutMetrics.heroCardWidth / PoseDetailLayoutMetrics.heroCardHeight,
            PoseDetailLayoutMetrics.heroCardAspectRatio,
            accuracy: 0.0001
        )
        // The photo owns the whole card: decoded at card width, bounded only by the tallest
        // ratio the card can draw.
        XCTAssertEqual(
            PoseDetailLayoutMetrics.heroArtworkPoints.width,
            PoseDetailLayoutMetrics.heroCardWidth,
            accuracy: 0.5
        )
        XCTAssertEqual(
            PoseDetailLayoutMetrics.heroArtworkPoints.height,
            PoseDetailLayoutMetrics.heroArtworkPoints.width / PoseDetailLayoutMetrics.minimumDownsampleAspectRatio,
            accuracy: 0.5
        )
    }

    @MainActor func testPoseHeroAspectRatioFollowsCachedPhotoRatio() {
        // Unloaded photo: prototype card, so the shimmer and the first frame agree.
        XCTAssertEqual(
            PoseDetailLayoutMetrics.heroAspectRatio(cachedPhotoRatio: nil),
            PoseDetailLayoutMetrics.heroCardAspectRatio,
            accuracy: 0.0001
        )
        // Degenerate cache entries never collapse the card.
        XCTAssertEqual(
            PoseDetailLayoutMetrics.heroAspectRatio(cachedPhotoRatio: 0),
            PoseDetailLayoutMetrics.heroCardAspectRatio,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            PoseDetailLayoutMetrics.heroAspectRatio(cachedPhotoRatio: .nan),
            PoseDetailLayoutMetrics.heroCardAspectRatio,
            accuracy: 0.0001
        )
        // Known photo: the card is exactly the photo's box — no letterbox, no inset.
        let portrait: CGFloat = 3.0 / 4.0
        let ratio = PoseDetailLayoutMetrics.heroAspectRatio(cachedPhotoRatio: portrait)
        XCTAssertEqual(ratio, portrait, accuracy: 0.0001)
        let cardHeight = PoseDetailLayoutMetrics.heroCardWidth / ratio
        XCTAssertEqual(cardHeight, PoseDetailLayoutMetrics.heroCardWidth * 4.0 / 3.0, accuracy: 0.5)
        // The decode box must cover the drawn box for every ratio the card can draw.
        XCTAssertGreaterThanOrEqual(
            PoseDetailLayoutMetrics.heroArtworkPoints.height,
            cardHeight,
            "hero artwork decode box must cover the drawn card height"
        )
    }

    func testTryPoseOpensCameraWithoutPremium() {
        var openedPoseID: String?
        routeTryPoseToCamera(samplePose, isPrivate: false) { request in openedPoseID = request.pose.id }
        XCTAssertEqual(openedPoseID, samplePose.id)
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

    // MARK: - "Browse poses" leaves Saved for the catalogue (TC-SAV-004)

    /// The panel's Browse runs the app root's action when the app provided one, and the screen's own
    /// dismiss when it did not (a preview, or a test that mounts the surface alone). Anything else is a
    /// dead button in one of the two cases.
    ///
    /// Mutation target: return `fallback` unconditionally and the first two assertions go red; return the
    /// action unconditionally and the last one does.
    @MainActor func testBrowsePosesPrefersTheAppRootAndKeepsADismissFallback() {
        final class Counter: @unchecked Sendable { var calls = 0 }
        let root = Counter()
        let fallback = Counter()

        APBrowsePosesRule.browse(action: APBrowsePosesAction { root.calls += 1 }, fallback: { fallback.calls += 1 })()
        XCTAssertEqual(root.calls, 1, "the app root's action is what the panel runs")
        XCTAssertEqual(fallback.calls, 0, "and the fallback is not also run")

        APBrowsePosesRule.browse(action: nil, fallback: { fallback.calls += 1 })()
        XCTAssertEqual(fallback.calls, 1, "a surface mounted outside the app still closes")
        XCTAssertEqual(root.calls, 1)
    }

    // MARK: - The route belongs to the request (PoseServing.posesPage(query:filter:offset:limit:))

    /// The signature Search and the camera picker now share answers **exactly** what Search shows: same
    /// route, same ids, same order, including the signed-out degradation to the community feed.
    ///
    /// Both calls go through one service instance: the adapter's routed window read, and the Search
    /// screen's own model built the way the app builds it. If they ever disagree, a screen would show a
    /// collection it did not ask for — the class of bug the process-wide slot caused.
    @MainActor func testTheRoutedWindowReadMatchesWhatSearchShows() async throws {
        let remote = SearchRouteRemote()
        remote.communityItems = ["a", "b", "c"].compactMap { id in
            try? JSONDecoder().decode(CommunityPose.self, from: Data("""
            {"poseId":"\(id)","name":"Pose \(id)","skeletonUrl":"/s.png","thumbnailUrl":"/t.jpg","status":"published"}
            """.utf8))
        }
        XCTAssertEqual(remote.communityItems.count, 3, "the fixture rows decode")
        // The app's wiring: the adapter's session probe is the same boundary the model follows.
        let adapter = PoseAPIServiceAdapter(
            remote: remote,
            baseURL: "https://api.example.com",
            filterState: PoseFilterState(),
            hasSession: { false }
        )

        // The picker shape: one routed window read, no model in between.
        let window = try await adapter.posesPage(query: "zzqqxx", filter: .all, offset: 0, limit: 20)

        // The Search shape: the model the app builds, on the same service instance.
        let model = PosesViewModel(
            service: adapter,
            boundary: SessionBoundary(tokenStorage: SignedOutTokenStorage())
        )
        model.filter = .all
        model.query = "zzqqxx"
        await model.load()

        XCTAssertEqual(
            window.poses.map(\.id),
            model.state.rows.map(\.id),
            "the routed window read and the Search screen see the same ids in the same order"
        )
        XCTAssertEqual(remote.savedCallCount, 0, "signed out, neither path asks for the account collection")
        XCTAssertEqual(remote.communityCallCount, 2, "both reads are the community feed")
        XCTAssertEqual(remote.lastQuery, "zzqqxx", "and both carry the term")
    }

    /// A signed-in reader still gets the account routes through the same signature.
    @MainActor func testTheRoutedWindowReadKeepsTheAccountRoutesWithASession() async throws {
        let remote = SearchRouteRemote()
        let adapter = PoseAPIServiceAdapter(
            remote: remote,
            baseURL: "https://api.example.com",
            filterState: PoseFilterState(),
            hasSession: { true }
        )

        _ = try await adapter.posesPage(query: nil, filter: .saved, offset: 0, limit: 20)
        XCTAssertEqual(remote.savedCallCount, 1)

        _ = try await adapter.posesPage(query: nil, filter: .all, offset: 0, limit: 20)
        XCTAssertEqual(remote.savedCallCount, 2, "`.all` merges the saved collection")
        XCTAssertEqual(remote.communityCallCount, 1)
    }

    // MARK: - One owner of "the shown list changed → reload"

    /// Opening Search, tapping a source chip, or typing is **one read each** — the model owns the reload
    /// and debounces it. The views used to set `filter` *and* call `load()` themselves, and `PosesScreen`
    /// watched the filter with its own `load()`, so an open cost two or three requests for the same window.
    ///
    /// The model here is built the way `AppFeatureRoot` builds it (adapter handed in, no filter slot), and
    /// the debounce is shortened so the test does not sleep for a third of a second.
    ///
    /// Mutation target: drop `scheduleSearch()` from the filter observer and every count becomes one short.
    @MainActor func testTheCollectionAndTheQueryEachTriggerExactlyOneRead() async {
        let remote = SearchRouteRemote()
        let adapter = PoseAPIServiceAdapter(
            remote: remote,
            baseURL: "https://api.example.com",
            filterState: PoseFilterState()
        )
        let model = PosesViewModel(
            service: adapter,
            boundary: SessionBoundary(tokenStorage: SignedOutTokenStorage()),
            debounceNanoseconds: 30_000_000
        )

        // Search opens: the screen sets the collection and nothing else.
        model.filter = .all
        await waitUntil("the open read") { remote.callCount == 1 }
        try? await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(remote.callCount, 1, "opening Search is exactly one read")

        // A source chip: one more.
        model.filter = .saved
        await waitUntil("the chip read") { remote.callCount == 2 }
        try? await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(remote.callCount, 2, "one read per collection change")

        // A burst (typing, or tapping two chips quickly) settles to one more read, not three.
        model.updateQuery("z")
        model.updateQuery("zz")
        model.filter = .community
        await waitUntil("the debounced read") { remote.callCount >= 3 }
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(remote.callCount, 3, "the debounce collapses the burst into one read")

        // The query the last read carried is the last thing typed.
        XCTAssertEqual(remote.lastQuery, "zz")
    }

    /// Opening the real Search screen reads the list **once**.
    ///
    /// The views used to set the collection and read it themselves, and `PosesScreen` watched the filter with
    /// a read of its own, so an open cost two or three requests for the same window. This hosts the screen
    /// the app opens, over a recording service, and counts: the model's reload is the only one.
    ///
    /// Mutation target: put a `load()` back in the screen's open task (or restore the filter observer in
    /// `PosesScreen`) and the count becomes two or three.
    @MainActor func testOpeningTheRealSearchScreenReadsTheListOnce() async {
        let remote = SearchRouteRemote()
        let adapter = PoseAPIServiceAdapter(
            remote: remote,
            baseURL: "https://api.example.com",
            filterState: PoseFilterState()
        )
        let model = PosesViewModel(
            service: adapter,
            boundary: SessionBoundary(tokenStorage: SignedOutTokenStorage()),
            debounceNanoseconds: 30_000_000
        )
        let probe = APViewProbe(SearchScreen(model: model), size: CGSize(width: 393, height: 700))
        defer { probe.tearDown() }
        probe.settle()

        await waitUntil("the screen's read") { remote.callCount >= 1 }
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(remote.callCount, 1, "opening Search is one read of the list, not two or three")
    }

    // MARK: - The offline catalog never invents "no match" for a search

    /// The community route already refuses to answer a *search* from the local catalog when nothing matches
    /// ("the server owns search matching, so a local name filter that matches nothing is not an answer").
    /// The `.all` route returned the empty merge instead, so a search whose rows the catalog had not mirrored
    /// — or an offline one — reported "no poses match" without asking anyone.
    ///
    /// Mutation target: return the empty merge and `communityCallCount` stays 0 while the page is empty.
    @MainActor func testTheAllRouteAsksTheServerWhenTheLocalCatalogCannotMatchASearch() async throws {
        let cache = try TempPoseCatalog()
        defer { cache.cleanUp() }
        let seeder = PoseAPIServiceAdapter(
            remote: SeedingPoseRemote(),
            baseURL: "https://api.example.com",
            filterState: PoseFilterState(),
            cache: cache.store
        )
        // Mirror one community row into the catalog, then search `.all` for something it cannot match.
        _ = try await seeder.posesPage(query: "pose", filter: .community, offset: 0, limit: 20)

        let remote = SearchRouteRemote()
        let adapter = PoseAPIServiceAdapter(
            remote: remote,
            baseURL: "https://api.example.com",
            filterState: PoseFilterState(),
            cache: cache.store,
            hasSession: { true }
        )
        let page = try await adapter.posesPage(query: "zzqqxx", filter: .all, offset: 0, limit: 20)

        XCTAssertTrue(page.poses.isEmpty, "the server's answer is what the screen shows")
        XCTAssertEqual(
            remote.communityCallCount, 1,
            "a local miss is not an answer: the request went to the server"
        )
    }

    // MARK: - A search with no matches renders its empty state

    /// A signed-out search must reach the catalogue, not an account route.
    ///
    /// The regression this covers: routing the displayed `.all` into the process-wide slot made the
    /// search ask `GET /api/me/saved` without a session; the server answers `401`, and a 401 on a
    /// credential-less request makes the session boundary "clear" a session that never existed
    /// (`SessionBoundary.performRefresh`), which bumps the generation and resets every model — so the
    /// answer was dropped and the screen sat in `.loading`. Measured: the results area showed only
    /// "Searching" for 20 s while the deploy's HTTP log showed `GET /api/me/saved 401` repeating, and no
    /// banner was ever mounted.
    ///
    /// Mutation target: route the read by the model's `filter` alone and `savedCallCount` becomes 1.
    @MainActor func testASignedOutSearchReadsTheCatalogueAndRendersItsEmptyState() async {
        let remote = SearchRouteRemote()
        let adapter = PoseAPIServiceAdapter(
            remote: remote,
            baseURL: "https://api.example.com",
            filterState: PoseFilterState()
        )
        let model = PosesViewModel(
            service: adapter,
            boundary: SessionBoundary(tokenStorage: SignedOutTokenStorage())
        )
        model.filter = .all
        model.query = "zzqqxx"

        await model.load()

        XCTAssertEqual(remote.savedCallCount, 0, "no account read without a session")
        XCTAssertEqual(remote.communityCallCount, 1, "the catalogue is what a signed-out reader gets")
        XCTAssertEqual(remote.lastQuery, "zzqqxx", "and the term reaches the server")
        guard case .empty = model.state else {
            return XCTFail("a search with no matches settles as empty, not as a stuck loading state")
        }
        XCTAssertEqual(
            APCatalogPresentationRule.presentation(
                for: model.state,
                hasVisiblePoses: !model.state.rows.isEmpty,
                isFilterActive: model.filter != .all
            ),
            .empty,
            "one of the two states the search panel renders as the no-match banner"
        )
    }

    /// A session change while the list is loading must not leave it `.idle`, which every panel draws as
    /// "loading": the reload goes through the route, which degrades to the community feed when signed out.
    @MainActor func testASessionChangeSettlesTheListInsteadOfLeavingItIdle() async {
        let remote = SearchRouteRemote()
        let adapter = PoseAPIServiceAdapter(
            remote: remote,
            baseURL: "https://api.example.com",
            filterState: PoseFilterState()
        )
        let boundary = SessionBoundary(tokenStorage: SignedOutTokenStorage())
        let model = PosesViewModel(service: adapter, boundary: boundary)
        model.filter = .all
        model.query = "zzqqxx"
        model.state = .loading

        model.resetForSessionChange(.signInRequired)
        // The reload is kicked on the main actor, so pump turns until it settles.
        for _ in 0..<40 where model.state.isWaitingForAnswer {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertFalse(model.state.isWaitingForAnswer, "the list settles: \(model.state)")
        XCTAssertEqual(remote.savedCallCount, 0, "signed out, the reload reads the catalogue")
    }

    // MARK: - Browse poses: the control, the environment, the real stack

    /// The app root's action really reaches a screen pushed inside the Poses navigation stack: the
    /// report's suspicion that the environment is nil inside Settings → Saved is false (a destination
    /// inherits the stack's environment), and this is the assertion for it.
    ///
    /// Mutation target: move `.environment(\.apBrowsePoses, …)` below the navigation container and the
    /// destination stops seeing it.
    @MainActor func testTheBrowseActionReachesAPushedDestination() async throws {
        guard #available(iOS 16.0, *) else { throw XCTSkip("NavigationStack is iOS 16 or newer") }
        let probe = BrowseActionProbe()
        let state = BrowseStackState()
        let host = UIHostingController(
            rootView: BrowseEnvProbeHarness(state: state, probe: probe)
                .environment(\.apBrowsePoses, APBrowsePosesAction { probe.rootActionCalls += 1 })
        )
        let window = hostedWindow(host)
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        await settleHosting()

        state.showsDestination = true
        await settleHosting()

        XCTAssertEqual(probe.destinationSawAction, true, "a pushed destination reads the root's action")
        probe.invokeCapturedAction()
        XCTAssertEqual(probe.rootActionCalls, 1, "and calling it runs the root's work")
    }

    /// The mechanism the fix relies on, on a real hosted stack with the **real** Saved screen pushed two
    /// levels deep (a Settings stand-in that applies the same modifier SettingsScreen does, then
    /// `SavedPosesScreen`): the root's signal makes each pushed screen leave, and the stack ends at its
    /// root. Measured before the fix: an identity change on the container left all three view controllers
    /// in place, which is exactly "Saved stays on screen".
    ///
    /// Mutation target: drop the modifier from either level (the harness applies the real one) and the
    /// depth stays above one.
    @MainActor func testBrowsingLeavesTheRealSavedStackAtItsRoot() async throws {
        guard #available(iOS 16.0, *) else { throw XCTSkip("NavigationStack is iOS 16 or newer") }
        let model = PosesViewModel(service: EmptySavedPoseService())
        model.state = .empty
        let state = BrowseStackState()
        let host = UIHostingController(rootView: BrowseStackHarness(state: state, model: model))
        let window = hostedWindow(host)
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        await settleHosting()

        state.showsDestination = true
        state.showsSaved = true
        let pushed = await waitForNavigationDepth(3, in: window)
        XCTAssertTrue(state.savedAppeared, "the Saved screen is on the stack before the action runs")
        XCTAssertEqual(pushed, 3, "root + Settings + Saved are pushed (last depth: \(pushed))")

        // Exactly what `AppFeatureRoot.showPosesCatalogue()` does for the navigation half.
        let popped = APPushedStack.popToRoot(in: window)
        XCTAssertTrue(popped, "the container reports the pop")

        let settled = await waitForNavigationDepth(1, in: window)
        XCTAssertEqual(settled, 1, "the stack is at its root: only the catalogue is left (last depth: \(settled))")
    }

    /// Pumps the main actor until `condition` holds — the model publishes its counts, so a test waits on
    /// that instead of on a guessed sleep.
    @MainActor private func waitUntil(
        _ what: String,
        timeout: TimeInterval = 3,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTFail("timed out waiting for \(what)")
    }

    // MARK: - Hosting helpers

    private func hostedWindow(_ host: UIHostingController<some View>) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host
        window.makeKeyAndVisible()
        return window
    }

    /// Gives SwiftUI turns to lay out and drive a presentation: suspension on the main actor is what
    /// lets its transaction run between calls.
    @MainActor private func settleHosting() async {
        for _ in 0..<10 {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
    }

    /// Waits for the hosted stack to reach `depth` (a push or a pop is a run-loop turn plus an
    /// animation), and reports the depth it last saw. A fixed settle window made this test flaky under a
    /// full-suite load; polling to a deadline does not.
    @MainActor private func waitForNavigationDepth(
        _ depth: Int,
        in window: UIWindow,
        timeout: TimeInterval = 5
    ) async -> Int {
        let deadline = Date().addingTimeInterval(timeout)
        var observed = navigationDepth(in: window)
        while observed != depth, Date() < deadline {
            try? await Task.sleep(nanoseconds: 30_000_000)
            observed = navigationDepth(in: window)
        }
        return observed
    }

    /// Pushed screens in the hosted navigation container, however deep the UIKit tree nests it.
    private func navigationDepth(in window: UIWindow) -> Int {
        func find(_ controller: UIViewController) -> UINavigationController? {
            if let navigation = controller as? UINavigationController { return navigation }
            for child in controller.children where !child.isBeingDismissed {
                if let found = find(child) { return found }
            }
            return nil
        }
        guard let root = window.rootViewController, let navigation = find(root) else { return 0 }
        return navigation.viewControllers.count
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

    /// BUG-261029-03: the same surface speaks two registers, and only a session that really ended on
    /// this install may use the "again" one.
    func testAccountSignInCardSelectsCopyFromTheInstallHistory() {
        let firstVisit = AccountStateCopy.signInCard(hasSignedInBefore: false)
        XCTAssertEqual(firstVisit.title, "Not signed in")
        XCTAssertEqual(firstVisit.message, "Sign in to save poses.")
        XCTAssertFalse(firstVisit.message.lowercased().contains("again"))

        let returning = AccountStateCopy.signInCard(hasSignedInBefore: true)
        XCTAssertEqual(returning.title, "Signed out")
        XCTAssertEqual(returning.message, "Sign in again to access your Saved poses.")
    }

    /// TC-SAV-001: the Saved gate is reachable without ever signing in, so its copy must stay neutral
    /// in both registers — a signed-out user and a first-time visitor read the same card there.
    func testSavedSignInGateCopyNeverAsksToSignInAgain() {
        XCTAssertEqual(PoseResultsStateCopy.savedSignInTitle, "Sign in to view your saved poses")
        XCTAssertEqual(
            PoseResultsStateCopy.savedSignInMessage,
            "Your saved poses are tied to your account. Sign in to keep them synced."
        )
        for copy in [PoseResultsStateCopy.savedSignInTitle, PoseResultsStateCopy.savedSignInMessage] {
            XCTAssertFalse(copy.lowercased().contains("again"), "Saved gate copy must not say \"again\": \(copy)")
        }
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
    /// F4 reads them from the shared `APStateTone`, so the feature card and the catalogue panel agree.
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

    /// `empty-state.css`: base copy is the body ink; `.nb-empty-state--loading` dims it to the
    /// secondary ink while the title stays `primaryText` (direction-B tokens since F4).
    func testOnlyLoadingToneDimsTheCopy() {
        for tone in FeatureStateTone.allCases {
            assertColor(tone.copyColor, tone == .loading ? 0x5E574C : 0x121212, "copy for .\(tone)")
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
        // S2 replaced `PoseResultsList` with the AP presentation rule; the mapping it verifies is the
        // same one: idle/loading render the loading panel, empty/failed their panels, loaded the list.
        let loadingModel = PosesViewModel(service: StubPoseService(result: []))
        XCTAssertEqual(presentation(for: loadingModel), .loading)

        let emptyModel = PosesViewModel(service: StubPoseService(result: []))
        await emptyModel.load()
        XCTAssertEqual(presentation(for: emptyModel), .empty)

        let failedModel = PosesViewModel(service: FailingPoseService())
        await failedModel.load()
        XCTAssertEqual(presentation(for: failedModel), .failed)

        let loadedModel = PosesViewModel(service: StubPoseService(result: [samplePose]))
        await loadedModel.load()
        XCTAssertEqual(presentation(for: loadedModel), .grid)
    }

    @MainActor private func presentation(for model: PosesViewModel) -> APCatalogPresentation {
        APCatalogPresentationRule.presentation(
            for: model.state,
            hasVisiblePoses: !model.state.rows.isEmpty,
            isFilterActive: false
        )
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

// MARK: - "Browse poses" hosting harness

/// The app root's state that the browse action writes, outside the view so a test can drive it.
@MainActor
final class BrowseStackState: ObservableObject {
    @Published var tab: AppTab = .poses
    @Published var showsDestination = false
    @Published var showsSaved = false
    @Published var savedAppeared = false
    @Published var savedDisappeared = false
    @Published var settingsDisappeared = false
}

/// The app's composition shape, hosted for real: one navigation container, a root marker, a destination
/// reached the way Settings is reached from the Poses tab — and the real `SavedPosesScreen` pushed on top of
/// it. The structure is the app's; the pop under test is the shipped `APPushedStack`.
@available(iOS 16.0, *)
struct BrowseStackHarness: View {
    @ObservedObject var state: BrowseStackState
    let model: PosesViewModel

    var body: some View {
        NavigationStack {
            VStack {
                Text("POSES ROOT")
                    .accessibilityIdentifier("poses.open-search")
            }
            .navigationDestination(isPresented: $state.showsDestination) {
                VStack {
                    Text("SETTINGS")
                }
                .navigationDestination(isPresented: $state.showsSaved) {
                    SavedPosesScreen(model: model)
                        .onAppear { state.savedAppeared = true }
                        .onDisappear { state.savedDisappeared = true }
                }
            }
        }
    }
}

/// The narrow shape the environment question needs: one navigation container with the action applied
/// above it, and a destination that reports what it can see.
@available(iOS 16.0, *)
struct BrowseEnvProbeHarness: View {
    @ObservedObject var state: BrowseStackState
    let probe: BrowseActionProbe

    var body: some View {
        NavigationStack {
            Text("POSES ROOT")
                .navigationDestination(isPresented: $state.showsDestination) {
                    BrowseActionDestinationProbe(probe: probe)
                }
        }
    }
}

/// A pushed screen that reports whether it can see the app root's browse action, and keeps it so the
/// test can run exactly what the destination would run.
@MainActor
final class BrowseActionProbe {
    var destinationSawAction: Bool?
    var rootActionCalls = 0
    private var captured: APBrowsePosesAction?

    func record(_ action: APBrowsePosesAction?) {
        destinationSawAction = action != nil
        captured = action
    }

    func invokeCapturedAction() {
        captured?()
    }
}

@available(iOS 16.0, *)
struct BrowseActionDestinationProbe: View {
    let probe: BrowseActionProbe
    @Environment(\.apBrowsePoses) private var browsePoses

    var body: some View {
        Text("DESTINATION")
            .onAppear { probe.record(browsePoses) }
    }
}

/// A catalogue with nothing in it: the Saved screen only has to exist for this harness.
private struct EmptySavedPoseService: PoseServing {
    func poses(query: String?) async throws -> [NativePose] { [] }
    func posesPage(query: String?, offset: Int, limit: Int) async throws -> PosePage { .end }
    func pose(id: String) async throws -> NativePose { throw PoseAdapterError.poseNotFound(id) }
}

/// The catalogue as the signed-out search sees it: no matches for the term, and a saved route that is
/// only counted (asking it without a session is what the fix prevents).
private final class SearchRouteRemote: PoseRemoteFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var communityCount = 0
    private var savedCount = 0
    private var query: String?
    /// The rows the community feed answers with, in server order (wire shape, as the adapter expects).
    var communityItems: [CommunityPose] = []

    var communityCallCount: Int { locked { communityCount } }
    /// Every window read this server answered, whatever the route.
    var callCount: Int { locked { communityCount + savedCount } }
    var savedCallCount: Int { locked { savedCount } }
    var lastQuery: String? { locked { query } }

    func fetchCommunity(page: Int, limit: Int, query text: String?) async throws -> PoseRemotePage {
        locked {
            communityCount += 1
            query = text
        }
        return PoseRemotePage(poses: communityItems, total: communityItems.count)
    }

    func fetchSaved(page: Int, limit: Int) async throws -> PoseRemotePage {
        locked { savedCount += 1 }
        return PoseRemotePage(poses: [], total: 0)
    }

    /// `NSLock.withLock` is iOS 16+, and `lock()` is unavailable straight from an async context.
    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private final class SignedOutTokenStorage: TokenStoring, @unchecked Sendable {
    func saveCredentials(_ credentials: SessionCredentials) {}
    func loadCredentials() -> SessionCredentials? { nil }
    func clearCredentials() {}
}

private final class SignedInTokenStorage: TokenStoring, @unchecked Sendable {
    private var credentials: SessionCredentials? = SessionCredentials(accessToken: "access", refreshToken: "refresh")
    func saveCredentials(_ credentials: SessionCredentials) { self.credentials = credentials }
    func loadCredentials() -> SessionCredentials? { credentials }
    func clearCredentials() { credentials = nil }
}

/// A state that is still waiting for an answer: exactly what the bug left on screen. A failure has
/// settled (it draws the error panel), so it counts as an answer.
private extension Loadable {
    var isWaitingForAnswer: Bool {
        switch self {
        case .idle, .loading: return true
        case .empty, .loaded, .failed: return false
        }
    }
}

/// A throwaway offline catalog for the adapters under test.
@MainActor
private final class TempPoseCatalog {
    let root: URL
    let database: AppDatabase

    /// No background revalidation, so "did the read ask the server?" is decided by the read itself.
    var store: PoseCatalogCacheStore {
        PoseCatalogCacheStore(
            repository: PoseRepository(database: database),
            scheduler: SilentPoseRefreshScheduler()
        )
    }

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pose-catalog-\(UUID().uuidString)", isDirectory: true)
        database = try AppDatabase(
            location: AppDatabaseLocation(url: root.appendingPathComponent("aipose.db"), kind: .freshInstall)
        )
    }

    func cleanUp() {
        try? database.pool.close()
        try? FileManager.default.removeItem(at: root)
    }
}

/// A scheduler that never runs anything: stale-while-revalidate work cannot mask whether the *read* asked.
private struct SilentPoseRefreshScheduler: PoseRefreshScheduling {
    func schedule(_ operation: @escaping @Sendable () async -> Void) {}
}

/// One community row, so the catalog has something mirrored that does not match the search term.
private struct SeedingPoseRemote: PoseRemoteFetching {
    func fetchCommunity(page: Int, limit: Int, query: String?) async throws -> PoseRemotePage {
        let pose = try JSONDecoder().decode(CommunityPose.self, from: Data("""
        {"poseId":"mirrored-1","name":"Mirrored Pose","skeletonUrl":"/s.png","thumbnailUrl":"/t.jpg","status":"published"}
        """.utf8))
        return PoseRemotePage(poses: [pose], total: 1)
    }

    func fetchSaved(page: Int, limit: Int) async throws -> PoseRemotePage { PoseRemotePage(poses: [], total: 0) }
}
