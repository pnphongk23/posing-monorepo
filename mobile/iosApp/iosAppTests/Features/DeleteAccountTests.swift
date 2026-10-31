import Foundation
import XCTest
@testable import iosApp

/// "Delete account" is an external deletion **request** now (user decision, release sprint): the row
/// opens a Google Form where the account owner asks for deletion, and an admin deletes by hand.
///
/// So these tests pin the whole contract of the replacement row:
/// - it hands the opener exactly one URL, and that URL is the `SupportDestinations.deleteAccount`
///   constant the app ships (no per-user URL, no interpolation);
/// - it issues no request at all — the app must not send `DELETE /api/account` any more, so the one
///   instrumented API client the screen could reach must see nothing;
/// - it only exists for a signed-in account and it never touches the session.
@MainActor
final class DeleteAccountTests: XCTestCase {
    func testDeleteAccountRowOpensTheDeletionRequestFormExactlyOnce() async throws {
        let harness = try await signedInHarness()
        var opened: [URL] = []

        let openedURL = harness.model.openAccountDeletionRequest { opened.append($0) }

        XCTAssertEqual(opened.count, 1, "one tap hands over one URL")
        XCTAssertEqual(opened.first?.absoluteString, SupportDestinations.deleteAccount)
        XCTAssertEqual(opened.first, SupportDestinations.deleteAccountURL)
        XCTAssertEqual(openedURL, SupportDestinations.deleteAccountURL, "the model reports what it opened")
    }

    /// The user asked for deletion *somewhere else*: nothing about the local session may change, or
    /// the person would be signed out of an account that still exists.
    func testOpeningTheFormMakesNoNetworkCallAndKeepsTheSession() async throws {
        let harness = try await signedInHarness()
        let requestsAfterProjection = harness.requests.value
        XCTAssertEqual(requestsAfterProjection, 1, "the screen projected the account once")
        XCTAssertEqual(harness.model.state, .signedIn(deleteTestAccount))

        var opened: [URL] = []
        harness.model.openAccountDeletionRequest { opened.append($0) }
        // Give any (unwanted) fire-and-forget work a chance to run before asserting silence.
        for _ in 0..<5 { await Task.yield() }

        XCTAssertEqual(opened.count, 1)
        XCTAssertEqual(harness.requests.value, requestsAfterProjection, "opening the form sends no request")
        XCTAssertEqual(harness.model.state, .signedIn(deleteTestAccount), "the account stays signed in")
        XCTAssertEqual(
            harness.storage.loadCredentials()?.accessToken,
            deleteTestCredentials.accessToken,
            "the credentials are untouched: only an admin may delete the account"
        )
        XCTAssertNil(harness.model.authError)
    }

    /// The row belongs to an account. Signed out (or failed) there is nothing to ask about, so the
    /// screen renders no row and `openAccountDeletionRequest` declines instead of opening a form.
    func testSignedOutAccountHasNoDeletionRequestRow() async {
        let storage = DeleteTestTokenStorage(credentials: nil)
        let model = AccountSessionModel(
            boundary: SessionBoundary(tokenStorage: storage),
            readAccount: { deleteTestAccount },
            signInAction: SignInAction(start: {}),
            signInHistory: DeleteTestSignInHistory(hasSignedInBefore: true)
        )
        model.start()
        await waitUntil("signed out") { model.state == .signedOut }

        XCTAssertFalse(model.isAccountDeletionRequestAvailable, "no deletion row while signed out")

        var opened: [URL] = []
        let openedURL = model.openAccountDeletionRequest { opened.append($0) }
        XCTAssertNil(openedURL)
        XCTAssertTrue(opened.isEmpty, "a signed-out tap opens nothing")
    }

