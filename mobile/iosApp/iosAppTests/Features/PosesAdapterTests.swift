import XCTest
@testable import iosApp

final class PosesAdapterTests: XCTestCase {
    func testCommunityPoseMappingResolvesRelativeThumbnail() throws {
        let pose = try Self.decodePose("""
        {
          "poseId": "p1",
          "name": "Sunset Stand",
          "skeletonUrl": "/skeleton.png",
          "thumbnailUrl": "/thumb.jpg",
          "difficulty": "Easy",
          "tags": ["standing"],
          "description": "Face the light",
          "bodyParts": ["arms"],
          "status": "published"
        }
        """)
        let native = CommunityPoseMapper.map(pose, isSaved: false, baseURL: "https://api.example.com")
        XCTAssertEqual(native.id, "p1")
        XCTAssertEqual(native.name, "Sunset Stand")
        XCTAssertEqual(native.category, "Easy")
        XCTAssertEqual(native.imageURL?.absoluteString, "https://api.example.com/thumb.jpg")
        XCTAssertEqual(native.instructions, ["Face the light"])
        XCTAssertFalse(native.isSaved)
    }

    func testSavedFilterRoutesToSavedEndpoint() async throws {
        let remote = StubPoseRemote()
        remote.savedItems = [try Self.decodePose("""
        {"poseId":"standing-1","name":"Soft Standing","skeletonUrl":"/s.png","thumbnailUrl":"/t.jpg","status":"published"}
        """)]
        let filterState = PoseFilterState()
        filterState.filter = .saved
        let adapter = PoseAPIServiceAdapter(remote: remote, baseURL: "https://api.example.com", filterState: filterState)
        let poses = try await adapter.poses(query: nil)
        XCTAssertEqual(remote.communityCallCount, 0)
        XCTAssertEqual(remote.savedCallCount, 1)
        XCTAssertEqual(poses.count, 1)
        XCTAssertTrue(poses[0].isSaved)
    }

    func testCommunityFilterPassesSearchQuery() async throws {
        let remote = StubPoseRemote()
        let filterState = PoseFilterState()
        filterState.filter = .community
        let adapter = PoseAPIServiceAdapter(remote: remote, baseURL: "https://api.example.com", filterState: filterState)
        _ = try await adapter.poses(query: "sunset")
        XCTAssertEqual(remote.communityCallCount, 1)
        XCTAssertEqual(remote.lastCommunityQuery, "sunset")
        XCTAssertEqual(remote.savedCallCount, 0)
    }

    func testSavedFilterAppliesLocalQueryFiltering() async throws {
        let remote = StubPoseRemote()
        remote.savedItems = [
            try Self.decodePose("""
            {"poseId":"soft","name":"Soft Standing","skeletonUrl":"/s.png","thumbnailUrl":"/t.jpg","status":"published"}
            """),
            try Self.decodePose("""
            {"poseId":"hard","name":"Hard Lean","skeletonUrl":"/s.png","thumbnailUrl":"/t.jpg","status":"published"}
            """),
        ]
        let filterState = PoseFilterState()
        filterState.filter = .saved
        let adapter = PoseAPIServiceAdapter(remote: remote, baseURL: "https://api.example.com", filterState: filterState)
        let poses = try await adapter.poses(query: "soft")
        XCTAssertEqual(remote.savedCallCount, 1)
        XCTAssertEqual(remote.communityCallCount, 0)
        XCTAssertEqual(poses.map(\.name), ["Soft Standing"])
    }

    func testAllFilterFetchesBothEndpointsCommunityFirst() async throws {
        let remote = StubPoseRemote()
        remote.communityItems = [try Self.decodePose("""
        {"poseId":"shared","name":"Shared Pose","skeletonUrl":"/s.png","thumbnailUrl":"/t.jpg","status":"published"}
        """)]
        remote.savedItems = [
            try Self.decodePose("""
            {"poseId":"shared","name":"Shared Pose","skeletonUrl":"/s.png","thumbnailUrl":"/t.jpg","status":"published"}
            """),
            try Self.decodePose("""
            {"poseId":"saved-only","name":"Saved Only","skeletonUrl":"/s.png","thumbnailUrl":"/t.jpg","status":"published"}
            """),
        ]
        let filterState = PoseFilterState()
          filterState.filter = .all
        let adapter = PoseAPIServiceAdapter(remote: remote, baseURL: "https://api.example.com", filterState: filterState)
        let poses = try await adapter.poses(query: nil)
        XCTAssertEqual(remote.communityCallCount, 1)
        XCTAssertEqual(remote.savedCallCount, 1)
        XCTAssertEqual(poses.map(\.id), ["shared", "saved-only"])
        XCTAssertFalse(poses[0].isSaved)
        XCTAssertTrue(poses[1].isSaved)
    }

