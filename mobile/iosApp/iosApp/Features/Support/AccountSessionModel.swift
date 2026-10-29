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
    /// The Apple authorization code, non-nil only on the retry that follows the server's 409.
    typealias AccountDeleter = (String?) async throws -> Void
    /// Runs the Apple sheet and returns a fresh authorization code, or throws `CancellationError`.
    typealias AppleReauthorizer = () async throws -> String

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

    /// Sign-out is the account-switching affordance on this screen. It is unavailable while a deletion
    /// is in flight: switching identity mid-deletion is how a reply lands on the next account (its
    /// local data wiped, or — worse — its identity deleted by A's Apple confirmation).
    var isSignOutAvailable: Bool {
        guard case .signedIn = state else { return false }
        return !isDeletingAccount
    }

    private let boundary: SessionBoundary
    private let readAccount: AccountReader
    private let signInAction: SignInAction
    private let deleteAccountRequest: AccountDeleter
    private let reauthorizeWithApple: AppleReauthorizer
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
            try await ServiceLocator.makePoseAPIService().deleteAccount(appleAuthorizationCode: $0)
        },
        appleReauthorize: @escaping AppleReauthorizer = {
            try await AppleReauthorizationAction().authorizationCode()
        },
        signInHistory: SignInHistoryRecording = UserDefaultsSignInHistory.shared
    ) {
        self.boundary = boundary
        self.readAccount = readAccount
        self.signInAction = signInAction
        self.deleteAccountRequest = deleteAccount
        self.reauthorizeWithApple = appleReauthorize
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
        // The deletion owns the session until it settles; see `isSignOutAvailable`.
        guard !isDeletingAccount else { return }
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
    ///
    /// An account that signs in with Apple is a two-step handshake: the server refuses to touch
    /// anything until it has a fresh Apple authorization code (guideline 5.1.1(v) revocation). We
    /// ask Apple exactly once; a second refusal is reported as a failure, and a cancelled sheet
    /// sends no second request at all, so the account is provably untouched.
    ///
    /// The whole attempt is bound to one `SessionTicket`: if the session moves under it (the user
    /// signs out, or another account signs in during the Apple sheet) the reply is dropped instead of
    /// signing out — and wiping the local data of — whoever is signed in now.
    func deleteAccount() {
        guard !isDeletingAccount else { return }
        isDeletingAccount = true
        deleteAccountError = nil
        Task { [weak self] in
            guard let self else { return }
            let ticket = await self.scope.beginRequest()
            do {
                try await self.deleteAccountRequest(nil)
                await self.finishDeletion(ticket)
            } catch AccountDeletionError.appleReauthRequired {
                await self.confirmWithAppleThenDelete(ticket)
            } catch {
                await self.finishFailedDeletion(error, ticket: ticket)
            }
        }
    }

    private func confirmWithAppleThenDelete(_ ticket: SessionTicket) async {
        guard await scope.isValid(ticket) else { return abandonDeletion() }

        let code: String
        do {
            code = try await reauthorizeWithApple()
        } catch is CancellationError {
            // Nothing was sent after the sheet closed, so the account was never touched.
            guard await scope.isValid(ticket) else { return abandonDeletion() }
            isDeletingAccount = false
            deleteAccountError = AccountStateCopy.deleteAccountCancelledMessage
            return
        } catch {
            guard await scope.isValid(ticket) else { return abandonDeletion() }
            isDeletingAccount = false
            deleteAccountError = AccountStateCopy.deleteAccountAppleConfirmationFailedMessage
            return
        }

        // The sheet is the one long gap in this flow and it can hand the device to another account:
        // the confirmation must never be sent on a session that is no longer the one that started it.
        guard await scope.isValid(ticket) else { return abandonDeletion() }

        do {
            try await deleteAccountRequest(code)
            await finishDeletion(ticket)
        } catch {
            await finishFailedDeletion(error, ticket: ticket)
        }
    }

    private func finishDeletion(_ ticket: SessionTicket) async {
        // Local cleanup and `boundary.signOut()` are destructive to whoever is signed in *now*, so they
        // are only allowed while this attempt still belongs to the current session.
        guard await scope.isValid(ticket) else { return abandonDeletion() }
        await boundary.signOut()
        isDeletingAccount = false
        state = .signedOut
    }

    private func finishFailedDeletion(_ error: Error, ticket: SessionTicket? = nil) async {
        if let ticket {
            guard await scope.isValid(ticket) else { return abandonDeletion() }
        }
        isDeletingAccount = false
        deleteAccountError = Self.deleteAccountMessage(for: error)
    }

    /// The session moved under the deletion, so the attempt is dropped without a trace: no sign-out, no
    /// local reset, and no error on the screen of the person who is signed in now.
    private func abandonDeletion() {
        isDeletingAccount = false
        deleteAccountError = nil
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
        switch error as? AccountDeletionError {
        case .appleIdentityMismatch:
            return AccountStateCopy.deleteAccountAppleIdentityMismatchMessage
        case .appleReauthRequired:
            // The handshake sends the code once; a second refusal is terminal for this attempt.
            return AccountStateCopy.deleteAccountAppleConfirmationFailedMessage
        case nil:
            break
        }
        if error is AppleReauthorizationError {
            return AccountStateCopy.deleteAccountAppleConfirmationFailedMessage
        }
        return ErrorCopy.text(for: error) ?? "Account deletion could not be completed."
    }
}
