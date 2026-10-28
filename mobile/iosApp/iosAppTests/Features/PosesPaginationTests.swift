import XCTest
@testable import iosApp

// MARK: - fixtures

private func pagedPose(_ id: String, isSaved: Bool = false) -> NativePose {
    NativePose(
        id: id,
        name: "Pose \(id)",
        category: "Standing",
        imageURL: URL(string: "https://example.com/\(id).jpg"),
        instructions: ["Step one"],
        isSaved: isSaved
    )
}

@MainActor private func pagedPoseIDs(_ model: PosesViewModel) -> [String] {
    guard case .loaded(let poses) = model.state else { return [] }
    return poses.map(\.id)
}

private func libraryPose(_ id: String, uploadedAt: String = "2024-03-02T00:00:00Z") throws -> CommunityPose {
    try JSONDecoder().decode(CommunityPose.self, from: Data("""
    {"poseId":"\(id)","name":"Pose \(id)","skeletonUrl":"/s.png","thumbnailUrl":"/t.jpg",
     "status":"published","uploadedAt":"\(uploadedAt)"}
    """.utf8))
}

private func libraryPoses(_ count: Int) throws -> [CommunityPose] {
    try (1...count).map { try libraryPose("lib-\($0)") }
}

private let pagedCredentialsA = SessionCredentials(accessToken: "access-a", refreshToken: "refresh-a")
private let pagedCredentialsB = SessionCredentials(accessToken: "access-b", refreshToken: "refresh-b")

/// Serves canned pages per page number, records every ask and can hold one page open, so a test can
/// assert the request sequence (the part that actually breaks in paging) instead of only the final
/// array.
private final class PagedPoseService: PoseServing, @unchecked Sendable {
    /// Page number → answer. A missing page answers "end of list".
    var pages: [Int: PosePage] = [:]
    var pageErrors: [Int: Error] = [:]
    /// Pages whose response the test holds open until it calls `release(page:)`.
    var heldPages: Set<Int> = []

    private let lock = NSLock()
    private var asks: [Int] = []
    private var holds: [Int: CheckedContinuation<Void, Never>] = [:]
    private var startWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    var requestedPages: [Int] { lock.withLock { asks } }
    var requestCount: Int { lock.withLock { asks.count } }

    func poses(query: String?) async throws -> [NativePose] {
        try await posesPage(query: query, page: 1).poses
    }

    func posesPage(query: String?, page: Int) async throws -> PosePage {
        let waiters: [CheckedContinuation<Void, Never>] = lock.withLock {
            asks.append(page)
            let matching = startWaiters.filter { $0.0 == page }.map { $0.1 }
            startWaiters.removeAll { $0.0 == page }
            return matching
        }
        waiters.forEach { $0.resume() }

        if heldPages.contains(page) {
            await withCheckedContinuation { (pending: CheckedContinuation<Void, Never>) in
                lock.withLock { holds[page] = pending }
            }
        }
        if let error = pageErrors[page] { throw error }
        return pages[page] ?? .end
    }

    func pose(id: String) async throws -> NativePose {
        for page in pages.values {
            if let match = page.poses.first(where: { $0.id == id }) { return match }
        }
        throw PoseAdapterError.poseNotFound(id)
    }

    // MARK: test controls

    func waitUntilRequested(_ page: Int, timeout: TimeInterval = 5) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if lock.withLock({ asks.contains(page) }) { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTFail("page \(page) was never requested (asked for \(requestedPages))")
    }

    func release(page: Int) {
        let pending: CheckedContinuation<Void, Never>? = lock.withLock { holds.removeValue(forKey: page) }
        pending?.resume()
    }
}

/// A fixed library sliced by page with the server's total — the shape the real endpoint has.
private final class LibraryPoseRemote: PoseRemoteFetching, @unchecked Sendable {
    private let poses: [CommunityPose]
    private let lock = NSLock()
    private var communityAsks: [(page: Int, query: String?)] = []
    private var savedAsks: [Int] = []

    var failure: Error?
    var savedItems: [CommunityPose] = []
    var savedTotal = 0

    init(poses: [CommunityPose]) {
        self.poses = poses
    }

