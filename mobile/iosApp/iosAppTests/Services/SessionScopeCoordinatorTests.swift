import XCTest
@testable import iosApp

private final class InMemoryTokenStorage: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var credentials: SessionCredentials?

    init(credentials: SessionCredentials? = nil) {
        self.credentials = credentials
    }

    func saveCredentials(_ credentials: SessionCredentials) {
        lock.lock()
        self.credentials = credentials
        lock.unlock()
    }

    func loadCredentials() -> SessionCredentials? {
        lock.lock()
        defer { lock.unlock() }
        return credentials
    }

    func clearCredentials() {
        lock.lock()
        credentials = nil
        lock.unlock()
    }
}

/// Drives the app database used by one coordinator test.
private final class TempPoseDatabase {
    let root: URL
    let database: AppDatabase

    var repository: PoseRepository { PoseRepository(database: database) }

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("session-scope-\(UUID().uuidString)", isDirectory: true)
        database = try AppDatabase(
            location: AppDatabaseLocation(url: root.appendingPathComponent("aipose.db"), kind: .freshInstall)
        )
    }

    func cleanUp() {
        try? database.pool.close()
        try? FileManager.default.removeItem(at: root)
    }
}

private struct StubPoseRemote: PoseRemoteFetching {
    let community: [CommunityPose]
    let saved: [CommunityPose]

    func fetchCommunity(page: Int, limit: Int, query: String?) async throws -> PoseRemotePage {
        PoseRemotePage(poses: community, total: community.count)
    }

    func fetchSaved(page: Int, limit: Int) async throws -> PoseRemotePage {
        PoseRemotePage(poses: saved, total: saved.count)
    }
}

private let storedCredentials = SessionCredentials(accessToken: "access", refreshToken: "refresh")

@MainActor
final class SessionScopeCoordinatorTests: XCTestCase {
    private static let baseURL = "https://api.example.com"

    private func decodePose(_ id: String, name: String) throws -> CommunityPose {
        try JSONDecoder().decode(CommunityPose.self, from: Data("""
        {"poseId":"\(id)","name":"\(name)","skeletonUrl":"/s.png","thumbnailUrl":"/t.jpg","status":"published"}
        """.utf8))
    }

    /// Seeds the offline catalog with a community row that is also saved (`shared-1`) and a
    /// saved-only row (`mine-1`), which is the shape sign-out cleanup has to tell apart.
    private func seed(_ cache: PoseCatalogCacheStore, temp: TempPoseDatabase) async throws {
        let filterState = PoseFilterState()
        let adapter = PoseAPIServiceAdapter(
            remote: StubPoseRemote(
                community: [try decodePose("shared-1", name: "Shared")],
                saved: [try decodePose("shared-1", name: "Shared"), try decodePose("mine-1", name: "Mine")]
            ),
            baseURL: Self.baseURL,
            filterState: filterState,
            cache: cache,
            hasSession: { true }
        )
        _ = try await adapter.poses(query: nil)
        filterState.filter = .saved
        _ = try await adapter.poses(query: nil)

        let stored = try await temp.repository.cached()
        XCTAssertEqual(stored.filter { $0.status == PoseCatalogMapping.savedStatus }.count, 2, "seeded saved rows")
    }

    private func cachedIDs(_ temp: TempPoseDatabase) async throws -> [String] {
        try await temp.repository.cached().map(\.poseId)
    }

    private func savedRowCount(_ temp: TempPoseDatabase) async throws -> Int {
        try await temp.repository.cached().filter { $0.status == PoseCatalogMapping.savedStatus }.count
    }

    /// Signing in starts a new Account context: the previous context's Saved rows must be gone even
    /// when the change is Account-to-Account with no sign-out in between.
    func testSignInDropsAccountScopedCatalogRows() async throws {
        let temp = try TempPoseDatabase()
        defer { temp.cleanUp() }
        let cache = PoseCatalogCacheStore(repository: temp.repository)
        try await seed(cache, temp: temp)

        let boundary = SessionBoundary(tokenStorage: InMemoryTokenStorage())
        let coordinator = SessionScopeCoordinator(
            boundary: boundary,
            cache: cache,
            purchases: FakePurchasesAdapter.make(),
            readAccount: { AccountSummary(id: "account-b", displayName: "B", createdAt: nil) }
        )
        coordinator.start()
        await coordinator.waitUntilSubscribed()

        let before = coordinator.fanOutsSettled
        await boundary.saveCredentials(storedCredentials)
        await coordinator.waitUntilSettled(after: before + 1)

        let remainingSaved = try await savedRowCount(temp)
        XCTAssertEqual(remainingSaved, 0)
        let remaining = try await cachedIDs(temp)
        XCTAssertEqual(remaining, ["shared-1"], "the community row survives")
    }