    func testAllFilterForwardsQueryToCommunityOnly() async throws {
        let remote = StubPoseRemote()
        let filterState = PoseFilterState()
        filterState.setFilterRawValueForTesting("All")
        let adapter = PoseAPIServiceAdapter(remote: remote, baseURL: "https://api.example.com", filterState: filterState)
        _ = try await adapter.poses(query: "sunset")
        XCTAssertEqual(remote.communityCallCount, 1)
        XCTAssertEqual(remote.lastCommunityQuery, "sunset")
        XCTAssertEqual(remote.savedCallCount, 1)
    }

    func testAllFilterKeepsCommunityResultsWhenSavedEndpointFails() async throws {
        let remote = StubPoseRemote()
        remote.communityItems = [try Self.decodePose("""
        {"poseId":"community-only","name":"Community Only","skeletonUrl":"/s.png","thumbnailUrl":"/t.jpg","status":"published"}
        """)]
        remote.savedError = NSError(domain: "saved", code: 401)
        let filterState = PoseFilterState()
        filterState.setFilterRawValueForTesting("All")
        let adapter = PoseAPIServiceAdapter(remote: remote, baseURL: "https://api.example.com", filterState: filterState)

        let poses = try await adapter.poses(query: nil)

        XCTAssertEqual(remote.communityCallCount, 1)
        XCTAssertEqual(remote.savedCallCount, 1)
        XCTAssertEqual(poses.map(\.id), ["community-only"])
    }

    func testCommunityFirstMergeDedupesSavedDuplicates() {
        let community = [sampleNativePose.withSaved(false)]
        let saved = [sampleNativePose.withSaved(true), sampleNativePose.withSaved(true)]
        let merged = PoseAdapterMerge.communityFirst(community: community, saved: saved)
        XCTAssertEqual(merged.count, 1)
        XCTAssertFalse(merged[0].isSaved)
    }

    @MainActor func testViewModelSavedFilterLoadsSavedOnly() async throws {
        let remote = StubPoseRemote()
        remote.savedItems = [try Self.decodePose("""
        {"poseId":"standing-1","name":"Soft Standing","skeletonUrl":"/s.png","thumbnailUrl":"/t.jpg","status":"published"}
        """)]
        remote.communityItems = [try Self.decodePose("""
        {"poseId":"other","name":"Other","skeletonUrl":"/s.png","thumbnailUrl":"/t.jpg","status":"published"}
        """)]
        let filterState = PoseFilterState()
        let adapter = PoseAPIServiceAdapter(remote: remote, baseURL: "https://api.example.com", filterState: filterState)
        let model = PosesViewModel(service: adapter, filterState: filterState)
        model.filter = .saved
        await model.load()
        XCTAssertEqual(remote.communityCallCount, 0)
        XCTAssertEqual(remote.savedCallCount, 1)
        guard case .loaded(let poses) = model.state else { return XCTFail("Expected loaded") }
        XCTAssertEqual(poses.count, 1)
        XCTAssertTrue(poses[0].isSaved)
    }

    @MainActor func testViewModelSyncsFilterStateBeforeLoad() async throws {
        let remote = StubPoseRemote()
        remote.communityItems = [try Self.decodePose("""
        {"poseId":"standing-1","name":"Soft Standing","skeletonUrl":"/s.png","thumbnailUrl":"/t.jpg","status":"published"}
        """)]
        let filterState = PoseFilterState()
        let adapter = PoseAPIServiceAdapter(remote: remote, baseURL: "https://api.example.com", filterState: filterState)
        let model = PosesViewModel(service: adapter, filterState: filterState)
        model.filter = .community
        await model.load()
        XCTAssertEqual(filterState.filter, .community)
        guard case .loaded(let poses) = model.state else { return XCTFail("Expected loaded") }
        XCTAssertEqual(poses.count, 1)
    }

    @MainActor func testSearchDebounceSchedulesLoad() async {
        let model = PosesViewModel(service: StubPoseService(result: [sampleNativePose]), debounceNanoseconds: 50_000_000)
        model.query = "soft"
        model.scheduleSearch()
        try? await Task.sleep(nanoseconds: 80_000_000)
        guard case .loaded = model.state else { return XCTFail("Expected loaded after debounce") }
    }

    @MainActor func testFailedPoseLoadMapsToFailedState() async {
        let model = PosesViewModel(service: FailingPoseService())
        await model.load()
        guard case .failed = model.state else { return XCTFail("Expected failed") }
    }

    // MARK: - Search results chrome copy (SCR-003-02 RES-001 / RES-002 / ST-003)

    func testSearchResultsCopyHeadingReflectsConfirmedQuery() {
        XCTAssertEqual(SearchResultsCopy.heading(query: ""), "Results")
        XCTAssertEqual(SearchResultsCopy.heading(query: "   "), "Results")
        XCTAssertEqual(SearchResultsCopy.heading(query: "Dancing"), "Results for “Dancing”")
    }

