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

/// Counts reads without tripping Swift 6's concurrent-mutation diagnostics.
private final class ReadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

private let storedCredentials = SessionCredentials(accessToken: "access", refreshToken: "refresh")

private func account(name: String = "Gmail") -> AccountSummary {
    AccountSummary(id: "google-sub-1", displayName: name, createdAt: "2026-09-01T00:00:00.000Z")
}

/// Records the install's sign-in history in memory. Every test builds its own, so nothing leans on
/// `UserDefaults` or on test order.
private final class FakeSignInHistory: SignInHistoryRecording, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: Bool

    init(hasSignedInBefore: Bool = false) {
        recorded = hasSignedInBefore
    }

    var hasSignedInBefore: Bool {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func recordSignedIn() {
        lock.lock()
        recorded = true
        lock.unlock()
    }
}

@MainActor
final class AccountSessionTests: XCTestCase {
    private func makeModel(
        storage: InMemoryTokenStorage,
        history: FakeSignInHistory = FakeSignInHistory(),
        reader: @escaping AccountSessionModel.AccountReader,
        signIn: @escaping SignInAction.Starter = {}
    ) -> (AccountSessionModel, SessionBoundary) {
        let boundary = SessionBoundary(tokenStorage: storage, signInHistory: history)
        let model = AccountSessionModel(
            boundary: boundary,
            readAccount: reader,
            signInAction: SignInAction(start: signIn),
            signInHistory: history
        )
        return (model, boundary)
    }

    func testNoStoredSessionProjectsSignedOutWithoutReadingAccount() async {
        let counter = ReadCounter()
        let (model, _) = makeModel(
            storage: InMemoryTokenStorage(),
            reader: { counter.increment(); return account() }
        )

        model.start()
        await waitUntil("signed out") { model.state == .signedOut }
        XCTAssertEqual(counter.value, 0, "A guest must not hit the protected account endpoint")
    }

    // MARK: - BUG-261029-03: never signed in is not "signed out"

    /// A fresh install that never signed in must not be told to "sign in again": there is no earlier
    /// session on this device to return to.
    func testFreshInstallThatNeverSignedInGetsNeutralSignInCopy() async {
        let (model, _) = makeModel(storage: InMemoryTokenStorage(), reader: { account() })

        model.start()
        await waitUntil("signed out") { model.state == .signedOut }

        XCTAssertFalse(model.hasSignedInBefore, "Nothing was ever signed in on this install")
        let card = AccountStateCopy.signInCard(hasSignedInBefore: model.hasSignedInBefore)
        XCTAssertEqual(card.title, "Not signed in")
        XCTAssertEqual(card.message, "Sign in to save poses.")
        XCTAssertFalse(card.message.lowercased().contains("again"))
    }

    /// A session that really ended on this install keeps the prototype's sign-out wording.
    func testSessionThatEndedOnThisInstallKeepsSignedOutCopy() async {
        let (model, _) = makeModel(
            storage: InMemoryTokenStorage(),
            history: FakeSignInHistory(hasSignedInBefore: true),
            reader: { account() }
        )

        model.start()
        await waitUntil("signed out") { model.state == .signedOut }

        XCTAssertTrue(model.hasSignedInBefore)
        let card = AccountStateCopy.signInCard(hasSignedInBefore: model.hasSignedInBefore)
        XCTAssertEqual(card.title, "Signed out")
        XCTAssertEqual(card.message, "Sign in again to access your Saved poses.")
    }

    /// The realistic sequence for the bug: brand-new account signs in, then signs out. The card must
    /// have flipped from neutral copy to the "again" variant because the sign-in really happened.
    func testSignInThenSignOutSwitchesTheCardToTheSignedOutVariant() async {
        let storage = InMemoryTokenStorage()
        let history = FakeSignInHistory()
        let boundary = SessionBoundary(tokenStorage: storage, signInHistory: history)
        let model = AccountSessionModel(
            boundary: boundary,
            readAccount: { account(name: "Fresh Account") },
            signInAction: SignInAction(start: { await boundary.saveCredentials(storedCredentials) }),
            signInHistory: history
        )

        model.start()
        await waitUntil("signed out") { model.state == .signedOut }
        XCTAssertFalse(model.hasSignedInBefore)
        XCTAssertEqual(
            AccountStateCopy.signInCard(hasSignedInBefore: model.hasSignedInBefore).title,
            "Not signed in"
        )

        model.signIn()
        await waitUntil("signed in") { model.state == .signedIn(account(name: "Fresh Account")) }
        XCTAssertTrue(model.hasSignedInBefore, "A completed sign-in is install history")

        model.signOut()
        await waitUntil("signed out again") { model.state == .signedOut }
        XCTAssertTrue(model.hasSignedInBefore)
        XCTAssertEqual(
            AccountStateCopy.signInCard(hasSignedInBefore: model.hasSignedInBefore).message,
            "Sign in again to access your Saved poses."
        )
    }