    var communityPageAsks: [Int] { lock.withLock { communityAsks.map(\.page) } }
    var lastCommunityQuery: String? { lock.withLock { communityAsks.last?.query } }
    var communityCallCount: Int { lock.withLock { communityAsks.count } }
    var savedCallCount: Int { lock.withLock { savedAsks.count } }

    func fetchCommunity(page: Int, limit: Int, query: String?) async throws -> PoseRemotePage {
        lock.withLock { communityAsks.append((page, query)) }
        if let failure { throw failure }
        let start = max(0, (page - 1) * limit)
        let slice = start < poses.count ? Array(poses[start..<min(poses.count, start + limit)]) : []
        return PoseRemotePage(poses: slice, total: poses.count)
    }

    func fetchSaved(page: Int, limit: Int) async throws -> PoseRemotePage {
        lock.withLock { savedAsks.append(page) }
        return PoseRemotePage(poses: savedItems, total: savedTotal)
    }
}

/// One catalog database per test, removed afterwards.
private final class PaginationTempDatabase {
    let root: URL
    let database: AppDatabase

    var repository: PoseRepository { PoseRepository(database: database) }

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pose-paging-\(UUID().uuidString)", isDirectory: true)
        database = try AppDatabase(
            location: AppDatabaseLocation(url: root.appendingPathComponent("aipose.db"), kind: .freshInstall)
        )
    }

    func cleanUp() {
        try? database.pool.close()
        try? FileManager.default.removeItem(at: root)
    }
}

/// Collects stale-while-revalidate work so a test drives it instead of racing a detached task.
private final class PaginationRefreshScheduler: PoseRefreshScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [@Sendable () async -> Void] = []

    var pendingCount: Int { lock.withLock { pending.count } }

    func schedule(_ operation: @escaping @Sendable () async -> Void) {
        lock.withLock { pending.append(operation) }
    }

    func runAll() async {
        while true {
            let next: (@Sendable () async -> Void)? = lock.withLock {
                pending.isEmpty ? nil : pending.removeFirst()
            }
            guard let next else { return }
            await next()
        }
    }
}

private final class PaginationTokenStorage: TokenStoring, @unchecked Sendable {
    private var credentials: SessionCredentials?

    init(credentials: SessionCredentials? = pagedCredentialsA) {
        self.credentials = credentials
    }

    func saveCredentials(_ credentials: SessionCredentials) { self.credentials = credentials }
    func loadCredentials() -> SessionCredentials? { credentials }
    func clearCredentials() { credentials = nil }
}

// MARK: - view-model paging

@MainActor
final class PosesPaginationTests: XCTestCase {
    private func page(_ ids: [Int], hasMore: Bool, prefix: String = "p") -> PosePage {
        PosePage(poses: ids.map { pagedPose("\(prefix)\($0)") }, hasMore: hasMore)
    }

    private func ids(_ page: Int, _ count: Int) -> [String] {
        let start = (page - 1) * count + 1
        return (start...(start + count - 1)).map { "p\($0)" }
    }

    func testNextPageIsAppendedWithoutLosingOrRepeatingRows() async {
        let service = PagedPoseService()
        service.pages = [
            1: page(Array(1...20), hasMore: true),
            2: page(Array(21...40), hasMore: true),
            3: page(Array(41...45), hasMore: false),
        ]
        let model = PosesViewModel(service: service)

        await model.load()
        XCTAssertEqual(pagedPoseIDs(model), ids(1, 20))
        XCTAssertTrue(model.paging.hasMore)
        XCTAssertEqual(model.paging.nextPage, 2)

        await model.loadMore()
        XCTAssertEqual(pagedPoseIDs(model), ids(1, 20) + ids(2, 20))
        XCTAssertEqual(model.paging.nextPage, 3)

        await model.loadMore()
        XCTAssertEqual(pagedPoseIDs(model).count, 45)
        XCTAssertEqual(model.paging.nextPage, 4)
        XCTAssertFalse(model.paging.hasMore, "the last page ends the list")
        XCTAssertNil(model.paging.error)
    }

