import Foundation

/// Read-only Account projection plus its session lifecycle.
///
/// Ported from the KMP `AccountSessionController`: it owns no profile writes, and every
/// in-flight read is discarded once the session generation moves under it (sign-in,
/// sign-out, or a 401 refresh/clear), so a stale response can never repaint a previous
/// account's identity over a signed-out or switched session.
@MainActor
final class AccountSessionModel: ObservableObject, SessionScoped {
    typealias AccountReader = () async throws -> AccountSummary
    typealias AccountDeleter = () async throws -> Void

    enum State: Equatable {
        case loading
        case signedOut
        case signedIn(AccountSummary)
        case failed(String)
    }

    @Published private(set) var state: State = .loading
    /// `true` once a real session has existed on this install (see `SignInHistoryRecording`).
    ///
    /// Read live from the install-level store instead of being copied into a published field: the
    /// copy depends on it, and a cached copy needs a projection hook on every transition (sign-in,
    /// sign-out, 401, delete) or it silently goes stale. Every transition that matters republishes
    /// `state`, which is what re-renders the card.
    var hasSignedInBefore: Bool { signInHistory.hasSignedInBefore }
    @Published private(set) var isAuthenticating = false
    @Published private(set) var authError: String?
    @Published private(set) var isDeletingAccount = false
    @Published private(set) var deleteAccountError: String?

    private let boundary: SessionBoundary
    private let readAccount: AccountReader
    private let signInAction: SignInAction
    private let deleteAccountRequest: AccountDeleter
    private let scope: SessionScope
    /// Read-only here: `SessionBoundary` is the only writer of the install's sign-in history.
    private let signInHistory: SignInHistoryRecording
    /// Local request token: a newer refresh supersedes the read before it. Session staleness is the
    /// scope's job (a ticket), this one is only "which read is the latest".
    private var refreshGeneration: UInt64 = 0

    init(
        boundary: SessionBoundary = ServiceLocator.sessionBoundary,
        readAccount: @escaping AccountReader = {
            try await ServiceLocator.makePoseAPIService().getCurrentAccount()
        },
        signInAction: SignInAction = SignInAction(),
        deleteAccount: @escaping AccountDeleter = {
            try await ServiceLocator.makePoseAPIService().deleteAccount()
        },
        signInHistory: SignInHistoryRecording = UserDefaultsSignInHistory.shared
    ) {
        self.boundary = boundary
        self.readAccount = readAccount
        self.signInAction = signInAction
        self.deleteAccountRequest = deleteAccount
        self.signInHistory = signInHistory
        self.scope = SessionScope.of(boundary)
        scope.adopt(self)
    }

    /// Starts the projection of the stored session. The session subscription belongs to the scope.
    func start() {
        refresh()
    }

    func refresh() {
        let request = beginRefresh()
        Task { [weak self] in
            guard let self else { return }
            let ticket = await self.scope.beginRequest()
            guard await self.boundary.hasStoredSession() else {
                if await self.isCurrent(request, ticket) { self.state = .signedOut }
                return
            }
            guard await self.isCurrent(request, ticket) else { return }
            self.state = .loading
            do {
                let account = try await self.readAccount()
                guard await self.isCurrent(request, ticket) else { return }
                self.state = await self.boundary.hasStoredSession() ? .signedIn(account) : .signedOut
            } catch {
                guard await self.isCurrent(request, ticket) else { return }
                if let apiError = error as? PoseAPIError, apiError.isUnauthorized {
                    // 401 is never an empty/failed account: it is a signed-out session.
                    self.state = .signedOut
                } else {
                    self.state = .failed(Self.accountMessage(for: error))
                }
            }
        }
    }

    func retry() {
        refresh()
    }

    func signIn() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        authError = nil
        Task { [weak self] in
            guard let self else { return }
            let outcome = await self.signInAction.run()
            self.isAuthenticating = false
            switch outcome {
            case .succeeded:
                // The sign-in seam persists through `SessionBoundary`, and its `.signedIn`
                // event already reloads. Only re-read when nothing did (a host that stores
                // credentials without emitting) so the screen cannot sit on stale state.
                if await self.boundary.hasStoredSession(), self.state != .loading {
                    self.refresh()
                }
            case .cancelled:
                break
            case .failed(let text):
                self.authError = text
            }
        }
    }

    func signOut() {
        let request = beginRefresh()
        Task { [weak self] in
            guard let self else { return }
            await self.boundary.signOut()
            guard self.refreshGeneration == request else { return }
            self.state = .signedOut
        }
    }

    /// Deletes remotely first. Only the API client's accepted 204 path reaches `signOut()`, which
    /// emits the existing session event for app-scope cache and RevenueCat cleanup.
    func deleteAccount() {
        guard !isDeletingAccount else { return }
        isDeletingAccount = true
        deleteAccountError = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.deleteAccountRequest()
                await self.boundary.signOut()
                self.isDeletingAccount = false
                self.state = .signedOut
            } catch {
                self.isDeletingAccount = false
                self.deleteAccountError = Self.deleteAccountMessage(for: error)
            }
        }
    }

    // MARK: - session changes

    /// Credentials changed: discard whatever the previous session was reading, then re-project.
    /// Called synchronously by the scope in the same turn as the generation bump.
    func resetForSessionChange(_ event: SessionEvent) {
        switch event {
        case .signedIn:
            beginRefresh()
            state = .loading
            refresh()
        case .signedOut, .signInRequired:
            beginRefresh()
            state = .signedOut
        }
    }

    // MARK: - request tokens

    @discardableResult
    private func beginRefresh() -> UInt64 {
        refreshGeneration &+= 1
        return refreshGeneration
    }

    /// Both halves must hold: this is still the latest read, and its session is still the current one.
    private func isCurrent(_ request: UInt64, _ ticket: SessionTicket) async -> Bool {
        guard refreshGeneration == request else { return false }
        return await scope.isValid(ticket)
    }

    private static func accountMessage(for error: Error) -> String {
        ErrorCopy.text(for: error) ?? "Unable to load your account."
    }

    private static func deleteAccountMessage(for error: Error) -> String {
        if let apiError = error as? PoseAPIError {
            if apiError.isUnauthorized { return "Please sign in again." }
            if ["503", "AUTH_PENDING_VALIDATION"].contains(apiError.code) {
                return "Account deletion is temporarily unavailable. Try again later."
            }
        }
        return ErrorCopy.text(for: error) ?? "Account deletion could not be completed."
    }
}