    /// A 401 is a session that ended, never a first visit: the wording must follow the history, not
    /// the transition that produced `.signedOut`.
    func testUnauthorizedClearAfterASignInKeepsSignedOutCopy() async {
        let storage = InMemoryTokenStorage(credentials: storedCredentials)
        let history = FakeSignInHistory()
        let boundary = SessionBoundary(tokenStorage: storage, signInHistory: history)
        let model = AccountSessionModel(
            boundary: boundary,
            readAccount: { account() },
            signInHistory: history
        )

        model.start()
        await waitUntil("signed in") { model.state == .signedIn(account()) }
        await boundary.clearForUnauthorized()

        await waitUntil("signed out") { model.state == .signedOut }
        XCTAssertTrue(model.hasSignedInBefore, "An expired session still happened on this install")
    }

    func testStoredSessionLoadsRealIdentity() async {
        let (model, _) = makeModel(
            storage: InMemoryTokenStorage(credentials: storedCredentials),
            reader: { account(name: "Phong Tran") }
        )

        model.start()
        await waitUntil("signed in") { model.state == .signedIn(account(name: "Phong Tran")) }
        guard case .signedIn(let summary) = model.state else { return XCTFail("Expected signedIn") }
        XCTAssertEqual(summary.displayName, "Phong Tran")
        XCTAssertEqual(summary.id, "google-sub-1")
    }

    func testUnauthorizedReadProjectsSignedOutInsteadOfError() async {
        let (model, _) = makeModel(
            storage: InMemoryTokenStorage(credentials: storedCredentials),
            reader: { throw PoseAPIError(code: "401", message: "Unauthorized") }
        )

        model.start()
        await waitUntil("signed out") { model.state == .signedOut }
    }

    func testNonUnauthorizedFailureSurfacesServerMessage() async {
        let (model, _) = makeModel(
            storage: InMemoryTokenStorage(credentials: storedCredentials),
            reader: { throw PoseAPIError(code: "500", message: "Server error: 500") }
        )

        model.start()
        await waitUntil("failed") { model.state == .failed("Server error: 500") }
    }

    func testRetryReloadsAfterFailure() async {
        let counter = ReadCounter()
        let (model, _) = makeModel(
            storage: InMemoryTokenStorage(credentials: storedCredentials),
            reader: {
                counter.increment()
                if counter.value == 1 { throw PoseAPIError(code: "503", message: "Temporarily unavailable") }
                return account(name: "Retried")
            }
        )

        model.start()
        await waitUntil("failed") { model.state == .failed("Temporarily unavailable") }
        model.retry()
        await waitUntil("signed in after retry") { model.state == .signedIn(account(name: "Retried")) }
    }

    func testSignOutClearsCredentialsAndProjectsSignedOut() async {
        let storage = InMemoryTokenStorage(credentials: storedCredentials)
        let (model, _) = makeModel(storage: storage, reader: { account() })

        model.start()
        await waitUntil("signed in") { model.state == .signedIn(account()) }
        model.signOut()

        await waitUntil("signed out") { model.state == .signedOut }
        XCTAssertNil(storage.loadCredentials(), "Sign-out must clear the local session")
    }

    func testSignInFailureSurfacesPromptErrorAndStaysSignedOut() async {
        let (model, _) = makeModel(
            storage: InMemoryTokenStorage(),
            reader: { account() },
            signIn: { throw OAuthCallbackError.invalidCallback }
        )

        model.start()
        await waitUntil("signed out") { model.state == .signedOut }
        model.signIn()

        await waitUntil("auth error") { model.authError != nil }
        XCTAssertEqual(model.authError, "Unable to start Google sign-in.")
        XCTAssertEqual(model.state, .signedOut)
        XCTAssertFalse(model.isAuthenticating)
    }