    func testSearchResultsCopyCountLabelMatchesLoadState() {
        XCTAssertEqual(SearchResultsCopy.countLabel(for: .loaded([sampleNativePose])), "1 pose")
        XCTAssertEqual(SearchResultsCopy.countLabel(for: .loaded([sampleNativePose, sampleNativePose])), "2 poses")
        XCTAssertEqual(SearchResultsCopy.countLabel(for: .loaded([])), "0 poses")
        XCTAssertEqual(SearchResultsCopy.countLabel(for: .empty), "0 poses")
        XCTAssertEqual(SearchResultsCopy.countLabel(for: .idle), "Searching…")
        XCTAssertEqual(SearchResultsCopy.countLabel(for: .loading), "Searching…")
        XCTAssertEqual(SearchResultsCopy.countLabel(for: .failed("offline")), "Unavailable")
    }

    func testSearchResultsCopyEmptyStateCopyIsContextAware() {
        XCTAssertEqual(SearchResultsCopy.emptyTitle(query: "Dancing", filter: .all), "No poses found")
        XCTAssertEqual(
            SearchResultsCopy.emptyMessage(query: "Dancing", filter: .all),
            "No poses match “Dancing”. Try a different title or clear the search."
        )
        XCTAssertEqual(SearchResultsCopy.emptyRecoveryTitle(query: "Dancing", filter: .all), "Clear search")

        XCTAssertEqual(SearchResultsCopy.emptyTitle(query: "", filter: .saved), "No saved poses")
        XCTAssertEqual(
            SearchResultsCopy.emptyMessage(query: "", filter: .saved),
            "Save poses from Community to see them here."
        )
        XCTAssertNil(SearchResultsCopy.emptyRecoveryTitle(query: "", filter: .saved))

        XCTAssertEqual(SearchResultsCopy.emptyTitle(query: "", filter: .community), "No poses")
        XCTAssertEqual(SearchResultsCopy.emptyMessage(query: "", filter: .community), "Try another search or category.")
        XCTAssertNil(SearchResultsCopy.emptyRecoveryTitle(query: "", filter: .community))
    }

    @MainActor func testUnmatchedQueryProducesEmptyStateWithoutFabricatedResults() async {
        let model = PosesViewModel(service: StubPoseService(result: [sampleNativePose]))
        model.query = "Dancing"
        await model.load()
        guard case .empty = model.state else { return XCTFail("Expected empty when the service answers []") }
        XCTAssertEqual(SearchResultsCopy.countLabel(for: model.state), "0 poses")
    }

    // MARK: - Search motion contract (SCR-003-02 "Motion and animation", D6)

    func testSearchMotionIsLowIntensityAndReducedMotionAware() {
        XCTAssertNil(SearchMotion.animation(reduceMotion: true))
        XCTAssertNotNil(SearchMotion.animation(reduceMotion: false))
        XCTAssertGreaterThanOrEqual(SearchMotion.stateChangeDuration, 0.10)
        XCTAssertLessThanOrEqual(SearchMotion.stateChangeDuration, 0.25)
    }

    func testPoseServiceBootstrapWiresBundle() {
        let remote = StubPoseRemote()
        let filterState = PoseFilterState()
        let api = PoseAPIService(client: APIClient(baseURL: "https://api.example.com", boundary: SessionBoundary(tokenStorage: KeychainTokenStorage())))
        _ = api
        let bundle = PoseServiceBundle(
            service: PoseAPIServiceAdapter(remote: remote, baseURL: "https://api.example.com", filterState: filterState),
            filterState: filterState,
            bookmarkService: PoseAPIBookmarkService(api: PoseAPIService(client: APIClient(baseURL: "https://api.example.com", boundary: SessionBoundary(tokenStorage: KeychainTokenStorage()))))
        )
        XCTAssertEqual(bundle.filterState.filter, .community)
        XCTAssertNotNil(bundle.bookmarkService)
    }

    // MARK: - Cache-first offline catalog (GRDB `Pose` catalog)

