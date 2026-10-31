import Foundation
import Network

// MARK: - Identity the session can prove

/// The identity facts the *session this device holds* can prove, as opposed to facts a board draws.
///
/// `/api/account/me` answers `id`, `displayName` and `createdAt` only, and it is the one shape the
/// Account projection reads. The email address and the provider that was used to sign in are not in
/// that payload, but they are in the access token the app already stores: Supabase signs `email`,
/// `app_metadata.provider` and `amr` into it. Reading them back from the token keeps the Account
/// screen truthful ("show what the session has") without inventing a value or widening a server
/// contract, and it works offline because the token never leaves the keychain.
struct AccountIdentity: Equatable {
    var email: String?
    /// "Apple", "Google" or "Email", `nil` when the token does not name a provider.
    var signInMethod: String?

    static let unknown = AccountIdentity()

    /// Nothing to read: the Profile section renders no rows at all rather than empty ones.
    var isEmpty: Bool { email == nil && signInMethod == nil }
}

/// Pure reader for the claims already carried by a stored access token.
///
/// It decodes, it never verifies: the token was verified by the server that issued it, and this type
/// only projects the two claims the Account screen reads. A malformed, opaque or non-JWT token is not
/// an error here — it simply proves nothing, so the screen shows no Profile rows.
enum SessionTokenClaims {
    static func identity(fromAccessToken token: String) -> AccountIdentity {
        guard let payload = payload(fromAccessToken: token) else { return .unknown }
        return AccountIdentity(
            email: email(in: payload),
            signInMethod: methodLabel(in: payload)
        )
    }

    /// The JSON body of a JWT (`header.payload.signature`), decoded from its base64url middle part.
    static func payload(fromAccessToken token: String) -> [String: Any]? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2, !parts[1].isEmpty else { return nil }
        guard let data = base64URLDecode(String(parts[1])),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    static func base64URLDecode(_ segment: String) -> Data? {
        var value = segment
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // base64url drops the padding; base64 needs it back before it can decode.
        let remainder = value.count % 4
        if remainder > 0 { value += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: value)
    }

    /// A trimmed, plausible address. Anything else is not an email and is not shown as one.
    static func email(in payload: [String: Any]) -> String? {
        guard let raw = payload["email"] as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let at = trimmed.firstIndex(of: "@"), at != trimmed.startIndex, at < trimmed.index(before: trimmed.endIndex) else {
            return nil
        }
        return trimmed
    }

    /// Supabase writes `app_metadata.provider` ("email", "apple", "google"), and for password
    /// sign-in the `amr` list carries the method (`"password"`). Both are read, because an account
    /// that later linked a provider has a provider it did not sign in with right now.
    static func methodLabel(in payload: [String: Any]) -> String? {
        if let metadata = payload["app_metadata"] as? [String: Any],
           let provider = metadata["provider"] as? String,
           let label = label(forProvider: provider) {
            return label
        }
        guard let methods = payload["amr"] as? [Any] else { return nil }
        for entry in methods {
            // `amr` is either `[{"method": "password"}]` or `["password"]` depending on the issuer.
            let method = (entry as? [String: Any])?["method"] as? String ?? entry as? String
            if let method, let label = label(forProvider: method) { return label }
        }
        return nil
    }

    /// Unknown providers stay `nil` on purpose: the row is hidden rather than labelled "Other".
    static func label(forProvider provider: String) -> String? {
        switch provider.lowercased() {
        case "apple": return "Apple"
        case "google": return "Google"
        case "email", "password": return "Email"
        default: return nil
        }
    }
}

/// Avatar initials for the profile card and the Account header. Pure, so the two surfaces cannot
/// disagree about what "Maya Pham" abbreviates to.
enum AccountAvatar {
    /// At most two letters, taken from the first two words; an empty name has no initials (the
    /// surface falls back to its own glyph) instead of a made-up letter.
    static func initials(for displayName: String) -> String {
        let words = displayName
            .split(whereSeparator: { $0.isWhitespace || $0 == "@" || $0 == "." || $0 == "_" || $0 == "-" })
            .filter { !$0.isEmpty }
        let letters = words.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }
}

/// The App Store's own subscription-management page. Apple owns that screen; the app only hands the
/// URL to the system, exactly like the deletion-request row hands over its form.
enum SubscriptionManagement {
    /// Pinned as a string so a test can assert the exact destination the row opens
    /// (`TC-ACC-028` cannot prove which URL the browser received).
    static let appStoreSubscriptions = "https://apps.apple.com/account/subscriptions"

    static var appStoreSubscriptionsURL: URL? { URL(string: appStoreSubscriptions) }
}