    func testSignInSuccessLoadsAccountThroughSessionEvent() async {
        let storage = InMemoryTokenStorage()
        let history = FakeSignInHistory()
        let boundary = SessionBoundary(tokenStorage: storage, signInHistory: history)
        let model = AccountSessionModel(
            boundary: boundary,
            readAccount: { account(name: "Signed In") },
            signInAction: SignInAction(start: { await boundary.saveCredentials(storedCredentials) }),
            signInHistory: history
        )

        model.start()
        await waitUntil("signed out") { model.state == .signedOut }
        model.signIn()

        await waitUntil("signed in") { model.state == .signedIn(account(name: "Signed In")) }
        XCTAssertNil(model.authError)
        XCTAssertFalse(model.isAuthenticating)
        XCTAssertNotNil(storage.loadCredentials())
    }

    func testCancelledSignInIsNotReportedAsFailure() async {
        let (model, _) = makeModel(
            storage: InMemoryTokenStorage(),
            reader: { account() },
            signIn: { throw CancellationError() }
        )

        model.start()
        await waitUntil("signed out") { model.state == .signedOut }
        model.signIn()
        await waitUntil("authentication settles") { !model.isAuthenticating }

        XCTAssertNil(model.authError, "\"Not now\"/dismiss must not look like a failure")
        XCTAssertEqual(model.state, .signedOut)
    }

    /// A 401 handled elsewhere clears the boundary; an open Account screen must follow
    /// without a second manual refresh (FEAT-014 E1 — no stale identity after expiry).
    func testUnauthorizedClearFromAnotherOwnerProjectsSignedOut() async {
        let storage = InMemoryTokenStorage(credentials: storedCredentials)
        let (model, boundary) = makeModel(storage: storage, reader: { account() })

        model.start()
        await waitUntil("signed in") { model.state == .signedIn(account()) }
        await boundary.clearForUnauthorized()

        await waitUntil("signed out") { model.state == .signedOut }
    }

    /// Credentials stored by another owner (e.g. the OAuth handoff) must repaint the screen.
    func testSignedInEventFromAnotherOwnerReloadsAccount() async {
        let (model, boundary) = makeModel(
            storage: InMemoryTokenStorage(),
            reader: { account(name: "External Sign In") }
        )

        model.start()
        await waitUntil("signed out") { model.state == .signedOut }
        await boundary.saveCredentials(storedCredentials)

        await waitUntil("signed in") { model.state == .signedIn(account(name: "External Sign In")) }
    }

    // MARK: - helpers

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 3,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(condition(), "Timed out waiting for \(description)", file: file, line: line)
    }
}

// MARK: - Build-17 support surface: identity claims, offline details, plan truth, hub rules

/// Counts reachability readings so a test can prove the model wired the monitor it was given.
@MainActor
private final class FakeConnectivity: AccountConnectivityMonitoring {
    var onChange: ((Bool) -> Void)?
    private(set) var isStarted = false

    func start() { isStarted = true }
    func stop() { isStarted = false }

    func emit(isOffline: Bool) { onChange?(isOffline) }
}

/// The Account screen's identity, plan and offline behaviour, plus the Settings hub's pure copy
/// rules. Everything here is a claim the app makes to the user, so each one is asserted against the
/// real input that produces it — never against a screenshot.
@MainActor
final class AccountSupportSurfaceTests: XCTestCase {
    // MARK: - Session claims → AccountIdentity

    func testIdentityReadsTheEmailAndProviderTheTokenCarries() {
        let apple = SessionTokenClaims.identity(fromAccessToken: Self.token(
            email: "maya@example.com",
            provider: "apple"
        ))
        XCTAssertEqual(apple.email, "maya@example.com")
        XCTAssertEqual(apple.signInMethod, "Apple")

        XCTAssertEqual(
            SessionTokenClaims.identity(fromAccessToken: Self.token(email: "maya@example.com", provider: "google")).signInMethod,
            "Google"
        )
        XCTAssertEqual(
            SessionTokenClaims.identity(fromAccessToken: Self.token(email: "maya@example.com", provider: "email")).signInMethod,
            "Email"
        )
    }