    /// Cold read: one network round trip, and the fetched page lands in the database.
    func testCacheFirstColdReadFetchesOnceAndPersistsCatalogToDatabase() async throws {
        let temp = try TempPoseDatabase()
        defer { temp.cleanUp() }
        let remote = StubPoseRemote()
        remote.communityItems = [
            try stubPose("sunset-1", name: "Sunset Stand", uploadedAt: "2024-03-02T00:00:00Z"),
            try stubPose("warrior-1", name: "Warrior Two", uploadedAt: "2024-03-01T00:00:00Z"),
        ]
        let filterState = PoseFilterState()
        let scheduler = ManualPoseRefreshScheduler()
        let adapter = PoseAPIServiceAdapter(
            remote: remote,
            baseURL: Self.baseURL,
            filterState: filterState,
            cache: PoseCatalogCacheStore(repository: temp.repository, scheduler: scheduler)
        )

        let poses = try await adapter.poses(query: nil)

        XCTAssertEqual(remote.communityCallCount, 1)
        XCTAssertEqual(scheduler.pendingCount, 0, "a cold read is already fresh, so nothing is queued")
        XCTAssertEqual(poses.map(\.id), ["sunset-1", "warrior-1"])
        let stored = try await temp.repository.cached()
        XCTAssertEqual(stored.map(\.poseId), ["sunset-1", "warrior-1"])
        XCTAssertTrue(stored.allSatisfy { $0.ownerAccountId == PoseCatalogBucket.community.rawValue })
        XCTAssertTrue(stored.allSatisfy { $0.status == "published" })
        XCTAssertTrue(stored.allSatisfy { $0.thumbnailPath == "/thumb.jpg" })
    }