/// Reachability, as the Account surface needs it ("the cached details are what you are reading").
@MainActor
protocol AccountConnectivityMonitoring: AnyObject {
    var onChange: ((Bool) -> Void)? { get set }
    func start()
    func stop()
}

/// `NWPathMonitor` behind the protocol, so the model stays drivable in tests.
///
/// A monitor is created per presentation: `NWPathMonitor.cancel()` is terminal, so a stale reading
/// must not outlive the screen that owns it.
@MainActor
final class NWPathAccountConnectivity: AccountConnectivityMonitoring {
    var onChange: ((Bool) -> Void)?

    private var pathMonitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "aipose.account.path")

    func start() {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let isOffline = path.status != .satisfied
            Task { @MainActor [weak self] in
                self?.onChange?(isOffline)
            }
        }
        pathMonitor = monitor
        monitor.start(queue: queue)
    }

    func stop() {
        pathMonitor?.cancel()
        pathMonitor = nil
    }
}

/// Read-only Account projection plus its session lifecycle.
///
/// Ported from the KMP `AccountSessionController`: it owns no profile writes, and every
/// in-flight read is discarded once the session generation moves under it (sign-in,
/// sign-out, or a 401 refresh/clear), so a stale response can never repaint a previous
/// account's identity over a signed-out or switched session.
@MainActor
final class AccountSessionModel: ObservableObject, SessionScoped {
    typealias AccountReader = () async throws -> AccountSummary
    /// Hands an external URL to the screen's `@Environment(\.openURL)` action.
    typealias ExternalOpener = (URL) -> Void

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
    /// sign-out, 401) or it silently goes stale. Every transition that matters republishes
    /// `state`, which is what re-renders the card.
    var hasSignedInBefore: Bool { signInHistory.hasSignedInBefore }
    @Published private(set) var isAuthenticating = false
    @Published private(set) var authError: String?

    /// Sign-out is the account-switching affordance on this screen. It is local, so it stays
    /// available in every signed-in state, offline included.
    var isSignOutAvailable: Bool {
        if case .signedIn = state { return true }
        return false
    }

    /// The deletion request belongs to an account, so it is only offered once one is projected.
    /// The deletion itself happens outside the app: the row opens an external request form, which
    /// cannot be filled in without a connection — so an offline row is shown disabled with its
    /// reason instead of sending the user to a browser that will fail.
    var isAccountDeletionRequestAvailable: Bool {
        guard !isOffline else { return false }
        if case .signedIn = state { return true }
        return false
    }

    /// Why the deletion row cannot be used right now, for the row's own second line (`nil` when the
    /// row is usable, so the reason cannot drift from the availability rule).
    var accountDeletionUnavailableReason: String? {
        guard case .signedIn = state else { return nil }
        return isOffline ? Self.offlineDeletionReason : nil
    }

    static let offlineDeletionReason = "Connect to the internet to delete"

    /// The email and sign-in method this device's session proves (see `AccountIdentity`).
    @Published private(set) var identity = AccountIdentity.unknown

    /// The Account that was projected last. Kept so losing the network mid-session shows the identity
    /// the user already saw (marked as cached) instead of an error about a screen that has content.
    private(set) var cachedAccount: AccountSummary?

    /// `true` while the shipped identity came off `cachedAccount` instead of a live read.
    @Published private(set) var isShowingCachedDetails = false

    /// Network state. Driven by `connectivity` when one is injected; `false` otherwise, so a unit test
    /// that does not care about reachability is deterministic.
    @Published private(set) var isOffline = false

    /// The form the "Delete account" row opens. `nil` only if the destination itself is unusable,
    /// which `SupportDestinationsTests` guards at build/QA time.
    static var deleteAccountRequestURL: URL? { SupportDestinations.deleteAccountURL }

    private let boundary: SessionBoundary
    private let readAccount: AccountReader
    private let signInAction: SignInAction
    private let scope: SessionScope
    /// Read-only here: `SessionBoundary` is the only writer of the install's sign-in history.
    private let signInHistory: SignInHistoryRecording
    private let connectivity: (any AccountConnectivityMonitoring)?
    /// Local request token: a newer refresh supersedes the read before it. Session staleness is the
    /// scope's job (a ticket), this one is only "which read is the latest".
    private var refreshGeneration: UInt64 = 0

    init(
        boundary: SessionBoundary = ServiceLocator.sessionBoundary,
        readAccount: @escaping AccountReader = {
            try await ServiceLocator.makePoseAPIService().getCurrentAccount()
        },
        signInAction: SignInAction = SignInAction(),
        signInHistory: SignInHistoryRecording = UserDefaultsSignInHistory.shared,
        connectivity: (any AccountConnectivityMonitoring)? = nil
    ) {
        self.boundary = boundary
        self.readAccount = readAccount
        self.signInAction = signInAction
        self.signInHistory = signInHistory
        self.connectivity = connectivity
        self.scope = SessionScope.of(boundary)
        scope.adopt(self)
    }