    /// Supabase puts password sign-in in `amr`, not in `app_metadata.provider`; both are read.
    func testPasswordSignInIsReadFromTheAuthenticationMethodsList() {
        let token = Self.token(payload: [
            "email": "maya@example.com",
            "amr": [["method": "password"]]
        ])
        XCTAssertEqual(SessionTokenClaims.identity(fromAccessToken: token).signInMethod, "Email")
    }

    /// An opaque token (or a provider the app cannot name) proves nothing, so nothing is rendered as
    /// if it did. This is what keeps the Profile rows from inventing an address.
    func testUnprovableIdentityIsEmptyInsteadOfInvented() {
        XCTAssertEqual(SessionTokenClaims.identity(fromAccessToken: "access"), .unknown)
        XCTAssertEqual(SessionTokenClaims.identity(fromAccessToken: ""), .unknown)
        XCTAssertEqual(SessionTokenClaims.identity(fromAccessToken: "a.!!!.c"), .unknown)
        XCTAssertTrue(SessionTokenClaims.identity(fromAccessToken: "access").isEmpty)

        let unknownProvider = SessionTokenClaims.identity(fromAccessToken: Self.token(
            email: "maya@example.com",
            provider: "saml"
        ))
        XCTAssertNil(unknownProvider.signInMethod, "an unnameable provider is hidden, never labelled \"Other\"")
        XCTAssertEqual(unknownProvider.email, "maya@example.com")

        let notAnAddress = SessionTokenClaims.identity(fromAccessToken: Self.token(email: "maya", provider: "email"))
        XCTAssertNil(notAnAddress.email, "a value that is not an address is not shown as one")
    }

    func testAvatarInitialsUseAtMostTwoWords() {
        XCTAssertEqual(AccountAvatar.initials(for: "Maya Pham"), "MP")
        XCTAssertEqual(AccountAvatar.initials(for: "maya pham nguyen"), "MP")
        XCTAssertEqual(AccountAvatar.initials(for: "Phong"), "P")
        XCTAssertEqual(AccountAvatar.initials(for: ""), "")
        XCTAssertEqual(AccountAvatar.initials(for: "   "), "")
    }

    // MARK: - Offline (board 10-09 / TC-ACC-013)

    func testOfflineDisablesTheDeletionRowAndKeepsSignOutAvailable() async {
        let connectivity = FakeConnectivity()
        let storage = InMemoryTokenStorage(credentials: storedCredentials)
        let boundary = SessionBoundary(tokenStorage: storage)
        let model = AccountSessionModel(
            boundary: boundary,
            readAccount: { account() },
            signInHistory: FakeSignInHistory(hasSignedInBefore: true),
            connectivity: connectivity
        )

        model.start()
        XCTAssertTrue(connectivity.isStarted, "the screen's monitor is what decides the offline state")
        await waitUntil("signed in") { model.state == .signedIn(account()) }
        XCTAssertTrue(model.isAccountDeletionRequestAvailable)
        XCTAssertNil(model.accountDeletionUnavailableReason)

        connectivity.emit(isOffline: true)
        await waitUntil("offline") { model.isOffline }

        XCTAssertFalse(
            model.isAccountDeletionRequestAvailable,
            "the deletion form cannot be filled in without a connection"
        )
        XCTAssertEqual(model.accountDeletionUnavailableReason, "Connect to the internet to delete")
        XCTAssertTrue(model.isSignOutAvailable, "signing out is local, so it stays available")

        var opened: [URL] = []
        XCTAssertNil(
            model.openAccountDeletionRequest { opened.append($0) },
            "an offline tap must not send the user to a form that cannot load"
        )
        XCTAssertTrue(opened.isEmpty)

        model.stop()
        XCTAssertFalse(connectivity.isStarted, "the monitor does not outlive the screen")
    }