    /// Second read in the same session is served from memory: no remote, not even a background
    /// refresh while the entry is fresh.
    func testCacheFirstSecondReadIsMemoryOnly() async throws {
        let temp = try TempPoseDatabase()
        defer { temp.cleanUp() }
        let remote = StubPoseRemote()
        remote.communityItems = [try stubPose("sunset-1", name: "Sunset Stand", uploadedAt: "2024-03-02T00:00:00Z")]
        let scheduler = ManualPoseRefreshScheduler()
        let adapter = PoseAPIServiceAdapter(
            remote: remote,
            baseURL: Self.baseURL,
            filterState: PoseFilterState(),
            cache: PoseCatalogCacheStore(repository: temp.repository, scheduler: scheduler)
        )

        let first = try await adapter.poses(query: nil)
        let second = try await adapter.poses(query: nil)

        XCTAssertEqual(second, first)
        XCTAssertEqual(remote.communityCallCount, 1)
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    /// Relaunch while offline: a brand new service instance answers from the database and never
    /// touches the network on the read path (revalidation is queued behind the answer).
    func testRelaunchOfflineAnswersFromDatabaseWithoutCallingRemote() async throws {
        let temp = try TempPoseDatabase()
        defer { temp.cleanUp() }
        let online = StubPoseRemote()
        online.communityItems = [
            try stubPose("sunset-1", name: "Sunset Stand", uploadedAt: "2024-03-02T00:00:00Z"),
            try stubPose("warrior-1", name: "Warrior Two", uploadedAt: "2024-03-01T00:00:00Z"),
        ]
        let onlineScheduler = ManualPoseRefreshScheduler()
        let onlineAdapter = PoseAPIServiceAdapter(
            remote: online,
            baseURL: Self.baseURL,
            filterState: PoseFilterState(),
            cache: PoseCatalogCacheStore(repository: temp.repository, scheduler: onlineScheduler)
        )
        let onlinePoses = try await onlineAdapter.poses(query: nil)

        let offline = StubPoseRemote()
        offline.communityError = URLError(.notConnectedToInternet)
        let scheduler = ManualPoseRefreshScheduler()
        let offlineAdapter = PoseAPIServiceAdapter(
            remote: offline,
            baseURL: Self.baseURL,
            filterState: PoseFilterState(),
            cache: PoseCatalogCacheStore(repository: temp.repository, scheduler: scheduler)
        )

        let offlinePoses = try await offlineAdapter.poses(query: nil)

        XCTAssertEqual(
            offlinePoses.sorted { $0.id < $1.id },
            onlinePoses.sorted { $0.id < $1.id }
        )
        XCTAssertEqual(online.communityCallCount, 1, "the warm-up session fetched exactly once")
        XCTAssertEqual(onlineScheduler.pendingCount, 0)
        // The stale catalog answer is returned without waiting for the network...
        XCTAssertEqual(offline.communityCallCount, 0, "the catalog answer must not wait on the network")
        XCTAssertEqual(scheduler.pendingCount, 1, "the stale catalog read still queues one revalidation")

        // ...and the queued revalidation is what touches the network.
        await scheduler.runAll()
        XCTAssertEqual(offline.communityCallCount, 1, "background refresh is what calls the remote")
    }

    /// Only relative paths are stored, so a base URL change re-resolves the artwork.
    func testOfflineCatalogReResolvesImageURLAgainstCurrentBaseURL() async throws {
        let temp = try TempPoseDatabase()
        defer { temp.cleanUp() }
        let remote = StubPoseRemote()
        remote.communityItems = [try stubPose("sunset-1", name: "Sunset Stand", uploadedAt: "2024-03-02T00:00:00Z")]
        let onlineAdapter = PoseAPIServiceAdapter(
            remote: remote,
            baseURL: "https://old.example.com",
            filterState: PoseFilterState(),
            cache: PoseCatalogCacheStore(repository: temp.repository, scheduler: ManualPoseRefreshScheduler())
        )
        _ = try await onlineAdapter.poses(query: nil)

        let offlineAdapter = PoseAPIServiceAdapter(
            remote: StubPoseRemote(),
            baseURL: "https://new.example.com",
            filterState: PoseFilterState(),
            cache: PoseCatalogCacheStore(repository: temp.repository, scheduler: ManualPoseRefreshScheduler())
        )

        let poses = try await offlineAdapter.poses(query: nil)

        XCTAssertEqual(poses.count, 1)
        XCTAssertEqual(poses.first?.imageURL?.absoluteString, "https://new.example.com/thumb.jpg")
    }

    /// Search text is part of the cache key and is answered from the catalog while offline.
    func testCommunitySearchIsAnsweredFromCachedCatalogOffline() async throws {
        let temp = try TempPoseDatabase()
        defer { temp.cleanUp() }
        let remote = StubPoseRemote()
        remote.communityItems = [
            try stubPose("soft", name: "Soft Standing", uploadedAt: "2024-03-02T00:00:00Z"),
            try stubPose("hard", name: "Hard Lean", uploadedAt: "2024-03-01T00:00:00Z"),
        ]
        let onlineAdapter = PoseAPIServiceAdapter(
            remote: remote,
            baseURL: Self.baseURL,
            filterState: PoseFilterState(),
            cache: PoseCatalogCacheStore(repository: temp.repository, scheduler: ManualPoseRefreshScheduler())
        )
        _ = try await onlineAdapter.poses(query: nil)

        let offline = StubPoseRemote()
        offline.communityError = URLError(.notConnectedToInternet)
        let offlineScheduler = ManualPoseRefreshScheduler()
        let offlineAdapter = PoseAPIServiceAdapter(
            remote: offline,
            baseURL: Self.baseURL,
            filterState: PoseFilterState(),
            cache: PoseCatalogCacheStore(repository: temp.repository, scheduler: offlineScheduler)
        )

        let matched = try await offlineAdapter.poses(query: "hard")

        XCTAssertEqual(matched.map(\.id), ["hard"])
        XCTAssertEqual(offline.communityCallCount, 0, "the cached search answer must not wait on the network")
        XCTAssertEqual(offlineScheduler.pendingCount, 1, "the stale search answer queues a revalidation")

        await offlineScheduler.runAll()
        XCTAssertEqual(offline.communityCallCount, 1, "the queued background refresh is what calls the remote")
        let afterFailedRefresh = try await offlineAdapter.poses(query: "hard")
        XCTAssertEqual(afterFailedRefresh.map(\.id), ["hard"], "a failed revalidation cannot corrupt the catalog")
    }

    /// All poses / My poses / Community keep their own catalog buckets: a route that was never
    /// fetched must not serve another route's poses.
    func testCatalogBucketsDoNotLeakAcrossFilters() async throws {
        let temp = try TempPoseDatabase()
        defer { temp.cleanUp() }
        let remote = StubPoseRemote()
        remote.communityItems = [try stubPose("community-only", name: "Community Only", uploadedAt: "2024-03-02T00:00:00Z")]
        let onlineAdapter = PoseAPIServiceAdapter(
            remote: remote,
            baseURL: Self.baseURL,
            filterState: PoseFilterState(),
            cache: PoseCatalogCacheStore(repository: temp.repository, scheduler: ManualPoseRefreshScheduler())
        )
        _ = try await onlineAdapter.poses(query: nil)

        let offline = StubPoseRemote()
        offline.communityError = URLError(.notConnectedToInternet)
        offline.savedError = URLError(.notConnectedToInternet)
        let savedFilter = PoseFilterState()
        savedFilter.filter = .saved
        let offlineScheduler = ManualPoseRefreshScheduler()
        let offlineAdapter = PoseAPIServiceAdapter(
            remote: offline,
            baseURL: Self.baseURL,
            filterState: savedFilter,
            cache: PoseCatalogCacheStore(repository: temp.repository, scheduler: offlineScheduler)
        )

        do {
            _ = try await offlineAdapter.poses(query: nil)
            XCTFail("expected a cold miss for a saved feed nobody fetched")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }
        XCTAssertEqual(offlineScheduler.pendingCount, 0, "a cold miss has nothing cached to revalidate")
    }

    /// A save/unsave is reflected by the catalog without a refetch, and the saved feed stays
    /// reachable offline.
    func testBookmarkToggleUpdatesCatalogCacheWithoutRefetching() async throws {
        let temp = try TempPoseDatabase()
        defer { temp.cleanUp() }
        let remote = StubPoseRemote()
        remote.communityItems = [
            try stubPose("shared", name: "Shared Pose", uploadedAt: "2024-03-02T00:00:00Z"),
            try stubPose("other", name: "Other Pose", uploadedAt: "2024-03-01T00:00:00Z"),
        ]
        remote.savedItems = remote.communityItems
        let filterState = PoseFilterState()
        let cache = PoseCatalogCacheStore(repository: temp.repository, scheduler: ManualPoseRefreshScheduler())
        let adapter = PoseAPIServiceAdapter(
            remote: remote,
            baseURL: Self.baseURL,
            filterState: filterState,
            cache: cache
        )
        let bookmarks = PoseCachingBookmarkService(base: NoopBookmarkService(), cache: cache)

        _ = try await adapter.poses(query: nil)
        filterState.filter = .saved
        let initialSaved = try await adapter.poses(query: nil)
        XCTAssertEqual(initialSaved.map(\.id).sorted(), ["other", "shared"])
        XCTAssertTrue(initialSaved.allSatisfy(\.isSaved))
        XCTAssertEqual(remote.savedCallCount, 1)

        try await bookmarks.unsavePose(poseId: "shared")
        let afterUnsave = try await adapter.poses(query: nil)
        XCTAssertEqual(afterUnsave.map(\.id), ["other"])
        XCTAssertTrue(afterUnsave.allSatisfy(\.isSaved))
        XCTAssertEqual(remote.savedCallCount, 1, "an unsave must not need another fetch")

        try await bookmarks.savePose(poseId: "shared")
        let afterSave = try await adapter.poses(query: nil)
        XCTAssertEqual(afterSave.map(\.id).sorted(), ["other", "shared"])
        XCTAssertEqual(remote.savedCallCount, 1, "a save must not need another fetch")
    }

    /// Measured cache-first claim: with the network unavailable the catalog hit answers in a
    /// fraction of the time a cold (network-bound) read needs.
    func testOfflineCatalogHitIsFasterThanNetworkMiss() async throws {
        let temp = try TempPoseDatabase()
        defer { temp.cleanUp() }
        let remote = StubPoseRemote()
        remote.communityItems = [try stubPose("sunset-1", name: "Sunset Stand", uploadedAt: "2024-03-02T00:00:00Z")]
        let onlineAdapter = PoseAPIServiceAdapter(
            remote: remote,
            baseURL: Self.baseURL,
            filterState: PoseFilterState(),
            cache: PoseCatalogCacheStore(repository: temp.repository, scheduler: ManualPoseRefreshScheduler())
        )
        _ = try await onlineAdapter.poses(query: nil)

        let hitScheduler = ManualPoseRefreshScheduler()
        let offlineAdapter = PoseAPIServiceAdapter(
            remote: SlowOfflinePoseRemote(delay: 0.3),
            baseURL: Self.baseURL,
            filterState: PoseFilterState(),
            cache: PoseCatalogCacheStore(repository: temp.repository, scheduler: hitScheduler)
        )

        // Nothing saved was ever cached, so this read is a cold miss and waits for the network.
        let savedFilter = PoseFilterState()
        savedFilter.filter = .saved
        let missScheduler = ManualPoseRefreshScheduler()
        let missAdapter = PoseAPIServiceAdapter(
            remote: SlowOfflinePoseRemote(delay: 0.3),
            baseURL: Self.baseURL,
            filterState: savedFilter,
            cache: PoseCatalogCacheStore(repository: temp.repository, scheduler: missScheduler)
        )
        let missStart = Date()
        do {
            _ = try await missAdapter.poses(query: nil)
            XCTFail("expected the offline remote to fail")
        } catch {}
        let miss = Date().timeIntervalSince(missStart)

        let hitStart = Date()
        let hitPoses = try await offlineAdapter.poses(query: nil)
        let hit = Date().timeIntervalSince(hitStart)

        print("POSE CACHE TIMING: cold/offline miss = \(miss)s, catalog hit = \(hit)s")
        XCTAssertEqual(hitPoses.map(\.id), ["sunset-1"])
        XCTAssertGreaterThan(miss, 0.25)
        XCTAssertLessThan(hit, 0.1)
        XCTAssertEqual(missScheduler.pendingCount, 0, "the cold miss never reached the catalog path")
        XCTAssertEqual(hitScheduler.pendingCount, 1, "the catalog hit queues its own revalidation")
    }

    private static let baseURL = "https://api.example.com"

    private static func decodePose(_ json: String) throws -> CommunityPose {
        try JSONDecoder().decode(CommunityPose.self, from: Data(json.utf8))
    }
}

private func stubPose(
    _ id: String,
    name: String,
    uploadedAt: String,
    thumbnail: String = "/thumb.jpg"
) throws -> CommunityPose {
    try JSONDecoder().decode(CommunityPose.self, from: Data("""
    {"poseId":"\(id)","name":"\(name)","skeletonUrl":"/skeleton.png","thumbnailUrl":"\(thumbnail)","difficulty":"Easy","tags":["standing"],"description":"Face the light","bodyParts":["arms"],"status":"published","uploadedAt":"\(uploadedAt)"}
    """.utf8))
}

/// Drives the app database used by one cache-first test.
private final class TempPoseDatabase {
    let root: URL
    let database: AppDatabase

