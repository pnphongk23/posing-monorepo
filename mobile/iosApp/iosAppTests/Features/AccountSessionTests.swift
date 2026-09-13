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

@MainActor
final class AccountSessionTests: XCTestCase {
    private func makeModel(
        storage: InMemoryTokenStorage,
        reader: @escaping AccountSessionModel.AccountReader,
        signIn: @escaping SignInAction.Starter = {}
    ) -> (AccountSessionModel, SessionBoundary) {
        let boundary = SessionBoundary(tokenStorage: storage)
        let model = AccountSessionModel(
            boundary: boundary,
            readAccount: reader,
            signInAction: SignInAction(start: signIn)
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
        let boundary = SessionBoundary(tokenStorage: storage)
        let model = AccountSessionModel(
            boundary: boundary,
            readAccount: { account(name: "Signed In") },
            signInAction: SignInAction(start: { await boundary.saveCredentials(storedCredentials) })
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
