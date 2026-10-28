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

private func numberedPoses(_ range: ClosedRange<Int>, isSaved: Bool = false) -> [NativePose] {
    range.map { pagedPose("p\($0)", isSaved: isSaved) }
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

/// An OFFSET-paging server: it serves `library[offset..<offset+limit]` and reports `total`, records
/// every offset it was asked for and can hold one window open. Windows can be "hidden" to emulate
/// the Saved route's local name filter, and the total can be pinned so a stale one can be tested.
private final class PagedPoseService: PoseServing, @unchecked Sendable {
    var library: [NativePose] = []
    /// What the server reports as `total`; defaults to the library count.
    var reportedTotal: Int?
    /// Windows whose rows the caller filters out locally (Saved + query): the rows are consumed, the
    /// answer is empty, and the window is not the end of the list.
    var hiddenWindows: Set<Int> = []
    var offsetErrors: [Int: Error] = [:]
    /// Windows the test holds open until it calls `release(offset:)`.
    var heldOffsets: Set<Int> = []

    private let lock = NSLock()
    private var asks: [Int] = []
    private var holds: [Int: CheckedContinuation<Void, Never>] = [:]
    private var startWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    var requestedOffsets: [Int] { lock.withLock { asks } }
    var requestCount: Int { lock.withLock { asks.count } }
    var total: Int { reportedTotal ?? library.count }

    func poses(query: String?) async throws -> [NativePose] {
        try await posesPage(query: query, offset: 0, limit: PosesViewModel.Paging.pageSize).poses
    }

    func posesPage(query: String?, offset: Int, limit: Int) async throws -> PosePage {
        let waiters: [CheckedContinuation<Void, Never>] = lock.withLock {
            asks.append(offset)
            let matching = startWaiters.filter { $0.0 == offset }.map { $0.1 }
            startWaiters.removeAll { $0.0 == offset }
            return matching
        }
        waiters.forEach { $0.resume() }

        if heldOffsets.contains(offset) {
            await withCheckedContinuation { (pending: CheckedContinuation<Void, Never>) in
                lock.withLock { holds[offset] = pending }
            }
        }
        if let error = offsetErrors[offset] { throw error }

        let start = min(max(0, offset), library.count)
        let window = Array(library[start..<min(library.count, start + limit)])
        return PosePage(
            poses: hiddenWindows.contains(offset) ? [] : window,
            hasMore: offset + window.count < total,
            consumed: window.count
        )
    }

    func pose(id: String) async throws -> NativePose {
        guard let match = library.first(where: { $0.id == id }) else {
            throw PoseAdapterError.poseNotFound(id)
        }
        return match
    }

    // MARK: test controls

    func waitUntilRequested(_ offset: Int, timeout: TimeInterval = 5) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if lock.withLock({ asks.contains(offset) }) { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTFail("offset \(offset) was never requested (asked for \(requestedOffsets))")
    }

    func release(offset: Int) {
        let pending: CheckedContinuation<Void, Never>? = lock.withLock { holds.removeValue(forKey: offset) }
        pending?.resume()
    }
}

/// A fixed library sliced by page/offset with a settable server total — the shape the real endpoints
/// have, including the `page`/`limit` request the client has to translate an offset into.
private final class LibraryPoseRemote: PoseRemoteFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var communityAsks: [(page: Int, query: String?)] = []
    private var savedAsks: [Int] = []

    var communityItems: [CommunityPose]
    var communityTotal: Int?
    var savedItems: [CommunityPose]
    var savedTotal: Int?
    var failure: Error?

    init(community: [CommunityPose] = [], saved: [CommunityPose] = []) {
        communityItems = community
        savedItems = saved
    }

    var communityPageAsks: [Int] { lock.withLock { communityAsks.map(\.page) } }
    var lastCommunityQuery: String? { lock.withLock { communityAsks.last?.query } }
    var communityCallCount: Int { lock.withLock { communityAsks.count } }
    var savedCallCount: Int { lock.withLock { savedAsks.count } }

    func fetchCommunity(page: Int, limit: Int, query: String?) async throws -> PoseRemotePage {
        lock.withLock { communityAsks.append((page, query)) }
        if let failure { throw failure }
        return Self.window(communityItems, page: page, limit: limit, total: communityTotal)
    }

    func fetchSaved(page: Int, limit: Int) async throws -> PoseRemotePage {
        lock.withLock { savedAsks.append(page) }
        if let failure { throw failure }
        return Self.window(savedItems, page: page, limit: limit, total: savedTotal)
    }

    private static func window(
        _ items: [CommunityPose],
        page: Int,
        limit: Int,
        total: Int?
    ) -> PoseRemotePage {
        let start = max(0, (page - 1) * limit)
        let slice = start < items.count ? Array(items[start..<min(items.count, start + limit)]) : []
        return PoseRemotePage(poses: slice, total: total ?? items.count)
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
    private func makeModel(_ service: PagedPoseService, filter: PoseLibraryFilter = .community) -> PosesViewModel {
        let model = PosesViewModel(service: service)
        model.filter = filter
        return model
    }

    func testNextWindowIsAppendedWithoutLosingOrRepeatingRows() async {
        let service = PagedPoseService()
        service.library = numberedPoses(1...45)
        let model = makeModel(service)

        await model.load()
        XCTAssertEqual(pagedPoseIDs(model), numberedPoses(1...20).map(\.id))
        XCTAssertTrue(model.paging.hasMore)
        XCTAssertEqual(model.paging.nextOffset, 20, "the cursor counts the rows the server handed over")

        await model.loadMore()
        XCTAssertEqual(pagedPoseIDs(model), numberedPoses(1...40).map(\.id))
        XCTAssertEqual(model.paging.nextOffset, 40)

        await model.loadMore()
        XCTAssertEqual(pagedPoseIDs(model).count, 45)
        XCTAssertEqual(model.paging.nextOffset, 45)
        XCTAssertFalse(model.paging.hasMore, "the last window ends the list")
        XCTAssertNil(model.paging.error)
        XCTAssertEqual(service.requestedOffsets, [0, 20, 40])
    }

    func testPoseRepeatedAcrossWindowsIsShownOnce() async {
        let service = PagedPoseService()
        // A row inserted at the head between two windows shows up again in the second one.
        service.library = numberedPoses(1...20) + [pagedPose("p20"), pagedPose("p21")]
        let model = makeModel(service)

        await model.load()
        await model.loadMore()

        let ids = pagedPoseIDs(model)
        XCTAssertEqual(ids.count, 21, "a row two windows both return is drawn once")
        XCTAssertEqual(ids, numberedPoses(1...21).map(\.id))
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testLastWindowStopsAskingTheNetwork() async {
        let service = PagedPoseService()
        service.library = numberedPoses(1...45)
        let model = makeModel(service)

        await model.load()
        await model.loadMore()
        await model.loadMore()
        let asked = service.requestCount
        await model.loadMore()

        XCTAssertEqual(service.requestCount, asked, "an ended list must not request another window")
        XCTAssertEqual(pagedPoseIDs(model).count, 45)
    }

    func testFailedWindowKeepsLoadedRowsAndRetryLoadsTheSameOffset() async {
        let service = PagedPoseService()
        service.library = numberedPoses(1...45)
        service.offsetErrors[20] = URLError(.notConnectedToInternet)
        let model = makeModel(service)

        await model.load()
        await model.loadMore()

        XCTAssertEqual(pagedPoseIDs(model), numberedPoses(1...20).map(\.id), "a failed window keeps the loaded rows")
        XCTAssertNotNil(model.paging.error)
        XCTAssertTrue(model.paging.hasMore, "the window that failed is still owed")
        XCTAssertEqual(model.paging.nextOffset, 20, "the cursor stays on the failed window")
        XCTAssertFalse(model.paging.isLoading)

        service.offsetErrors[20] = nil
        await model.loadMoreResults()

        XCTAssertNil(model.paging.error)
        XCTAssertEqual(pagedPoseIDs(model).count, 40, "the retry appends the window that failed")
        XCTAssertEqual(service.requestedOffsets, [0, 20, 20])
    }

    func testRefreshStartsAgainFromTheFirstWindow() async {
        let service = PagedPoseService()
        service.library = numberedPoses(1...45)
        let model = makeModel(service)
        await model.load()
        await model.loadMore()
        XCTAssertEqual(pagedPoseIDs(model).count, 40)

        service.library = numberedPoses(46...85)
        await model.load()

        XCTAssertEqual(pagedPoseIDs(model), numberedPoses(46...65).map(\.id), "a refresh replaces the list")
        XCTAssertEqual(model.paging.nextOffset, 20, "the cursor restarts after the first window")
        XCTAssertTrue(model.paging.hasMore)

        await model.loadMore()
        XCTAssertEqual(pagedPoseIDs(model).count, 40)
        XCTAssertEqual(service.requestedOffsets, [0, 20, 0, 20])
    }

    func testQueryChangeDiscardsAWindowThatArrivesLate() async {
        let service = PagedPoseService()
        service.library = numberedPoses(1...45)
        service.heldOffsets = [20]
        let model = makeModel(service)
        await model.load()

        let paginating = Task { await model.loadMore() }
        await service.waitUntilRequested(20)

        model.query = "other"
        await model.load()

        service.release(offset: 20)
        await paginating.value

        XCTAssertEqual(pagedPoseIDs(model).count, 20, "a window fetched for the previous search is dropped")
        XCTAssertEqual(model.paging.nextOffset, 20)
    }

    func testTwoTriggersWhileLoadingSendOneRequest() async {
        let service = PagedPoseService()
        service.library = numberedPoses(1...40)
        service.heldOffsets = [20]
        let model = makeModel(service)
        await model.load()

        let first = Task { await model.loadMore() }
        await service.waitUntilRequested(20)
        let second = Task { await model.loadMore() }
        await Task.yield()

        service.release(offset: 20)
        await first.value
        await second.value

        XCTAssertEqual(service.requestedOffsets, [0, 20], "the second trigger joins the window in flight")
        XCTAssertEqual(pagedPoseIDs(model).count, 40)
    }

    /// The review's P1: the Saved collection loses a row when it is unsaved, so every later row moves
    /// up one position. A page counter would ask for offset 20 again and never show the row that
    /// moved into position 20.
    func testUnsavingARowMovesTheCursorSoNoRowIsSkipped() async {
        let service = PagedPoseService()
        service.library = numberedPoses(1...45, isSaved: true)
        let model = makeModel(service, filter: .saved)
        await model.load()
        XCTAssertEqual(model.paging.nextOffset, 20)

        // The DELETE lands: the server's Saved collection is now p2…p45.
        service.library.removeFirst()
        model.updateSavedLocally(poseID: "p1", saved: false)

        XCTAssertEqual(pagedPoseIDs(model).count, 19, "the unsaved row leaves the list")
        XCTAssertEqual(model.paging.nextOffset, 19, "the cursor follows the collection, not the visible rows")

        await model.loadMore()

        let ids = pagedPoseIDs(model)
        XCTAssertEqual(service.requestedOffsets, [0, 19])
        XCTAssertEqual(ids, numberedPoses(2...40).map(\.id), "p21 is not skipped and nothing is repeated")
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testUnsavingWhileAWindowIsInFlightDropsThatWindow() async {
        let service = PagedPoseService()
        service.library = numberedPoses(1...45, isSaved: true)
        service.heldOffsets = [20]
        let model = makeModel(service, filter: .saved)
        await model.load()

        let paginating = Task { await model.loadMore() }
        await service.waitUntilRequested(20)

        service.library.removeFirst()
        model.updateSavedLocally(poseID: "p1", saved: false)
        service.release(offset: 20)
        await paginating.value

        XCTAssertEqual(pagedPoseIDs(model), numberedPoses(2...20).map(\.id), "the window was cut for the old cursor")
        XCTAssertEqual(model.paging.nextOffset, 19)
        XCTAssertFalse(model.paging.isLoading)

        await model.loadMore()

        let ids = pagedPoseIDs(model)
        XCTAssertEqual(service.requestedOffsets, [0, 20, 19])
        XCTAssertEqual(ids, numberedPoses(2...40).map(\.id))
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    /// The review's P2: the community feed is public, so its cursor must survive a session change.
    func testCommunityListCanStillLoadMoreAfterASessionChange() async {
        let boundary = SessionBoundary(tokenStorage: PaginationTokenStorage())
        let service = PagedPoseService()
        service.library = numberedPoses(1...45)
        let model = PosesViewModel(service: service, boundary: boundary)
        await waitForSessionSubscription(boundary)
        model.filter = .community
        await model.load()
        XCTAssertEqual(model.paging.nextOffset, 20)

        await boundary.signOut()
        await boundary.saveCredentials(pagedCredentialsB)

        XCTAssertTrue(model.paging.hasMore, "a public list keeps its cursor across a session change")
        XCTAssertEqual(model.paging.nextOffset, 20)
        await model.loadMore()
        XCTAssertEqual(pagedPoseIDs(model).count, 40, "load more still works after the change")
    }

    /// The same change does drop an account-scoped list: Saved restarts from its first window.
    func testSavedListRestartsPagingAfterASessionChange() async {
        let boundary = SessionBoundary(tokenStorage: PaginationTokenStorage())
        let service = PagedPoseService()
        service.library = numberedPoses(1...45, isSaved: true)
        let model = PosesViewModel(service: service, boundary: boundary)
        await waitForSessionSubscription(boundary)
        model.filter = .saved
        await model.load()
        await model.loadMore()
        XCTAssertEqual(pagedPoseIDs(model).count, 40)

        await boundary.signOut()
        await boundary.saveCredentials(pagedCredentialsB)
        await waitUntil("the next Account's saved list loaded") {
            pagedPoseIDs(model).count == 20 && !model.paging.isLoading
        }

        XCTAssertEqual(model.paging.nextOffset, 20, "the next Account starts from its own first window")
        XCTAssertTrue(model.paging.hasMore)
        XCTAssertFalse(pagedPoseIDs(model).contains("p21"), "the previous Account's second window is gone")
    }

    func testEmptyFilteredFirstWindowKeepsPagingUntilAMatchIsFound() async {
        let service = PagedPoseService()
        service.library = numberedPoses(1...21)
        service.hiddenWindows = [0]
        let model = makeModel(service, filter: .saved)

        await model.load()

        XCTAssertEqual(pagedPoseIDs(model), ["p21"], "an empty window is not the end of a filtered list")
        XCTAssertFalse(model.paging.hasMore)
        XCTAssertEqual(service.requestedOffsets, [0, 20])
    }

    func testSpentAutoFetchBudgetOffersLoadMoreInsteadOfADeadEnd() async {
        let service = PagedPoseService()
        service.library = numberedPoses(1...100)
        service.hiddenWindows = [0, 20, 40, 60]
        let model = makeModel(service, filter: .saved)

        await model.load()

        XCTAssertEqual(service.requestedOffsets, [0, 20, 40, 60], "three automatic windows, then stop")
        XCTAssertEqual(model.paging.remainingAutoFetches, 0)
        XCTAssertTrue(model.paging.hasMore)
        if case .empty = model.state {} else { XCTFail("Expected the empty state until a match, got \(model.state)") }

        await model.loadMoreResults()

        XCTAssertEqual(service.requestedOffsets, [0, 20, 40, 60, 80])
        XCTAssertEqual(pagedPoseIDs(model), numberedPoses(81...100).map(\.id))
        XCTAssertFalse(model.paging.hasMore)
        XCTAssertEqual(model.paging.remainingAutoFetches, PosesViewModel.Paging.autoFetchBudget)
    }

    func testEveryWindowEmptyEndsEmptyWithNoMore() async {
        let service = PagedPoseService()
        let model = makeModel(service)

        await model.load()

        if case .empty = model.state {} else { XCTFail("Expected a final empty state, got \(model.state)") }
        XCTAssertFalse(model.paging.hasMore)
        XCTAssertNil(model.paging.error)
        XCTAssertEqual(service.requestedOffsets, [0], "an empty collection is not paged further")
    }

    /// A total that shrinks (or a server that reports none) must end the list, not loop forever.
    func testShrunkOrZeroTotalEndsTheListWithoutRepeatingRows() async {
        let service = PagedPoseService()
        service.library = numberedPoses(1...45)
        let model = makeModel(service)
        await model.load()
        XCTAssertTrue(model.paging.hasMore)

        // Rows were unpublished while we were paging: the collection is now exactly what we hold.
        service.library = numberedPoses(1...20)
        await model.loadMore()

        XCTAssertFalse(model.paging.hasMore)
        XCTAssertEqual(pagedPoseIDs(model), numberedPoses(1...20).map(\.id), "no duplicate and no crash")
        XCTAssertNil(model.paging.error)

        // A total below the cursor from the first window already ends the list.
        let zeroService = PagedPoseService()
        zeroService.library = numberedPoses(1...45)
        zeroService.reportedTotal = 0
        let zeroModel = makeModel(zeroService)
        await zeroModel.load()
        XCTAssertFalse(zeroModel.paging.hasMore, "a zero total is an ended list, not an endless one")
        XCTAssertEqual(pagedPoseIDs(zeroModel).count, 20)
    }

    func testFilterChangeStartsPagingOver() async {
        let service = PagedPoseService()
        service.library = numberedPoses(1...45)
        let model = makeModel(service)
        await model.load()
        await model.loadMore()
        XCTAssertEqual(pagedPoseIDs(model).count, 40)

        model.filter = .saved
        await model.load()

        XCTAssertEqual(model.paging.nextOffset, 20, "a new filter is a new list, not a continuation")
        XCTAssertFalse(model.paging.isLoading)
    }

    func testPageTwoPoseIsUsableWithoutACatalogRow() async {
        let service = PagedPoseService()
        service.library = [pagedPose("a")] + numberedPoses(21...40)
        service.library.append(pagedPose("late", isSaved: true))
        let model = makeModel(service)

        await model.load()
        await model.loadMore()

        XCTAssertEqual(pagedPoseIDs(model).last, "late")
        // The detail screen is handed the value from this list, so it needs no database row.
        XCTAssertEqual(model.savedState(for: pagedPose("late", isSaved: true)), true)
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

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTFail("timed out waiting for \(description)")
    }
}

// MARK: - adapter paging (server total, first-window-only catalog)

final class PoseAdapterPaginationTests: XCTestCase {
    private static let baseURL = "https://api.example.com"

    private func adapter(
        _ remote: LibraryPoseRemote,
        filter: PoseLibraryFilter = .community,
        cache: PoseCatalogCacheStore? = nil
    ) -> PoseAPIServiceAdapter {
        let filterState = PoseFilterState()
        filterState.filter = filter
        return PoseAPIServiceAdapter(remote: remote, baseURL: Self.baseURL, filterState: filterState, cache: cache)
    }

    private func window(_ adapter: PoseAPIServiceAdapter, offset: Int) async throws -> PosePage {
        try await adapter.posesPage(query: nil, offset: offset, limit: 20)
    }

    /// `hasMore` comes from the server total, never from the number of rows the window happened to
    /// return: an exactly-full window is not the last one.
    func testHasMoreFollowsTheServerTotal() async throws {
        let emptyPage = try await window(adapter(LibraryPoseRemote()), offset: 0)
        XCTAssertEqual(emptyPage.poses.count, 0)
        XCTAssertFalse(emptyPage.hasMore)

        let exactlyFull = try await window(adapter(LibraryPoseRemote(community: try libraryPoses(20))), offset: 0)
        XCTAssertEqual(exactlyFull.poses.count, 20)
        XCTAssertFalse(exactlyFull.hasMore, "20 of 20 rows is the end even though the window is full")

        let oneMore = adapter(LibraryPoseRemote(community: try libraryPoses(21)))
        let first = try await window(oneMore, offset: 0)
        XCTAssertTrue(first.hasMore)
        let second = try await window(oneMore, offset: 20)
        XCTAssertEqual(second.poses.count, 1)
        XCTAssertFalse(second.hasMore, "21 of 21 rows is the end of the second window")
    }

    func testThreeWindowLibraryPagesEndToEnd() async throws {
        let remote = LibraryPoseRemote(community: try libraryPoses(45))
        let adapter = adapter(remote)

        let first = try await window(adapter, offset: 0)
        let second = try await window(adapter, offset: 20)
        let third = try await window(adapter, offset: 40)

        XCTAssertEqual([first.poses.count, second.poses.count, third.poses.count], [20, 20, 5])
        XCTAssertEqual([first.hasMore, second.hasMore, third.hasMore], [true, true, false])
        XCTAssertEqual([first.consumed, second.consumed, third.consumed], [20, 20, 5])
        XCTAssertEqual(remote.communityPageAsks, [1, 2, 3])
        let ids = (first.poses + second.poses + third.poses).map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "no row is returned by two windows")
    }

    /// The Saved collection moved up one row, so the cursor is 19 — not a multiple of the 20-row
    /// server page. The adapter reads the aligned page that covers it and drops the rows before it.
    func testUnalignedOffsetAfterARemovalSlicesWithoutSkippingRows() async throws {
        let remote = LibraryPoseRemote(saved: try libraryPoses(45))
        let saved = adapter(remote, filter: .saved)
        let first = try await saved.posesPage(query: nil, offset: 0, limit: 20)
        XCTAssertEqual(first.poses.count, 20)

        // The DELETE lands: the collection is now the previous rows 2…45.
        remote.savedItems.removeFirst()
        remote.savedTotal = remote.savedItems.count

        let continuation = try await saved.posesPage(query: nil, offset: 19, limit: 20)
        XCTAssertEqual(continuation.poses.map(\.id), ["lib-21"], "the row that moved into position 20 is served")
        XCTAssertEqual(continuation.consumed, 1)
        XCTAssertTrue(continuation.hasMore)

        let after = try await saved.posesPage(query: nil, offset: 20, limit: 20)
        let ids = first.poses.map(\.id) + continuation.poses.map(\.id) + after.poses.map(\.id)
        XCTAssertEqual(ids, (1...41).map { "lib-\($0)" }, "contiguous: nothing skipped, nothing repeated")
    }

    func testSecondWindowWritesNothingToTheCatalog() async throws {
        let temp = try PaginationTempDatabase()
        defer { temp.cleanUp() }
        let scheduler = PaginationRefreshScheduler()
        let remote = LibraryPoseRemote(community: try libraryPoses(45))
        let cache = PoseCatalogCacheStore(repository: temp.repository, scheduler: scheduler)
        let adapter = adapter(remote, cache: cache)

        let first = try await window(adapter, offset: 0)
        XCTAssertEqual(first.poses.count, 20)
        let storedAfterFirst = try await temp.repository.cached().count
        XCTAssertEqual(storedAfterFirst, 20)
        let callsAfterFirst = remote.communityCallCount

        _ = try await window(adapter, offset: 20)

        let storedAfterSecond = try await temp.repository.cached().count
        XCTAssertEqual(storedAfterSecond, storedAfterFirst, "a later window is network-only: it writes no rows")

        let reread = try await adapter.poses(query: nil)
        XCTAssertEqual(reread.count, 20, "memory still holds the first window")
        XCTAssertEqual(remote.communityCallCount, callsAfterFirst + 1, "the only network call was the window itself")
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    func testSecondWindowFailsOfflineWhileTheFirstWindowStillServes() async throws {
        let temp = try PaginationTempDatabase()
        defer { temp.cleanUp() }
        let remote = LibraryPoseRemote(community: try libraryPoses(45))
        let cache = PoseCatalogCacheStore(repository: temp.repository, scheduler: PaginationRefreshScheduler())
        let adapter = adapter(remote, cache: cache)
        _ = try await window(adapter, offset: 0)

        remote.failure = URLError(.notConnectedToInternet)
        do {
            _ = try await window(adapter, offset: 20)
            XCTFail("a window past the cached one has no offline answer, so it must fail loudly")
        } catch {
            // expected: the screen keeps its rows and offers a retry
        }

        let firstWindow = try await window(adapter, offset: 0)
        XCTAssertEqual(firstWindow.poses.count, 20, "the first window is still answered while offline")
    }

    func testAllSourcePagesTheCommunityFeedOnly() async throws {
        let remote = LibraryPoseRemote(
            community: try libraryPoses(45),
            saved: [try libraryPose("saved-1")]
        )
        let all = adapter(remote, filter: .all)

        let first = try await all.posesPage(query: nil, offset: 0, limit: 20)
        XCTAssertEqual(first.consumed, 20, "the first window's cursor is the community feed only")
        let savedAfterFirst = remote.savedCallCount
        let communityAfterFirst = remote.communityCallCount
        XCTAssertGreaterThan(savedAfterFirst, 0, "the first window merges the saved collection")

        let second = try await all.posesPage(query: nil, offset: 20, limit: 20)

        XCTAssertEqual(remote.savedCallCount, savedAfterFirst, "later windows do not re-merge the saved list")
        XCTAssertEqual(remote.communityCallCount, communityAfterFirst + 1)
        XCTAssertEqual(second.poses.count, 20)
        XCTAssertEqual(second.poses.first?.id, "lib-21", "the saved rows of window 1 do not shift the cursor")
        XCTAssertTrue(second.hasMore)
    }

    func testSearchWindowsKeepTheQuery() async throws {
        let remote = LibraryPoseRemote(community: try libraryPoses(45))
        let adapter = adapter(remote)

        _ = try await adapter.posesPage(query: "warrior", offset: 20, limit: 20)

        XCTAssertEqual(remote.communityPageAsks, [2])
        XCTAssertEqual(remote.lastCommunityQuery, "warrior")
    }

    /// A saved window can contribute zero matches for the query and still not be the last one.
    func testSavedWindowWithoutMatchesStillReportsMore() async throws {
        let remote = LibraryPoseRemote(saved: try libraryPoses(41))
        let saved = adapter(remote, filter: .saved)

        let page = try await saved.posesPage(query: "zzzz", offset: 20, limit: 20)

        XCTAssertEqual(page.poses.count, 0, "the local name filter removes the window's rows")
        XCTAssertEqual(page.consumed, 20, "but the server did hand over a full window")
        XCTAssertTrue(page.hasMore, "the server total, not the local match count, decides hasMore")
    }

    /// Sol's coverage gap: a stale, zero or shrunken total must end the list instead of crashing or
    /// asking for the same window forever.
    func testStaleOrShrunkenTotalEndsTheList() async throws {
        let remote = LibraryPoseRemote(community: try libraryPoses(45))
        let adapter = adapter(remote)

        let first = try await window(adapter, offset: 0)
        XCTAssertTrue(first.hasMore)

        remote.communityTotal = 10
        let beyondTotal = try await window(adapter, offset: 20)
        XCTAssertEqual(beyondTotal.poses.count, 20, "the rows the server did return are still usable")
        XCTAssertFalse(beyondTotal.hasMore, "a total below the cursor ends the list")

        remote.communityTotal = 0
        let pastTheEnd = try await window(adapter, offset: 80)
        XCTAssertEqual(pastTheEnd.poses.count, 0)
        XCTAssertEqual(pastTheEnd.consumed, 0)
        XCTAssertFalse(pastTheEnd.hasMore)
    }
}