    var repository: PoseRepository { PoseRepository(database: database) }

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pose-cache-\(UUID().uuidString)", isDirectory: true)
        database = try AppDatabase(
            location: AppDatabaseLocation(url: root.appendingPathComponent("aipose.db"), kind: .freshInstall)
        )
    }

    func cleanUp() {
        // Close the pool before the files disappear, otherwise SQLite reports the WAL vnode as
        // "unlinked while in use" (cache stores still hold `PoseRepository` references here).
        try? database.pool.close()
        try? FileManager.default.removeItem(at: root)
    }
}

/// Collects stale-while-revalidate work so a test can assert exactly when the network is touched.
private final class ManualPoseRefreshScheduler: PoseRefreshScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [@Sendable () async -> Void] = []

    var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return pending.count
    }

    func schedule(_ operation: @escaping @Sendable () async -> Void) {
        lock.lock()
        pending.append(operation)
        lock.unlock()
    }

    func runAll() async {
        while true {
            guard let next = nextPending() else { return }
            await next()
        }
    }

    private func nextPending() -> (@Sendable () async -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        return pending.isEmpty ? nil : pending.removeFirst()
    }
}

private struct NoopBookmarkService: PoseBookmarkServing {
    func savePose(poseId: String) async throws {}
    func unsavePose(poseId: String) async throws {}
}