    func testPoseRepeatedOnTwoPagesIsShownOnce() async {
        let service = PagedPoseService()
        service.pages = [
            1: PosePage(poses: [pagedPose("a"), pagedPose("b")], hasMore: true),
            2: PosePage(poses: [pagedPose("b"), pagedPose("c")], hasMore: false),
        ]
        let model = PosesViewModel(service: service)

        await model.load()
        await model.loadMore()

        XCTAssertEqual(pagedPoseIDs(model), ["a", "b", "c"], "a row that appears on two pages is drawn once")
    }

    func testLastPageStopsAskingTheNetwork() async {
        let service = PagedPoseService()
        service.pages = [
            1: PosePage(poses: [pagedPose("a")], hasMore: true),
            2: PosePage(poses: [pagedPose("b")], hasMore: false),
        ]
        let model = PosesViewModel(service: service)

        await model.load()
        await model.loadMore()
        let asked = service.requestCount
        await model.loadMore()

        XCTAssertEqual(service.requestCount, asked, "an ended list must not request page 3")
        XCTAssertEqual(pagedPoseIDs(model), ["a", "b"])
    }

    func testFailedPageKeepsLoadedRowsAndRetryLoadsTheSamePage() async {
        let service = PagedPoseService()
        service.pages = [
            1: page(Array(1...20), hasMore: true),
            2: page(Array(21...40), hasMore: false),
        ]
        service.pageErrors[2] = URLError(.notConnectedToInternet)
        let model = PosesViewModel(service: service)

        await model.load()
        await model.loadMore()

        XCTAssertEqual(pagedPoseIDs(model), ids(1, 20), "a failed page must not cost the loaded rows")
        XCTAssertNotNil(model.paging.error)
        XCTAssertTrue(model.paging.hasMore, "the page that failed is still owed")
        XCTAssertEqual(model.paging.nextPage, 2, "the cursor stays on the failed page")
        XCTAssertFalse(model.paging.isLoading)

        service.pageErrors[2] = nil
        await model.loadMoreResults()

        XCTAssertNil(model.paging.error)
        XCTAssertEqual(pagedPoseIDs(model).count, 40, "the retry appends the page that failed")
        XCTAssertFalse(model.paging.hasMore)
    }

    func testRefreshStartsAgainFromPageOne() async {
        let service = PagedPoseService()
        service.pages = [
            1: page(Array(1...20), hasMore: true),
            2: page(Array(21...40), hasMore: false),
        ]
        let model = PosesViewModel(service: service)
        await model.load()
        await model.loadMore()
        XCTAssertEqual(pagedPoseIDs(model).count, 40)

        service.pages[1] = PosePage(poses: (1...20).map { pagedPose("fresh\($0)") }, hasMore: true)
        await model.load()

        XCTAssertEqual(Array(pagedPoseIDs(model).prefix(3)), ["fresh1", "fresh2", "fresh3"])
        XCTAssertEqual(pagedPoseIDs(model).count, 20, "a refresh replaces the list instead of appending to it")
        XCTAssertEqual(model.paging.nextPage, 2, "the cursor restarts at page 2")
        XCTAssertTrue(model.paging.hasMore)
    }

    func testQueryChangeDiscardsAPageThatArrivesLate() async {
        let service = PagedPoseService()
        service.pages = [
            1: PosePage(poses: [pagedPose("a"), pagedPose("b")], hasMore: true),
            2: PosePage(poses: [pagedPose("stale")], hasMore: false),
        ]
        service.heldPages = [2]
        let model = PosesViewModel(service: service)
        await model.load()

        let paginating = Task { await model.loadMore() }
        await service.waitUntilRequested(2)

        // The user types: the debounced load replaces the list before page 2 answers.
        model.query = "other"
        await model.load()

        service.release(page: 2)
        await paginating.value

        XCTAssertEqual(pagedPoseIDs(model), ["a", "b"], "a page fetched for the previous search must be dropped")
        XCTAssertEqual(model.paging.nextPage, 2)
    }

