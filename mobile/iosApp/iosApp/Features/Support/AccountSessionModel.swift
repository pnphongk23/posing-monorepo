import Foundation

/// Read-only Account projection plus its session lifecycle.
///
/// Ported from the KMP `AccountSessionController`: it owns no profile writes, and every
/// in-flight read is discarded once the session generation moves under it (sign-in,
/// sign-out, or a 401 refresh/clear), so a stale response can never repaint a previous
/// account's identity over a signed-out or switched session.
@MainActor
final class AccountSessionModel: ObservableObject {
    typealias AccountReader = () async throws -> AccountSummary

    enum State: Equatable {
        case loading
        case signedOut
        case signedIn(AccountSummary)
        case failed(String)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var isAuthenticating = false
    @Published private(set) var authError: String?

    private let boundary: SessionBoundary
    private let readAccount: AccountReader
    private let signInAction: SignInAction
    private var generationID = 0
    private var sessionTask: Task<Void, Never>?

    init(
        boundary: SessionBoundary = ServiceLocator.sessionBoundary,
        readAccount: @escaping AccountReader = {
            try await ServiceLocator.makePoseAPIService().getCurrentAccount()
        },
        signInAction: SignInAction = SignInAction()
    ) {
        self.boundary = boundary
        self.readAccount = readAccount
        self.signInAction = signInAction
    }

    deinit {
        sessionTask?.cancel()
    }

    /// Starts session observation once, then projects the stored session.
    func start() {
        observeSessionOnce()
        refresh()
    }

    func refresh() {
        let requestGeneration = nextGeneration()
        Task { [weak self] in
            guard let self else { return }
            guard await self.boundary.hasStoredSession() else {
                if self.isCurrent(requestGeneration) { self.state = .signedOut }
                return
            }
            let sessionGeneration = await self.boundary.currentGeneration
            guard self.isCurrent(requestGeneration) else { return }
            self.state = .loading
            do {
                let account = try await self.readAccount()
                guard self.isCurrent(requestGeneration) else { return }
                guard await self.boundary.currentGeneration == sessionGeneration else { return }
                self.state = await self.boundary.hasStoredSession() ? .signedIn(account) : .signedOut
            } catch {
                guard self.isCurrent(requestGeneration) else { return }
                guard await self.boundary.currentGeneration == sessionGeneration else { return }
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
        let requestGeneration = nextGeneration()
        Task { [weak self] in
            guard let self else { return }
            await self.boundary.signOut()
            guard self.isCurrent(requestGeneration) else { return }
            self.state = .signedOut
        }
    }

    // MARK: - session observation

    private func observeSessionOnce() {
        guard sessionTask == nil else { return }
        // `start()` projects the stored session itself, so this observer has no `onStart` step.
        sessionTask = boundary.observeSessions(
            onEvent: { [weak self] event in
                guard let self else { return }
                self.handle(event)
            }
        )
    }

    private func handle(_ event: SessionEvent) {
        switch event {
        case .signedIn:
            // Credentials changed: discard whatever the previous session was reading.
            _ = nextGeneration()
            state = .loading
            refresh()
        case .signedOut, .signInRequired:
            _ = nextGeneration()
            state = .signedOut
        }
    }

    // MARK: - generation

    private func nextGeneration() -> Int {
        generationID += 1
        return generationID
    }

    private func isCurrent(_ requestGeneration: Int) -> Bool {
        generationID == requestGeneration
    }

    private static func accountMessage(for error: Error) -> String {
        ErrorCopy.text(for: error) ?? "Unable to load your account."
    }
}