    /// Starts the projection of the stored session. The session subscription belongs to the scope.
    func start() {
        startConnectivity()
        refresh()
    }

    /// Releases the reachability monitor; the session subscription belongs to the scope.
    func stop() {
        connectivity?.stop()
        connectivity?.onChange = nil
    }

    /// Reachability readings land here. The screen never writes `isOffline` directly, so the delete
    /// row's availability and its reason always read the same value.
    func setOffline(_ offline: Bool) {
        guard isOffline != offline else { return }
        isOffline = offline
        // Going offline while a read already failed: the identity the user saw before is the cached
        // detail the board's offline state shows, not the error.
        if offline, case .failed = state, let cached = cachedAccount {
            state = .signedIn(cached)
            isShowingCachedDetails = true
        }
    }

    func refresh() {
        let request = beginRefresh()
        Task { [weak self] in
            guard let self else { return }
            let ticket = await self.scope.beginRequest()
            guard await self.boundary.hasStoredSession() else {
                if await self.isCurrent(request, ticket) {
                    self.clearProjection()
                    self.state = .signedOut
                }
                return
            }
            guard await self.isCurrent(request, ticket) else { return }
            self.state = .loading
            await self.readIdentity()
            do {
                let account = try await self.readAccount()
                guard await self.isCurrent(request, ticket) else { return }
                if await self.boundary.hasStoredSession() {
                    self.project(account)
                } else {
                    self.clearProjection()
                    self.state = .signedOut
                }
            } catch {
                guard await self.isCurrent(request, ticket) else { return }
                if let apiError = error as? PoseAPIError, apiError.isUnauthorized {
                    // 401 is never an empty/failed account: it is a signed-out session.
                    self.clearProjection()
                    self.state = .signedOut
                } else if Self.isConnectivityFailure(error), let cached = self.cachedAccount {
                    // No network is not "this account is broken": the identity already read on this
                    // device is the truth the offline board shows, marked as cached.
                    self.state = .signedIn(cached)
                    self.isShowingCachedDetails = true
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
            // The scope's `.signedOut` reset lands a turn later; dropping the identity here as well
            // keeps the sign-out synchronous for everything the screen draws.
            self.clearProjection()
            self.state = .signedOut
        }
    }

    /// Opens the external account-deletion *request* form.
    ///
    /// The app deletes nothing: App Review 5.1.1(v) is satisfied by an in-app entry point that
    /// reaches a real deletion path, and the user asks for it in this form. So the only side effect
    /// here is one hand-off to the opener the screen injects (`@Environment(\.openURL)`) — no
    /// request, no session change, no local wipe. A signed-out or failed projection is declined: a
    /// request about an account needs an account.
    ///
    /// - Returns: the URL that was opened, or `nil` when nothing was handed over.
    @discardableResult
    func openAccountDeletionRequest(_ openURL: ExternalOpener) -> URL? {
        guard isAccountDeletionRequestAvailable, let url = Self.deleteAccountRequestURL else { return nil }
        openURL(url)
        return url
    }

    // MARK: - session changes

    /// Credentials changed: discard whatever the previous session was reading, then re-project.
    /// Called synchronously by the scope in the same turn as the generation bump.
    func resetForSessionChange(_ event: SessionEvent) {
        switch event {
        case .signedIn:
            beginRefresh()
            // A new session's identity is not the previous one's, cached or otherwise.
            clearProjection()
            state = .loading
            refresh()
        case .signedOut, .signInRequired:
            beginRefresh()
            clearProjection()
            state = .signedOut
        }
    }

    // MARK: - projection

    private func startConnectivity() {
        guard let connectivity else { return }
        connectivity.onChange = { [weak self] offline in self?.setOffline(offline) }
        connectivity.start()
    }

    /// The identity the stored token proves. Read on every projection so a switched session cannot
    /// keep the previous account's address.
    private func readIdentity() async {
        let token = await boundary.loadAccessToken()
        identity = SessionTokenClaims.identity(fromAccessToken: token ?? "")
    }

    private func project(_ account: AccountSummary) {
        cachedAccount = account
        isShowingCachedDetails = false
        state = .signedIn(account)
    }

    /// Anything that ends the session drops the cached identity with it (FEAT-014: no stale
    /// protected state after a context change).
    private func clearProjection() {
        cachedAccount = nil
        isShowingCachedDetails = false
        identity = .unknown
    }

    /// "The device could not reach the service", as opposed to "the service answered with a failure".
    static func isConnectivityFailure(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
             .dataNotAllowed, .internationalRoamingOff, .timedOut:
            return true
        default:
            return false
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
}