    /// A failed read while the device has no network is not an error screen: the identity already on
    /// this device is what the offline board shows.
    func testOfflineReadFailureKeepsTheAlreadyProjectedIdentity() async {
        let connectivity = FakeConnectivity()
        let storage = InMemoryTokenStorage(credentials: storedCredentials)
        let reads = ReadCounter()
        let model = AccountSessionModel(
            boundary: SessionBoundary(tokenStorage: storage),
            readAccount: {
                reads.increment()
                if reads.value > 1 { throw URLError(.notConnectedToInternet) }
                return account(name: "Maya Pham")
            },
            signInHistory: FakeSignInHistory(hasSignedInBefore: true),
            connectivity: connectivity
        )
        model.start()
        await waitUntil("signed in") { model.state == .signedIn(account(name: "Maya Pham")) }

        connectivity.emit(isOffline: true)
        model.retry()

        await waitUntil("cached details") { model.isShowingCachedDetails }
        XCTAssertEqual(model.state, .signedIn(account(name: "Maya Pham")))
        XCTAssertTrue(model.isOffline)
        XCTAssertFalse(model.isAccountDeletionRequestAvailable)
    }

    /// The same network failure *without* a previous read is a real error state, not an empty screen.
    func testOfflineFailureWithoutCachedIdentityIsTheErrorState() async {
        let model = AccountSessionModel(
            boundary: SessionBoundary(tokenStorage: InMemoryTokenStorage(credentials: storedCredentials)),
            readAccount: { throw URLError(.notConnectedToInternet) },
            signInHistory: FakeSignInHistory(hasSignedInBefore: true)
        )
        model.start()
        await waitUntil("failed") { if case .failed = model.state { return true }; return false }
        XCTAssertFalse(model.isShowingCachedDetails)
    }

    // MARK: - Session changes drop the identity

    func testSignOutDropsTheCachedIdentityAndTheClaims() async {
        let storage = InMemoryTokenStorage(credentials: SessionCredentials(
            accessToken: Self.token(email: "maya@example.com", provider: "apple"),
            refreshToken: "refresh"
        ))
        let model = AccountSessionModel(
            boundary: SessionBoundary(tokenStorage: storage),
            readAccount: { account(name: "Maya Pham") },
            signInHistory: FakeSignInHistory(hasSignedInBefore: true)
        )
        model.start()
        await waitUntil("signed in") { model.state == .signedIn(account(name: "Maya Pham")) }
        XCTAssertEqual(model.identity.email, "maya@example.com")

        model.signOut()
        await waitUntil("signed out") { model.state == .signedOut }

        XCTAssertEqual(model.identity, .unknown, "no previous account's address survives a sign-out")
        XCTAssertNil(model.cachedAccount)
        XCTAssertFalse(model.isShowingCachedDetails)
    }

    // MARK: - Premium plan (board 10-05 / TC-ACC-014)

    func testPlanIsClaimedOnlyFromAConfirmedEntitlement() {
        XCTAssertEqual(AccountPremiumStatus.resolve(entitlement: .entitled, isSignedIn: true), .active)
        XCTAssertEqual(AccountPremiumStatus.resolve(entitlement: .entitled, isSignedIn: false), .notSubscribed,
                       "an entitlement with no session is not this user's plan")

        for state in [PurchaseGatewayState.notEntitled, .billingRetry, .expired, .revoked, .unconfigured] {
            XCTAssertEqual(AccountPremiumStatus.resolve(entitlement: state, isSignedIn: true), .notSubscribed,
                           "\(state.rawValue) is a confirmed negative")
        }
        for state in [PurchaseGatewayState.loading, .noOffering, .purchasePending, .purchaseCancelled,
                      .purchaseFailed, .signInRequired] {
            XCTAssertEqual(AccountPremiumStatus.resolve(entitlement: state, isSignedIn: true), .unknown,
                           "\(state.rawValue) proves nothing about access, so no plan is shown")
        }
        let everyState: [PurchaseGatewayState] = [
            .loading, .unconfigured, .noOffering, .notEntitled, .entitled, .purchasePending,
            .purchaseCancelled, .purchaseFailed, .billingRetry, .expired, .revoked, .signInRequired
        ]
        for state in everyState {
            XCTAssertEqual(
                AccountPremiumStatus.resolve(entitlement: state, isSignedIn: false),
                .notSubscribed,
                "signed out, \(state.rawValue) is never a plan"
            )
        }
    }

