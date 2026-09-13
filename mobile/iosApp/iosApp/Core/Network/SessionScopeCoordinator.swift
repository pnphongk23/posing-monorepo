import Foundation

/// App-scope reaction to `SessionBoundary` changes.
///
/// Two pieces of state follow the signed-in Account and belong to no screen:
///  - the offline pose catalog keeps account-scoped Saved rows, so a session *change* drops them
///    (FEAT-014 FR-005 — Account A's rows must not answer Account B's or a guest's read);
///  - the RevenueCat customer is the Account (FEAT-011 FR-006), so the provider context is linked
///    after sign-in and reset before another context can mount (E4).
///
/// Started once from `AppDelegate`; a screen may come and go, this must not.
///
/// Only an actual boundary event clears the catalog: launching with an unchanged session keeps its
/// confirmed offline read (the Saved list's "Offline · showing saved poses from last confirmed
/// read" state), because the credentials still name the Account those rows belong to.
@MainActor
final class SessionScopeCoordinator {
    static let shared = SessionScopeCoordinator()

    private let boundary: SessionBoundary
    private let cache: PoseCatalogCacheStore
    private let purchases: RevenueCatAdapter
    private let readAccount: () async throws -> AccountSummary
    private var task: Task<Void, Never>?
    private var generation = 0

    init(
        boundary: SessionBoundary = ServiceLocator.sessionBoundary,
        cache: PoseCatalogCacheStore = .shared,
        purchases: RevenueCatAdapter = .shared,
        readAccount: @escaping () async throws -> AccountSummary = {
            try await ServiceLocator.makePoseAPIService().getCurrentAccount()
        }
    ) {
        self.boundary = boundary
        self.cache = cache
        self.purchases = purchases
        self.readAccount = readAccount
    }

    deinit {
        task?.cancel()
    }

    func start() {
        guard task == nil else { return }
        task = boundary.observeSessions(
            // A launch with an already-stored session emits no event, so link it up front.
            onStart: { [weak self] in
                guard let self else { return }
                await self.linkCurrentAccount()
            },
            onEvent: { [weak self] _ in
                guard let self else { return }
                await self.handleSessionChange()
                await self.linkCurrentAccount()
            }
        )
    }

    /// Binds the provider customer to whatever Account the current session resolves to.
    /// `RevenueCatAdapter.linkAccount` is idempotent, so an unchanged session is a no-op.
    private func linkCurrentAccount() async {
        guard await boundary.hasStoredSession() else { return }
        generation += 1
        let requestGeneration = generation
        // Read the Account first so the RevenueCat customer id is the same identity the backend
        // authorizes against; a failed read leaves the provider context unlinked.
        guard let account = try? await readAccount() else { return }
        guard requestGeneration == generation else { return }
        await purchases.linkAccount(account.id)
    }

    /// A credential change means the account context changed, even when it changed from one Account
    /// straight to another, so the previous context is dropped before the next one is mounted.
    private func handleSessionChange() async {
        generation += 1
        await cache.clearSavedState()
        await purchases.clearAccount()
    }
}
