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

private let storedCredentials = SessionCredentials(accessToken: "access", refreshToken: "refresh")

@MainActor
final class SignInPromptModelTests: XCTestCase {
    func testSuccessReportsTrueOnceAndLeavesNoError() async {
        let model = SignInPromptModel(signInAction: SignInAction(start: {}))

        let succeeded = await model.continueWithGoogle()
        XCTAssertTrue(succeeded)
        XCTAssertNil(model.error)
        XCTAssertFalse(model.isAuthenticating)
    }

    /// Dismissing the web sheet is not a failure: nothing changed, so nothing is reported.
    func testCancellationReportsFalseWithoutAnError() async {
        let model = SignInPromptModel(signInAction: SignInAction(start: { throw CancellationError() }))

        let succeeded = await model.continueWithGoogle()
        XCTAssertFalse(succeeded)
        XCTAssertNil(model.error)
        XCTAssertFalse(model.isAuthenticating)
    }

    func testFailureUsesTheLauncherMessage() async {
        let model = SignInPromptModel(signInAction: SignInAction(start: { throw OAuthCallbackError.invalidCallback }))

        let succeeded = await model.continueWithGoogle()
        XCTAssertFalse(succeeded)
        XCTAssertEqual(model.error, "Unable to start Google sign-in.")
        XCTAssertFalse(model.isAuthenticating)
    }

    func testProviderDenialSurfacesTheProviderDetail() async {
        let model = SignInPromptModel(
            signInAction: SignInAction(start: { throw OAuthCallbackError.providerDenied("access_denied") })
        )
        _ = await model.continueWithGoogle()
        XCTAssertEqual(model.error, "Google sign-in failed: access_denied")
    }

    func testClearErrorResetsThePromptCopy() async {
        let model = SignInPromptModel(signInAction: SignInAction(start: { throw OAuthCallbackError.missingCode }))
        _ = await model.continueWithGoogle()
        XCTAssertNotNil(model.error)

        model.clearError()
        XCTAssertNil(model.error)
    }

    /// A second tap while the handoff is in flight must not start a second launcher.
    func testConcurrentTapsStartOneHandoff() async {
        let counter = Counter()
        let model = SignInPromptModel(
            signInAction: SignInAction(start: {
                counter.increment()
                try await Task.sleep(nanoseconds: 60_000_000)
            })
        )

        async let first = model.continueWithGoogle()
        try? await Task.sleep(nanoseconds: 10_000_000)
        async let second = model.continueWithGoogle()
        let results = await [first, second]

        XCTAssertEqual(counter.value, 1)
        XCTAssertEqual(results.filter { $0 }.count, 1, "Exactly one caller owns the successful handoff")
    }
}

final class ErrorCopyTests: XCTestCase {
    func testUsesTheServerMessageForAPIErrors() {
        XCTAssertEqual(
            ErrorCopy.text(for: PoseAPIError(code: "401", message: "Unauthorized")),
            "Unauthorized"
        )
    }

    func testUsesLocalizedErrorDescription() {
        XCTAssertEqual(ErrorCopy.text(for: OAuthCallbackError.missingCode), "Google sign-in returned an invalid callback.")
    }

    func testFallsBackToNilForASilentError() {
        struct Silent: Error {}
        XCTAssertNil(
            ErrorCopy.text(for: Silent()),
            "A plain Swift error must not surface the 'operation couldn't be completed' narration"
        )
    }

    func testUsesTheURLErrorDescriptionForOfflineFailures() {
        XCTAssertEqual(ErrorCopy.text(for: URLError(.timedOut)), URLError(.timedOut).localizedDescription)
    }
}

final class SignInIntentTests: XCTestCase {
    /// Copy matrix from the prototype `scripts/sign-in-prompt.js`.
    func testPromptCopyWithMatchesThePrototype() {
        XCTAssertEqual(SignInIntent.openSaved.promptCopy, "View your saved poses.")
        XCTAssertEqual(SignInIntent.savePose.promptCopy, "Save this pose.")
        XCTAssertEqual(SignInIntent.tryPose.promptCopy, "Try this pose.")
        XCTAssertEqual(SignInIntent.openAccount.promptCopy, "Manage your account.")
    }
}

@MainActor
final class SessionPresenceModelTests: XCTestCase {
    func testStartsSignedOutWithoutCredentials() async {
        let model = SessionPresenceModel(boundary: SessionBoundary(tokenStorage: InMemoryTokenStorage()))
        model.start()
        await waitUntil("resolved") { model.isResolved }
        XCTAssertFalse(model.isSignedIn)
    }

    func testStartsSignedInWithStoredCredentials() async {
        let storage = InMemoryTokenStorage(credentials: storedCredentials)
        let model = SessionPresenceModel(boundary: SessionBoundary(tokenStorage: storage))
        model.start()
        await waitUntil("signed in") { model.isSignedIn }
        XCTAssertTrue(model.isSignedIn)
    }

    func testFollowsSignInAndSignOutEvents() async {
        let storage = InMemoryTokenStorage()
        let boundary = SessionBoundary(tokenStorage: storage)
        let model = SessionPresenceModel(boundary: boundary)

        model.start()
        await waitUntil("resolved") { model.isResolved }
        XCTAssertFalse(model.isSignedIn)

        await boundary.saveCredentials(storedCredentials)
        await waitUntil("signed in") { model.isSignedIn }

        await boundary.signOut()
        await waitUntil("signed out") { !model.isSignedIn }
    }

    /// A 401 refresh failure clears the boundary; protected content must unmount.
    func testFollowsUnauthorizedClear() async {
        let storage = InMemoryTokenStorage(credentials: storedCredentials)
        let boundary = SessionBoundary(tokenStorage: storage)
        let model = SessionPresenceModel(boundary: boundary)

        model.start()
        await waitUntil("signed in") { model.isSignedIn }

        await boundary.clearForUnauthorized()
        await waitUntil("signed out") { !model.isSignedIn }
    }

    @MainActor
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

private final class Counter: @unchecked Sendable {
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