    func testTwoTriggersWhileLoadingSendOneRequest() async {
        let service = PagedPoseService()
        service.pages = [
            1: page(Array(1...20), hasMore: true),
            2: page(Array(21...40), hasMore: false),
        ]
        service.heldPages = [2]
        let model = PosesViewModel(service: service)
        await model.load()

        let first = Task { await model.loadMore() }
        await service.waitUntilRequested(2)
        let second = Task { await model.loadMore() }
        await Task.yield()

        service.release(page: 2)
        await first.value
        await second.value

        XCTAssertEqual(service.requestedPages, [1, 2], "the second trigger joins the page already in flight")
        XCTAssertEqual(pagedPoseIDs(model).count, 40)
    }

    func testSessionChangeDropsAPageFromThePreviousAccount() async {
        let boundary = SessionBoundary(tokenStorage: PaginationTokenStorage())
        let service = PagedPoseService()
        service.pages = [
            1: PosePage(poses: [pagedPose("a"), pagedPose("b")], hasMore: true),
            2: PosePage(poses: [pagedPose("a-account-only")], hasMore: true),
        ]
        service.heldPages = [2]
        let model = PosesViewModel(service: service, boundary: boundary)
        await waitForSessionSubscription(boundary)
        model.filter = .community
        await model.load()

        let paginating = Task { await model.loadMore() }
        await service.waitUntilRequested(2)

        await boundary.signOut()
        await boundary.saveCredentials(pagedCredentialsB)

        service.release(page: 2)
        await paginating.value

        XCTAssertFalse(
            pagedPoseIDs(model).contains("a-account-only"),
            "a page requested by the previous session must never reach the next one"
        )
        XCTAssertEqual(model.paging.nextPage, 2, "the next Account starts its own paging")
        XCTAssertFalse(model.paging.isLoading)
    }

    func testEmptyFilteredFirstPageKeepsPagingUntilAMatchIsFound() async {
        let service = PagedPoseService()
        service.pages = [
            1: PosePage(poses: [], hasMore: true),
            2: PosePage(poses: [pagedPose("match")], hasMore: false),
        ]
        let model = PosesViewModel(service: service)

        await model.load()

        XCTAssertEqual(pagedPoseIDs(model), ["match"], "an empty page is not the end of a filtered list")
        XCTAssertFalse(model.paging.hasMore)
    }

    func testSpentAutoFetchBudgetOffersLoadMoreInsteadOfADeadEnd() async {
        let service = PagedPoseService()
        service.pages = [
            1: PosePage(poses: [], hasMore: true),
            2: PosePage(poses: [], hasMore: true),
            3: PosePage(poses: [], hasMore: true),
            4: PosePage(poses: [], hasMore: true),
            5: PosePage(poses: [pagedPose("match")], hasMore: false),
        ]
        let model = PosesViewModel(service: service)

        await model.load()

        XCTAssertEqual(service.requestedPages, [1, 2, 3, 4], "three automatic pages, then stop")
        XCTAssertEqual(model.paging.remainingAutoFetches, 0)
        XCTAssertTrue(model.paging.hasMore)
        if case .empty = model.state {} else { XCTFail("Expected the empty state until page 5, got \(model.state)") }

        await model.loadMoreResults()

        XCTAssertEqual(service.requestedPages, [1, 2, 3, 4, 5])
        XCTAssertEqual(pagedPoseIDs(model), ["match"])
        XCTAssertFalse(model.paging.hasMore)
        XCTAssertEqual(model.paging.remainingAutoFetches, PosesViewModel.Paging.autoFetchBudget)
    }

    func testEveryPageEmptyEndsEmptyWithNoMore() async {
        let service = PagedPoseService()
        service.pages = [
            1: PosePage(poses: [], hasMore: true),
            2: PosePage(poses: [], hasMore: false),
        ]
        let model = PosesViewModel(service: service)

        await model.load()

        if case .empty = model.state {} else { XCTFail("Expected a final empty state, got \(model.state)") }
        XCTAssertFalse(model.paging.hasMore)
        XCTAssertNil(model.paging.error)
    }