/// Unreachable network that takes its time, so a cold read is measurably slower than a catalog hit.
private struct SlowOfflinePoseRemote: PoseRemoteFetching {
    let delay: TimeInterval

    func fetchCommunity(page: Int, limit: Int, query: String?) async throws -> [CommunityPose] {
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        throw URLError(.timedOut)
    }

    func fetchSaved(page: Int, limit: Int) async throws -> [CommunityPose] {
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        throw URLError(.timedOut)
    }
}

private let sampleNativePose = NativePose(
    id: "standing-1",
    name: "Soft Standing",
    category: "Standing",
    imageURL: nil,
    instructions: ["Relax"],
    isSaved: true
)

private extension NativePose {
    func withSaved(_ saved: Bool) -> NativePose {
        NativePose(id: id, name: name, category: category, imageURL: imageURL, instructions: instructions, isSaved: saved)
    }
}

private final class StubPoseRemote: PoseRemoteFetching, @unchecked Sendable {
    var communityItems: [CommunityPose] = []
    var savedItems: [CommunityPose] = []
    var communityError: Error?
    var savedError: Error?
    var communityCallCount = 0
    var savedCallCount = 0
    var lastCommunityQuery: String?

    func fetchCommunity(page: Int, limit: Int, query: String?) async throws -> [CommunityPose] {
        communityCallCount += 1
        lastCommunityQuery = query
        if let communityError { throw communityError }
        return communityItems
    }

    func fetchSaved(page: Int, limit: Int) async throws -> [CommunityPose] {
        savedCallCount += 1
        if let savedError { throw savedError }
        return savedItems
    }
}

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

/// Account-scoped catalog behaviour: the Saved collection belongs to one Account, so neither the
/// offline catalog nor a stale in-memory entry may answer for a guest or for another Account
/// (FEAT-013 sign-in gate, FEAT-014 FR-005).
final class PoseAccountScopeTests: XCTestCase {
    private static let baseURL = "https://api.example.com"

    /// A signed-in read seeds the catalog; a signed-out `.saved` read must hit the network instead
    /// of replaying the previous Account's rows from memory or the database.
    func testSavedRouteIsNotAnsweredFromTheCatalogWithoutASession() async throws {
        let temp = try TempPoseDatabase()
        defer { temp.cleanUp() }
        let remote = StubPoseRemote()
        remote.savedItems = [try savedPose("mine-1", name: "My Pose")]
        let scheduler = ManualPoseRefreshScheduler()
        let cache = PoseCatalogCacheStore(repository: temp.repository, scheduler: scheduler)

        let signedIn = PoseAPIServiceAdapter(
            remote: remote,
            baseURL: Self.baseURL,
            filterState: savedFilterState(),
            cache: cache,
            hasSession: { true }
        )
        let seeded = try await signedIn.poses(query: nil)
        XCTAssertEqual(seeded.map(\.id), ["mine-1"])
        XCTAssertEqual(remote.savedCallCount, 1)

        let signedOut = PoseAPIServiceAdapter(
            remote: remote,
            baseURL: Self.baseURL,
            filterState: savedFilterState(),
            cache: cache,
            hasSession: { false }
        )
        remote.savedError = PoseAPIError(code: "401", message: "Unauthorized")
        do {
            _ = try await signedOut.poses(query: nil)
            XCTFail("A gated route must not resolve without a session")
        } catch {
            // expected: the 401 propagates instead of a cached answer
        }
        XCTAssertEqual(remote.savedCallCount, 2, "A guest read must reach the network, never the cache")
        XCTAssertEqual(scheduler.pendingCount, 0, "No stale-while-revalidate may run for a gated route")
    }

