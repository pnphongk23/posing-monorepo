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

final class AuthErrorCopyTests: XCTestCase {
    /// One message for unknown email AND wrong password — anti-enumeration is frozen copy.
    func testInvalidCredentialsUsesTheFrozenCopy() {
        XCTAssertEqual(
            AuthErrorCopy.text(for: PoseAPIError(code: "INVALID_CREDENTIALS", message: "anything"), fallback: "fallback"),
            "Incorrect email or password."
        )
    }

    func testEmailNotConfirmedUsesTheFrozenCopy() {
        XCTAssertEqual(
            AuthErrorCopy.text(for: PoseAPIError(code: "EMAIL_NOT_CONFIRMED", message: "anything"), fallback: "fallback"),
            "Confirm your email address."
        )
    }

    func testRateLimitedUsesTheFrozenCopy() {
        XCTAssertEqual(
            AuthErrorCopy.text(for: PoseAPIError(code: "RATE_LIMITED", message: "anything"), fallback: "fallback"),
            "Too many attempts. Try again in a few minutes."
        )
    }

    /// Anything else falls through to the shared `ErrorCopy` rules (e.g. 503
    /// AUTH_PENDING_VALIDATION keeps the server's own message).
    func testOtherAPIErrorsUseTheServerMessage() {
        XCTAssertEqual(
            AuthErrorCopy.text(for: PoseAPIError(code: "AUTH_PENDING_VALIDATION", message: "Still validating."), fallback: "fallback"),
            "Still validating."
        )
    }

    func testURLErrorsKeepTheirOwnCopy() {
        let offline = URLError(.notConnectedToInternet)
        XCTAssertEqual(AuthErrorCopy.text(for: offline, fallback: "fallback"), offline.localizedDescription)
    }

    func testSilentErrorsUseTheCallerFallback() {
        struct Silent: Error {}
        XCTAssertEqual(AuthErrorCopy.text(for: Silent(), fallback: "fallback"), "fallback")
    }
}

@MainActor
final class EmailSignInModelTests: XCTestCase {
    override func tearDown() {
        SignInMockURLProtocol.requestHandler = nil
        SignInMockURLProtocol.errorHandler = nil
        super.tearDown()
    }