    func testFilterChangeStartsPagingOver() async {
        let service = PagedPoseService()
        service.pages = [
            1: page(Array(1...20), hasMore: true),
            2: page(Array(21...40), hasMore: false),
        ]
        let model = PosesViewModel(service: service)
        await model.load()
        await model.loadMore()
        XCTAssertEqual(pagedPoseIDs(model).count, 40)

        model.filter = .saved
        await model.load()

        XCTAssertEqual(model.paging.nextPage, 2, "a new filter is a new list, not a continuation")
        XCTAssertFalse(model.paging.isLoading)
    }

    func testPageTwoPoseIsUsableWithoutACatalogRow() async {
        let service = PagedPoseService()
        let late = pagedPose("page-two", isSaved: true)
        service.pages = [
            1: PosePage(poses: [pagedPose("a")], hasMore: true),
            2: PosePage(poses: [late], hasMore: false),
        ]
        let model = PosesViewModel(service: service)

        await model.load()
        await model.loadMore()

        XCTAssertEqual(pagedPoseIDs(model), ["a", "page-two"])
        // The detail screen is handed the value from this list, so it needs no database row.
        XCTAssertEqual(model.savedState(for: late), true)
    }

    // MARK: helpers

    private func waitForSessionSubscription(_ boundary: SessionBoundary, timeout: TimeInterval = 5) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await boundary.subscriberCountForTests() > 0 { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTFail("the model never subscribed to the session boundary")
    }
}

// MARK: - adapter paging (server total, page-1-only catalog)

final class PoseAdapterPaginationTests: XCTestCase {
    private static let baseURL = "https://api.example.com"

    private func communityAdapter(_ remote: LibraryPoseRemote, cache: PoseCatalogCacheStore? = nil) -> PoseAPIServiceAdapter {
        let filterState = PoseFilterState()
        filterState.filter = .community
        return PoseAPIServiceAdapter(remote: remote, baseURL: Self.baseURL, filterState: filterState, cache: cache)
    }

    /// `hasMore` comes from the server total, never from the number of rows the page happened to
    /// return: an exactly-full page is not the last page.
    func testHasMoreFollowsTheServerTotal() async throws {
        let empty = communityAdapter(LibraryPoseRemote(poses: []))
        let emptyPage = try await empty.posesPage(query: nil, page: 1)
        XCTAssertEqual(emptyPage.poses.count, 0)
        XCTAssertFalse(emptyPage.hasMore)

        let exactlyFull = communityAdapter(LibraryPoseRemote(poses: try libraryPoses(20)))
        let fullPage = try await exactlyFull.posesPage(query: nil, page: 1)
        XCTAssertEqual(fullPage.poses.count, 20)
        XCTAssertFalse(fullPage.hasMore, "20 of 20 rows is the end even though the page is full")

        let oneMore = communityAdapter(LibraryPoseRemote(poses: try libraryPoses(21)))
        let firstPage = try await oneMore.posesPage(query: nil, page: 1)
        XCTAssertTrue(firstPage.hasMore)
        let secondPage = try await oneMore.posesPage(query: nil, page: 2)
        XCTAssertEqual(secondPage.poses.count, 1)
        XCTAssertFalse(secondPage.hasMore, "21 of 21 rows is the end of page 2")
    }