    func testSignOutDropsAccountScopedCatalogRows() async throws {
        let temp = try TempPoseDatabase()
        defer { temp.cleanUp() }
        let cache = PoseCatalogCacheStore(repository: temp.repository)
        try await seed(cache, temp: temp)

        let storage = InMemoryTokenStorage(credentials: storedCredentials)
        let boundary = SessionBoundary(tokenStorage: storage)
        let coordinator = SessionScopeCoordinator(
            boundary: boundary,
            cache: cache,
            purchases: FakePurchasesAdapter.make(),
            readAccount: { AccountSummary(id: "account-a", displayName: "A", createdAt: nil) }
        )
        coordinator.start()
        await coordinator.waitUntilSubscribed()
        let seededSaved = try await savedRowCount(temp)
        XCTAssertGreaterThan(seededSaved, 0, "an unchanged session keeps its catalog")

        let before = coordinator.fanOutsSettled
        await boundary.signOut()
        await coordinator.waitUntilSettled(after: before + 1)
        let remainingSaved = try await savedRowCount(temp)
        XCTAssertEqual(remainingSaved, 0)
    }

    /// A 401 that clears the session is a context change too.
    func testUnauthorizedClearDropsAccountScopedCatalogRows() async throws {
        let temp = try TempPoseDatabase()
        defer { temp.cleanUp() }
        let cache = PoseCatalogCacheStore(repository: temp.repository)
        try await seed(cache, temp: temp)

        let boundary = SessionBoundary(tokenStorage: InMemoryTokenStorage(credentials: storedCredentials))
        let coordinator = SessionScopeCoordinator(
            boundary: boundary,
            cache: cache,
            purchases: FakePurchasesAdapter.make(),
            readAccount: { AccountSummary(id: "account-a", displayName: "A", createdAt: nil) }
        )
        coordinator.start()
        await coordinator.waitUntilSubscribed()

        let before = coordinator.fanOutsSettled
        await boundary.clearForUnauthorized()
        await coordinator.waitUntilSettled(after: before + 1)
        let remainingSaved = try await savedRowCount(temp)
        XCTAssertEqual(remainingSaved, 0)
    }

    /// A failed Account read leaves the provider context unlinked rather than guessing an identity,
    /// and must not disturb the session itself.
    func testLinkIsSkippedWhenTheAccountReadFails() async throws {
        let temp = try TempPoseDatabase()
        defer { temp.cleanUp() }
        let cache = PoseCatalogCacheStore(repository: temp.repository)
        let boundary = SessionBoundary(tokenStorage: InMemoryTokenStorage())
        let purchases = FakePurchasesAdapter.make()
        let coordinator = SessionScopeCoordinator(
            boundary: boundary,
            cache: cache,
            purchases: purchases,
            readAccount: { throw PoseAPIError(code: "503", message: "unavailable") }
        )
        coordinator.start()
        await coordinator.waitUntilSubscribed()

        let before = coordinator.fanOutsSettled
        await boundary.saveCredentials(storedCredentials)
        await coordinator.waitUntilSettled(after: before + 1)

        XCTAssertNil(purchases.linkedAccountID, "no identity is invented when the read fails")
        let token = await boundary.loadAccessToken()
        XCTAssertNotNil(token, "the session itself is untouched")
    }

    /// The coordinator's clear is what makes a *late* answer stale: it advances the cache's session
    /// epoch, and every account-scoped write that captured the previous one commits nothing
    /// (proven in `PoseSessionEpochTests`). A sign-out, a sign-in and a 401 clear all take this path.
    func testSessionChangeAdvancesTheEpochThatGuardsInFlightWrites() async throws {
        let temp = try TempPoseDatabase()
        defer { temp.cleanUp() }
        let cache = PoseCatalogCacheStore(repository: temp.repository)
        let boundary = SessionBoundary(tokenStorage: InMemoryTokenStorage(credentials: storedCredentials))
        let coordinator = SessionScopeCoordinator(
            boundary: boundary,
            cache: cache,
            purchases: FakePurchasesAdapter.make(),
            readAccount: { AccountSummary(id: "account-a", displayName: "A", createdAt: nil) }
        )
        coordinator.start()
        await coordinator.waitUntilSubscribed()

        let inFlightEpoch = cache.beginAccountScopedOperation()
        let before = coordinator.fanOutsSettled
        await boundary.signOut()
        await coordinator.waitUntilSettled(after: before + 1)

        XCTAssertNotEqual(cache.beginAccountScopedOperation(), inFlightEpoch)
        let token = await boundary.loadAccessToken()
        XCTAssertNil(token)
    }

    // MARK: - helpers

    /// A coordinator's store side without RevenueCat: the fan-out is the work under test, not the store's
    /// network call. `RevenueCatAdapter` with a fake provider is the same object the app uses, minus the SDK.
    enum FakePurchasesAdapter {
        @MainActor static func make() -> RevenueCatAdapter {
            RevenueCatAdapter(provider: FakePurchasesProvider(), entitlementID: nil)
        }
    }
}