    func testOnlyAnActivePlanShowsAPlanValueAndManageSubscription() {
        XCTAssertEqual(AccountPremiumStatus.active.planValue, "Premium")
        XCTAssertEqual(AccountPremiumStatus.active.badge, "Active")
        XCTAssertTrue(AccountPremiumStatus.active.showsManageSubscription)

        XCTAssertEqual(AccountPremiumStatus.notSubscribed.planValue, "Not subscribed")
        XCTAssertNil(AccountPremiumStatus.notSubscribed.badge, "only a live entitlement may say Active")
        XCTAssertFalse(AccountPremiumStatus.notSubscribed.showsManageSubscription)

        XCTAssertNil(AccountPremiumStatus.unknown.planValue)
        XCTAssertNil(AccountPremiumStatus.unknown.badge)
        XCTAssertFalse(AccountPremiumStatus.unknown.showsManageSubscription)
    }

    func testSubscriptionManagementOpensTheAppStorePage() throws {
        XCTAssertEqual(
            SubscriptionManagement.appStoreSubscriptions,
            "https://apps.apple.com/account/subscriptions"
        )
        let url = try XCTUnwrap(SubscriptionManagement.appStoreSubscriptionsURL)
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "apps.apple.com")
    }

    // MARK: - Settings hub rules (boards 10-01 / 10-02)

    func testSystemCaptionOnlyExplainsSystem() {
        XCTAssertEqual(SettingsHub.appearanceCaption(for: .system), "System follows your iPhone setting.")
        XCTAssertNil(SettingsHub.appearanceCaption(for: .light), "it must not claim to follow the phone under Light")
        XCTAssertNil(SettingsHub.appearanceCaption(for: .dark))
    }

    func testSignedOutHubCopyPromisesOnlyWhatExists() {
        XCTAssertEqual(SettingsHub.savedValue(isSignedIn: false), "Sign in to view")
        XCTAssertNil(SettingsHub.savedValue(isSignedIn: true))
        XCTAssertEqual(SettingsHub.signInTitle(appName: "posing"), "Sign in to posing")
        XCTAssertEqual(
            SettingsHub.signInMessage,
            "Keep your Saved poses with you and use Premium on every device."
        )
        // Premium unlocks the shutter only: the hub's copy must not promise anything else.
        XCTAssertFalse(SettingsHub.signInMessage.lowercased().contains("unlimited"))
    }

    func testPremiumRowLabelCarriesTheSameStatusAsTheBadge() {
        XCTAssertEqual(SettingsHub.premiumLabel(.active), "Premium, active. Opens premium")
        XCTAssertEqual(SettingsHub.premiumLabel(.notSubscribed), "Premium, not subscribed. Opens premium")
        XCTAssertEqual(SettingsHub.premiumLabel(.unknown), "Premium. Opens premium")
    }

    // MARK: - About → licences (board 10-12)

    func testLicenceListNamesTheDependenciesTheBuildLinks() {
        let licences = OpenSourceLicence.all
        XCTAssertEqual(licences.map(\.name), [
            "Firebase iOS SDK",
            "RevenueCat purchases-ios",
            "GRDB.swift",
            "Kingfisher"
        ])
        XCTAssertEqual(Set(licences.map(\.id)).count, licences.count, "ids stay unique")
        for licence in licences {
            XCTAssertFalse(licence.licence.isEmpty, "\(licence.name) names the licence it publishes")
            XCTAssertEqual(licence.url?.scheme, "https", "\(licence.name) links to a real https licence page")
            XCTAssertNotNil(licence.url?.host)
        }
    }

    // MARK: - helpers

    /// A JWT-shaped token whose middle segment is `claims`. Nothing here is signed: the app only
    /// projects claims from a token the server already verified.
    static func token(email: String?, provider: String?) -> String {
        var payload: [String: Any] = [:]
        if let email { payload["email"] = email }
        if let provider { payload["app_metadata"] = ["provider": provider] }
        return token(payload: payload)
    }

    static func token(payload: [String: Any]) -> String {
        func encode(_ string: String) -> String {
            Data(string.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        let header = encode(#"{"alg":"ES256","typ":"JWT"}"#)
        let body = (try? JSONSerialization.data(withJSONObject: payload))
            .map { encode(String(decoding: $0, as: UTF8.self)) } ?? encode("{}")
        return "\(header).\(body).signature"
    }

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 3,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(condition(), "Timed out waiting for \(description)", file: file, line: line)
    }
}