    func testThreePageLibraryPagesEndToEnd() async throws {
        let remote = LibraryPoseRemote(poses: try libraryPoses(45))
        let adapter = communityAdapter(remote)

        let first = try await adapter.posesPage(query: nil, page: 1)
        let second = try await adapter.posesPage(query: nil, page: 2)
        let third = try await adapter.posesPage(query: nil, page: 3)

        XCTAssertEqual([first.poses.count, second.poses.count, third.poses.count], [20, 20, 5])
        XCTAssertEqual([first.hasMore, second.hasMore, third.hasMore], [true, true, false])
        XCTAssertEqual(remote.communityPageAsks, [1, 2, 3])
        let ids = (first.poses + second.poses + third.poses).map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "no row is returned by two pages")
    }

    func testSecondPageWritesNothingToTheCatalog() async throws {
        let temp = try PaginationTempDatabase()
        defer { temp.cleanUp() }
        let scheduler = PaginationRefreshScheduler()
        let remote = LibraryPoseRemote(poses: try libraryPoses(45))
        let cache = PoseCatalogCacheStore(repository: temp.repository, scheduler: scheduler)
        let adapter = communityAdapter(remote, cache: cache)

        let first = try await adapter.posesPage(query: nil, page: 1)
        XCTAssertEqual(first.poses.count, 20)
        let storedAfterFirst = try await temp.repository.cached().count
        XCTAssertEqual(storedAfterFirst, 20)
        let callsAfterFirst = remote.communityCallCount

        _ = try await adapter.posesPage(query: nil, page: 2)

        let storedAfterSecond = try await temp.repository.cached().count
        XCTAssertEqual(storedAfterSecond, storedAfterFirst, "page 2 is network-only: it writes no catalog rows")

        // Still page 1 in memory: page 2 neither replaced nor extended the cached answer.
        let reread = try await adapter.poses(query: nil)
        XCTAssertEqual(reread.count, 20)
        XCTAssertEqual(remote.communityCallCount, callsAfterFirst + 1, "the only network call was page 2 itself")
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    func testSecondPageFailsOfflineWhileTheFirstPageStillServes() async throws {
        let temp = try PaginationTempDatabase()
        defer { temp.cleanUp() }
        let remote = LibraryPoseRemote(poses: try libraryPoses(45))
        let cache = PoseCatalogCacheStore(repository: temp.repository, scheduler: PaginationRefreshScheduler())
        let adapter = communityAdapter(remote, cache: cache)
        _ = try await adapter.posesPage(query: nil, page: 1)

        remote.failure = URLError(.notConnectedToInternet)
        do {
            _ = try await adapter.posesPage(query: nil, page: 2)
            XCTFail("a page beyond the cached one has no offline answer, so it must fail loudly")
        } catch {
            // expected: the screen keeps its rows and offers a retry
        }

        let firstPage = try await adapter.posesPage(query: nil, page: 1)
        XCTAssertEqual(firstPage.poses.count, 20, "page 1 is still answered while offline")
    }

    func testAllSourcePagesTheCommunityFeedOnly() async throws {
        let remote = LibraryPoseRemote(poses: try libraryPoses(45))
        remote.savedItems = [try libraryPose("saved-1")]
        remote.savedTotal = 1
        let filterState = PoseFilterState()
        filterState.filter = .all
        let adapter = PoseAPIServiceAdapter(remote: remote, baseURL: Self.baseURL, filterState: filterState)

        _ = try await adapter.posesPage(query: nil, page: 1)
        let savedAfterFirst = remote.savedCallCount
        let communityAfterFirst = remote.communityCallCount
        XCTAssertGreaterThan(savedAfterFirst, 0, "page 1 merges the saved collection")

        let second = try await adapter.posesPage(query: nil, page: 2)

        XCTAssertEqual(remote.savedCallCount, savedAfterFirst, "later pages do not re-merge the saved list")
        XCTAssertEqual(remote.communityCallCount, communityAfterFirst + 1)
        XCTAssertEqual(second.poses.count, 20)
        XCTAssertTrue(second.hasMore)
    }

    func testSearchPagesKeepTheQueryAndThePage() async throws {
        let remote = LibraryPoseRemote(poses: try libraryPoses(45))
        let adapter = communityAdapter(remote)

        _ = try await adapter.posesPage(query: "warrior", page: 2)

        XCTAssertEqual(remote.communityPageAsks, [2])
        XCTAssertEqual(remote.lastCommunityQuery, "warrior")
    }

    /// A saved page can contribute zero matches for the query and still not be the last page.
    func testSavedPageWithoutMatchesStillReportsMore() async throws {
        let remote = LibraryPoseRemote(poses: [])
        remote.savedItems = [try libraryPose("saved-1")]
        remote.savedTotal = 41
        let filterState = PoseFilterState()
        filterState.filter = .saved
        let adapter = PoseAPIServiceAdapter(remote: remote, baseURL: Self.baseURL, filterState: filterState)

        let page = try await adapter.posesPage(query: "zzzz", page: 2)

        XCTAssertEqual(page.poses.count, 0, "the local name filter removes the page's rows")
        XCTAssertTrue(page.hasMore, "the server total, not the local match count, decides hasMore")
    }
}