    func testFailedAccountProjectionHasNoDeletionRequestRow() async {
        let storage = DeleteTestTokenStorage(credentials: deleteTestCredentials)
        let model = AccountSessionModel(
            boundary: SessionBoundary(tokenStorage: storage),
            readAccount: { throw PoseAPIError(code: "500", message: "boom") },
            signInAction: SignInAction(start: {}),
            signInHistory: DeleteTestSignInHistory(hasSignedInBefore: true)
        )
        model.start()
        await waitUntil("failed") { if case .failed = model.state { return true }; return false }

        XCTAssertFalse(model.isAccountDeletionRequestAvailable)
        var opened: [URL] = []
        XCTAssertNil(model.openAccountDeletionRequest { opened.append($0) })
        XCTAssertTrue(opened.isEmpty)
    }

    func testSignedInAccountStillOffersSignOutAndTheDeletionRow() async throws {
        let harness = try await signedInHarness()

        XCTAssertTrue(harness.model.isAccountDeletionRequestAvailable, "the screen renders the row from this")
        XCTAssertTrue(harness.model.isSignOutAvailable, "sign-out is not gated by anything any more")
    }

    // MARK: - harness

    private struct Harness {
        let model: AccountSessionModel
        let storage: DeleteTestTokenStorage
        let requests: DeleteTestRequestCounter
    }

    /// A model backed by a real `PoseAPIService` whose transport is instrumented, so "no network call"
    /// is an assertion about the client the model actually holds rather than a claim about the code.
    private func signedInHarness() async throws -> Harness {
        let storage = DeleteTestTokenStorage(credentials: deleteTestCredentials)
        let requests = DeleteTestRequestCounter()
        // Left installed for the life of the test: the counter has to keep observing *after* the
        // projection, which is exactly the window the "no request" assertion is about.
        DeleteTestSpyURLProtocol.counter = requests

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DeleteTestSpyURLProtocol.self]
        let client = APIClient(
            baseURL: "https://test.server",
            session: URLSession(configuration: config),
            boundary: SessionBoundary(tokenStorage: storage)
        )
        let service = PoseAPIService(client: client)
        let model = AccountSessionModel(
            boundary: SessionBoundary(tokenStorage: storage),
            readAccount: { try await service.getCurrentAccount() },
            signInAction: SignInAction(start: {}),
            signInHistory: DeleteTestSignInHistory(hasSignedInBefore: true)
        )
        model.start()
        await waitUntil("signed in") { model.state == .signedIn(deleteTestAccount) }
        return Harness(model: model, storage: storage, requests: requests)
    }

    private func waitUntil(_ label: String, _ condition: @escaping () async -> Bool) async {
        for _ in 0..<400 {
            if await condition() { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTFail("Timed out waiting for \(label)")
    }
}

private let deleteTestCredentials = SessionCredentials(accessToken: "access", refreshToken: "refresh")
private let deleteTestAccount = AccountSummary(id: "apple-user", displayName: "Apple User", createdAt: nil)

private final class DeleteTestTokenStorage: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var credentials: SessionCredentials?

    init(credentials: SessionCredentials?) { self.credentials = credentials }
    func saveCredentials(_ credentials: SessionCredentials) { lock.lock(); self.credentials = credentials; lock.unlock() }
    func loadCredentials() -> SessionCredentials? { lock.lock(); defer { lock.unlock() }; return credentials }
    func clearCredentials() { lock.lock(); credentials = nil; lock.unlock() }
}

/// Records the install's sign-in history in memory; nothing in these tests reads `UserDefaults`.
private final class DeleteTestSignInHistory: SignInHistoryRecording, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: Bool

    init(hasSignedInBefore: Bool) { recorded = hasSignedInBefore }

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

private final class DeleteTestRequestCounter: @unchecked Sendable {
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

/// Instrumented transport: every request makes it here, so a silent `DELETE /api/account` (or any
/// other call) would show up in `DeleteTestRequestCounter`.
private final class DeleteTestSpyURLProtocol: URLProtocol {
    nonisolated(unsafe) static var counter: DeleteTestRequestCounter?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.counter?.increment()
        let body = #"{"data":{"id":"apple-user","displayName":"Apple User"}}"#
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://test.server")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