    /// A seeded in-memory entry must not leak either: the same adapter flips to signed-out.
    func testSavedRouteStopsUsingItsMemoryEntryAfterTheSessionEnds() async throws {
        let temp = try TempPoseDatabase()
        defer { temp.cleanUp() }
        let remote = StubPoseRemote()
        remote.savedItems = [try savedPose("mine-2", name: "My Pose")]
        let signedIn = SessionFlag()
        let adapter = PoseAPIServiceAdapter(
            remote: remote,
            baseURL: Self.baseURL,
            filterState: savedFilterState(),
            cache: PoseCatalogCacheStore(repository: temp.repository, scheduler: ManualPoseRefreshScheduler()),
            hasSession: { signedIn.value }
        )

        _ = try await adapter.poses(query: nil)
        signedIn.value = false
        remote.savedError = PoseAPIError(code: "401", message: "Unauthorized")

        do {
            _ = try await adapter.poses(query: nil)
            XCTFail("A gated route must not resolve without a session")
        } catch {
            // expected
        }
        XCTAssertEqual(remote.savedCallCount, 2)
    }

    /// The community feed is not account-scoped, so it keeps answering offline for a guest.
    func testCommunityRouteStillAnswersFromTheCatalogWithoutASession() async throws {
        let temp = try TempPoseDatabase()
        defer { temp.cleanUp() }
        let remote = StubPoseRemote()
        remote.communityItems = [try stubPose("sunset-1", name: "Sunset Stand", uploadedAt: "2024-03-02T00:00:00Z")]
        let adapter = PoseAPIServiceAdapter(
            remote: remote,
            baseURL: Self.baseURL,
            filterState: PoseFilterState(),
            cache: PoseCatalogCacheStore(repository: temp.repository, scheduler: ManualPoseRefreshScheduler()),
            hasSession: { false }
        )

        _ = try await adapter.poses(query: nil)
        let offline = try await adapter.poses(query: nil)

        XCTAssertEqual(offline.map(\.id), ["sunset-1"])
        XCTAssertEqual(remote.communityCallCount, 1, "The community feed is still served from the catalog")
    }

    /// Sign-out cleanup: saved-only rows go, rows that also came from the community feed keep their
    /// feed entry with the saved flag demoted, and the saved-sensitive memory entries are dropped.
    func testClearSavedStateRemovesAccountScopedRowsOnly() async throws {
        let temp = try TempPoseDatabase()
        defer { temp.cleanUp() }
        let remote = StubPoseRemote()
        remote.communityItems = [try stubPose("shared-1", name: "Shared", uploadedAt: "2024-03-02T00:00:00Z")]
        remote.savedItems = [
            try savedPose("shared-1", name: "Shared"),
            try savedPose("mine-1", name: "My Pose"),
        ]
        let cache = PoseCatalogCacheStore(repository: temp.repository, scheduler: ManualPoseRefreshScheduler())
        let filterState = PoseFilterState()

        // Community first (so `shared-1` is known to belong to the community feed), then saved.
        let communityAdapter = PoseAPIServiceAdapter(
            remote: remote,
            baseURL: Self.baseURL,
            filterState: filterState,
            cache: cache,
            hasSession: { true }
        )
        _ = try await communityAdapter.poses(query: nil)
        filterState.filter = .saved
        _ = try await communityAdapter.poses(query: nil)

        let before = try await temp.repository.cached()
        XCTAssertEqual(before.filter { $0.status == PoseCatalogMapping.savedStatus }.count, 2, "both rows are saved")

        await cache.clearSavedState()

        let after = try await temp.repository.cached()
        XCTAssertEqual(after.map(\.poseId), ["shared-1"], "the saved-only row is deleted")
        XCTAssertEqual(after.first?.status, PoseCatalogMapping.unsavedStatus, "the shared row keeps its community entry")
        XCTAssertEqual(after.first?.ownerAccountId, PoseCatalogBucket.community.rawValue)
    }

    // MARK: - helpers

    private func savedFilterState() -> PoseFilterState {
        let filterState = PoseFilterState()
        filterState.filter = .saved
        return filterState
    }

    private func savedPose(_ id: String, name: String) throws -> CommunityPose {
        try JSONDecoder().decode(CommunityPose.self, from: Data("""
        {"poseId":"\(id)","name":"\(name)","skeletonUrl":"/s.png","thumbnailUrl":"/t.jpg","status":"published"}
        """.utf8))
    }
}

/// Mutable session flag for the adapter's `hasSession` probe.
private final class SessionFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = true

    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}
