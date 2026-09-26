import Foundation
import XCTest
@testable import iosApp

@MainActor
final class DeleteAccountTests: XCTestCase {
    func test204ClearsCredentialsAndReachesSignedOut() async {
        let storage = DeleteTestTokenStorage(credentials: deleteTestCredentials)
        let model = makeModel(storage: storage, deleteAccount: {})
        model.start()
        await waitUntil("signed in") { if case .signedIn = model.state { return true }; return false }

        model.deleteAccount()
        await waitUntil("signed out") { model.state == .signedOut }

        XCTAssertNil(storage.loadCredentials())
        XCTAssertFalse(model.isDeletingAccount)
        XCTAssertNil(model.deleteAccountError)
    }

    func test401KeepsCredentialsSignedInAndSurfacesSignInAgain() async {
        let storage = DeleteTestTokenStorage(credentials: deleteTestCredentials)
        let model = makeModel(storage: storage) {
            throw PoseAPIError(code: "401", message: "Unauthorized")
        }
        model.start()
        await waitUntil("signed in") { if case .signedIn = model.state { return true }; return false }

        model.deleteAccount()
        await waitUntil("delete failure") { model.deleteAccountError != nil }

        XCTAssertNotNil(storage.loadCredentials())
        XCTAssertEqual(model.state, .signedIn(deleteTestAccount))
        XCTAssertEqual(model.deleteAccountError, "Please sign in again.")
    }

    func test503BackendEnvelopeKeepsCredentialsSignedInAndSurfacesUnavailable() async {
        let storage = DeleteTestTokenStorage(credentials: deleteTestCredentials)
        let errorRecorder = DeleteTestErrorRecorder()
        DeleteMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/account")
            let body = #"{"error":{"code":"AUTH_PENDING_VALIDATION","message":"Account deletion is pending runtime validation"}}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let client = APIClient(
            baseURL: "https://test.server",
            session: makeDeleteMockSession(),
            boundary: SessionBoundary(tokenStorage: storage)
        )
        let model = makeModel(storage: storage) {
            do {
                try await client.deleteAccount()
                XCTFail("Expected account deletion to fail")
            } catch let error as PoseAPIError {
                errorRecorder.record(error)
                throw error
            }
        }
        model.start()
        await waitUntil("signed in") { if case .signedIn = model.state { return true }; return false }

        model.deleteAccount()
        await waitUntil("delete failure") { model.deleteAccountError != nil }

        XCTAssertEqual(errorRecorder.code, "AUTH_PENDING_VALIDATION")
        XCTAssertNotNil(storage.loadCredentials())
        XCTAssertEqual(model.state, .signedIn(deleteTestAccount))
        XCTAssertEqual(model.deleteAccountError, "Account deletion is temporarily unavailable. Try again later.")
    }

    func testDoubleConfirmIssuesExactlyOneRequest() async {
        let storage = DeleteTestTokenStorage(credentials: deleteTestCredentials)
        let calls = DeleteTestCounter()
        let model = makeModel(storage: storage) {
            calls.increment()
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        model.start()
        await waitUntil("signed in") { if case .signedIn = model.state { return true }; return false }

        model.deleteAccount()
        model.deleteAccount()
        await waitUntil("signed out") { model.state == .signedOut }
        XCTAssertEqual(calls.value, 1)
    }

    func testConfirmationCopyStatesIrreversibilityWithoutSubscriptionClaim() {
        let copy = AccountStateCopy.deleteAccountConfirmationMessage
        XCTAssertTrue(copy.localizedCaseInsensitiveContains("cannot be recovered"))
        XCTAssertFalse(copy.localizedCaseInsensitiveContains("subscription"))
        XCTAssertFalse(copy.localizedCaseInsensitiveContains("Apple"))
    }

    private func makeModel(
        storage: DeleteTestTokenStorage,
        deleteAccount: @escaping AccountSessionModel.AccountDeleter
    ) -> AccountSessionModel {
        AccountSessionModel(
            boundary: SessionBoundary(tokenStorage: storage),
            readAccount: { deleteTestAccount },
            signInAction: SignInAction(start: {}),
            deleteAccount: deleteAccount
        )
    }

    private func waitUntil(_ label: String, _ condition: @escaping () -> Bool) async {
        for _ in 0..<400 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTFail("Timed out waiting for \(label)")
    }

    private func makeDeleteMockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DeleteMockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

private let deleteTestCredentials = SessionCredentials(accessToken: "access", refreshToken: "refresh")
private let deleteTestAccount = AccountSummary(id: "apple-user", displayName: "Apple User", createdAt: nil)

private final class DeleteTestTokenStorage: TokenStoring, @unchecked Sendable {
    private var credentials: SessionCredentials?

    init(credentials: SessionCredentials?) { self.credentials = credentials }
    func saveCredentials(_ credentials: SessionCredentials) { self.credentials = credentials }
    func loadCredentials() -> SessionCredentials? { credentials }
    func clearCredentials() { credentials = nil }
}

private final class DeleteTestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

private final class DeleteTestErrorRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedCode: String?

    func record(_ error: PoseAPIError) {
        lock.lock()
        recordedCode = error.code
        lock.unlock()
    }

    var code: String? {
        lock.lock()
        defer { lock.unlock() }
        return recordedCode
    }
}

private final class DeleteMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
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