    func testSuccessReturnsTrueSavesCredentialsAndLeavesNoError() async {
        SignInMockURLProtocol.requestHandler = { request in
            let body = #"{"accessToken":"a1","refreshToken":"r1","account":{"id":"u1","displayName":"U","createdAt":null}}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let storage = InMemoryTokenStorage()
        let model = makeModel(storage: storage)
        model.email = "reviewer@example.com"
        model.password = "correct-horse"

        let succeeded = await model.submit()

        XCTAssertTrue(succeeded)
        XCTAssertNil(model.errorText)
        XCTAssertFalse(model.isSubmitting)
        XCTAssertEqual(storage.loadCredentials()?.accessToken, "a1")
    }

    /// S4: an incomplete form is answered, never silently swallowed.
    ///
    /// This is the regression guard for the reported outcome: a tap that submits nothing used to
    /// leave the sheet exactly as it started (empty form, no error, no attempt), which the
    /// verification lane could not tell apart from a sign-in that failed and said nothing. The CTA
    /// keeps its muted fill but stays tappable, and the tap now writes the missing-input copy into
    /// the same error region a rejected credential uses.
    func testIncompleteFormSubmitAnswersWithCopyAndNeverCallsTheNetwork() async {
        SignInMockURLProtocol.requestHandler = { _ in
            XCTFail("No network call for an incomplete form")
            let empty = Data()
            return (HTTPURLResponse(url: URL(string: "https://test.server")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, empty)
        }
        let storage = InMemoryTokenStorage()
        let model = makeModel(storage: storage)

        let succeeded = await model.submit()

        XCTAssertFalse(succeeded)
        XCTAssertFalse(model.isSubmitting, "isSubmitting must never toggle for a rejected form")
        XCTAssertEqual(model.errorText, EmailSignInModel.incompleteFormText)
        XCTAssertNil(storage.loadCredentials())
    }

    /// One field missing is the same answer as both, so the sheet never says which field the
    /// server would have rejected.
    func testPasswordOnlyFormGetsTheSameIncompleteCopy() async {
        let model = makeModel(storage: InMemoryTokenStorage())
        model.password = "correct-horse"

        let succeeded = await model.submit()

        XCTAssertFalse(succeeded)
        XCTAssertEqual(model.errorText, EmailSignInModel.incompleteFormText)
    }

    /// The copy belongs to the attempt that produced it: the next attempt clears it before it
    /// makes a request, so a retry is never pre-answered by the previous outcome (S4).
    func testNextAttemptClearsTheIncompleteCopy() async {
        SignInMockURLProtocol.requestHandler = { request in
            let body = #"{"accessToken":"a1","refreshToken":"r1","account":{"id":"u1","displayName":"U","createdAt":null}}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let model = makeModel(storage: InMemoryTokenStorage())
        _ = await model.submit()
        XCTAssertEqual(model.errorText, EmailSignInModel.incompleteFormText)

        model.email = "reviewer@example.com"
        model.password = "correct-horse"
        let succeeded = await model.submit()

        XCTAssertTrue(succeeded)
        XCTAssertNil(model.errorText)
    }

    func testSubmittingTogglesIsSubmitting() async {
        SignInMockURLProtocol.requestHandler = { request in
            // Synchronous block on the loading thread keeps the request in flight so the
            // submitted state is observable from the test.
            Thread.sleep(forTimeInterval: 0.08)
            let body = #"{"accessToken":"a1","refreshToken":"r1","account":{"id":"u1","displayName":"U","createdAt":null}}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let model = makeModel(storage: InMemoryTokenStorage())
        model.email = "reviewer@example.com"
        model.password = "correct-horse"

        let task = Task { await model.submit() }
        await waitUntil("submitting") { model.isSubmitting }
        XCTAssertTrue(model.canSubmit)

        let succeeded = await task.value
        XCTAssertTrue(succeeded)
        XCTAssertFalse(model.isSubmitting)
    }

    /// DESIGN §5 "error": input is preserved so the user only fixes the wrong field.
    func testFailedSubmitPreservesTheTypedEmailAndPassword() async {
        SignInMockURLProtocol.requestHandler = { request in
            let body = #"{"error":{"code":"INVALID_CREDENTIALS","message":"Incorrect email or password."}}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let model = makeModel(storage: InMemoryTokenStorage())
        model.email = "reviewer@example.com"
        model.password = "wrong-password"

        let succeeded = await model.submit()

        XCTAssertFalse(succeeded)
        XCTAssertEqual(model.email, "reviewer@example.com")
        XCTAssertEqual(model.password, "wrong-password")
        XCTAssertEqual(model.errorText, "Incorrect email or password.")
        XCTAssertFalse(model.isSubmitting)
    }

    func testUnconfirmedEmailMapsToTheFrozenCopy() async {
        SignInMockURLProtocol.requestHandler = { request in
            let body = #"{"error":{"code":"EMAIL_NOT_CONFIRMED","message":"Confirm your email."}}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let model = makeModel(storage: InMemoryTokenStorage())
        model.email = "reviewer@example.com"
        model.password = "correct-horse"

        _ = await model.submit()
        XCTAssertEqual(model.errorText, "Confirm your email address.")
    }

    func testRateLimitedMapsToTheFrozenCopy() async {
        SignInMockURLProtocol.requestHandler = { request in
            let body = #"{"error":{"code":"RATE_LIMITED","message":"Too many attempts."}}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let model = makeModel(storage: InMemoryTokenStorage())
        model.email = "reviewer@example.com"
        model.password = "correct-horse"

        _ = await model.submit()
        XCTAssertEqual(model.errorText, "Too many attempts. Try again in a few minutes.")
    }

    func testUnmappedErrorUsesTheServerMessage() async {
        SignInMockURLProtocol.requestHandler = { request in
            let body = #"{"error":{"code":"BAD_REQUEST","message":"Malformed request."}}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let model = makeModel(storage: InMemoryTokenStorage())
        model.email = "reviewer@example.com"
        model.password = "correct-horse"

        _ = await model.submit()
        XCTAssertEqual(model.errorText, "Malformed request.")
    }

    /// DESIGN §5 "offline": the URL error's own copy, no stuck spinner, both fields intact so a
    /// retry only needs a connection.
    func testOfflineSubmitSurfacesTheURLErrorCopyAndStaysRetryable() async {
        SignInMockURLProtocol.errorHandler = { _ in URLError(.notConnectedToInternet) }
        let model = makeModel(storage: InMemoryTokenStorage())
        model.email = "reviewer@example.com"
        model.password = "correct-horse"

        let succeeded = await model.submit()

        XCTAssertFalse(succeeded)
        XCTAssertEqual(model.errorText, URLError(.notConnectedToInternet).localizedDescription)
        XCTAssertFalse(model.isSubmitting, "No stuck spinner: the CTA re-enables immediately")
        XCTAssertEqual(model.email, "reviewer@example.com")
        XCTAssertEqual(model.password, "correct-horse")
    }

    private func makeModel(storage: InMemoryTokenStorage) -> EmailSignInModel {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SignInMockURLProtocol.self]
        let client = APIClient(
            baseURL: "https://test.server",
            session: URLSession(configuration: config),
            boundary: SessionBoundary(tokenStorage: storage)
        )
        return EmailSignInModel(client: client)
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

private final class SignInMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) -> (HTTPURLResponse, Data))?
    /// Optional failure path for transport-level errors (offline, timeout).
    nonisolated(unsafe) static var errorHandler: ((URLRequest) -> Error)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let errorHandler = SignInMockURLProtocol.errorHandler {
            client?.urlProtocol(self, didFailWithError: errorHandler(request))
            return
        }
        guard let handler = SignInMockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
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
        XCTAssertEqual(SignInIntent.addPose.promptCopy, "Add your own pose.")
        XCTAssertEqual(SignInIntent.openJobs.promptCopy, "See your pose jobs.")
    }
}

/// BUG-261029-02: the Apple control shipped as an empty black box because `NeoButtonStyle` hardcodes
/// the label's `foregroundStyle` and the call site applied its white colour outside the button. These
/// assertions pin the two halves that made it invisible: the system wordmark (HIG) and a label colour
/// that is not the fill.
final class AppleSignInControlTests: XCTestCase {
    /// HIG requires the system wording next to the logo; QA asserts this label verbatim.
    func testUsesTheSystemWordmarkAndQAHandle() {
        XCTAssertEqual(AppleSignInCopy.title, "Sign in with Apple")
        XCTAssertEqual(AppleSignInCopy.identifier, "account.signin.apple")
    }

    /// The shipped bug, stated as an invariant: black fill + black logo/wordmark = invisible control.
    func testLabelColourIsVisibleAgainstTheFill() {
        XCTAssertTrue(
            AppleSignInCopy.hasVisibleContrast,
            "The Apple button's label colour must differ from its fill, or the logo and wordmark vanish"
        )
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
