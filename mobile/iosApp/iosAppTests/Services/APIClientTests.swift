import XCTest
@testable import iosApp

final class APIClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testUnauthorizedCodeDetection() {
        let error = PoseAPIError(code: "UNAUTHORIZED", message: "expired")
        XCTAssertTrue(error.isUnauthorized)
        XCTAssertTrue(UnauthorizedCodes.contains("401"))
        XCTAssertFalse(UnauthorizedCodes.contains("INVALID_IMAGE"))
    }

    func testRefreshAndRetryOn401() async throws {
        var callCount = 0
        MockURLProtocol.requestHandler = { request in
            callCount += 1
            if request.url?.path == "/api/auth/refresh" {
                let body = #"{"accessToken":"new","refreshToken":"rt2"}"#
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
            }
            if callCount == 1 {
                return (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data())
            }
            let body = #"{"data":{"id":"u1","displayName":"Test"}}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let storage = InMemoryTokenStorage()
        storage.saveCredentials(SessionCredentials(accessToken: "old", refreshToken: "rt"))
        let boundary = SessionBoundary(tokenStorage: storage)
        let session = makeMockSession()
        let client = APIClient(baseURL: "https://test.server", session: session, boundary: boundary)
        let (data, _) = try await client.request(path: "/api/account/me")
        let account = try client.decode(AccountSummaryResponse.self, from: data)
        XCTAssertEqual(account.data.displayName, "Test")
        XCTAssertEqual(storage.loadCredentials()?.accessToken, "new")
        XCTAssertEqual(callCount, 3)
    }

    func testPoseAPIErrorFromEnvelope() async {
        MockURLProtocol.requestHandler = { request in
            let body = #"{"error":{"code":"INVALID_IMAGE","message":"Bad image"}}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let boundary = SessionBoundary(tokenStorage: InMemoryTokenStorage())
        let client = APIClient(baseURL: "https://test.server", session: makeMockSession(), boundary: boundary)
        do {
            _ = try await client.request(path: "/api/community/poses", acceptedStatus: [200])
            XCTFail("Expected error")
        } catch let error as PoseAPIError {
            XCTAssertEqual(error.code, "INVALID_IMAGE")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - email + password sign-in (PLAN §4)

    /// POST /api/auth/email/signin must carry exactly the contracted method, path, header and
    /// body keys, persist through `SessionBoundary.saveCredentials` and emit exactly ONE
    /// `.signedIn` session event.
    func testSignInWithPasswordSendsExactRequestSavesCredentialsAndEmitsOneSignedIn() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            let body = #"{"accessToken":"access-1","refreshToken":"refresh-1","account":{"id":"u1","displayName":"Reviewer","createdAt":"2026-01-01"}}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let storage = InMemoryTokenStorage()
        let boundary = SessionBoundary(tokenStorage: storage)
        let recorder = SessionEventRecorder()
        let stream = await boundary.events()
        let collector = Task {
            for await event in stream { recorder.record(event) }
        }
        let client = APIClient(baseURL: "https://test.server", session: makeMockSession(), boundary: boundary)

        try await client.signInWithPassword(email: "reviewer@example.com", password: "correct-horse")
        // Give any duplicate event a chance to surface before asserting exactly one.
        try await Task.sleep(nanoseconds: 100_000_000)
        collector.cancel()

        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/auth/email/signin")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(request.bodyData)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json, ["email": "reviewer@example.com", "password": "correct-horse"])

        let credentials = try XCTUnwrap(storage.loadCredentials())
        XCTAssertEqual(credentials.accessToken, "access-1")
        XCTAssertEqual(credentials.refreshToken, "refresh-1")
        XCTAssertEqual(recorder.recorded, [.signedIn], "Exactly ONE .signedIn event per sign-in")
    }

    /// A 401 from the sign-in endpoint is INVALID_CREDENTIALS, never a trigger for the refresh
    /// cycle: exactly one network call, and no stored credentials were touched.
    func testSignInWithPasswordWrongPasswordThrowsInvalidCredentialsWithoutRefreshing() async {
        var callCount = 0
        MockURLProtocol.requestHandler = { request in
            callCount += 1
            let body = #"{"error":{"code":"INVALID_CREDENTIALS","message":"Incorrect email or password."}}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let storage = InMemoryTokenStorage()
        let client = APIClient(baseURL: "https://test.server", session: makeMockSession(), boundary: SessionBoundary(tokenStorage: storage))

        do {
            try await client.signInWithPassword(email: "who@example.com", password: "wrong")
            XCTFail("Expected INVALID_CREDENTIALS")
        } catch let error as PoseAPIError {
            XCTAssertEqual(error.code, "INVALID_CREDENTIALS")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(callCount, 1, "No refresh attempt on a sign-in 401")
        XCTAssertNil(storage.loadCredentials())
    }

    func testSignInWithPasswordRateLimitedThrowsRateLimited() async {
        MockURLProtocol.requestHandler = { request in
            let body = #"{"error":{"code":"RATE_LIMITED","message":"Too many attempts."}}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let client = APIClient(baseURL: "https://test.server", session: makeMockSession(), boundary: SessionBoundary(tokenStorage: InMemoryTokenStorage()))

        do {
            try await client.signInWithPassword(email: "who@example.com", password: "wrong")
            XCTFail("Expected RATE_LIMITED")
        } catch let error as PoseAPIError {
            XCTAssertEqual(error.code, "RATE_LIMITED")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSignInWithApplePostsRawNonceAndStoresCredentials() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            let body = #"{"accessToken":"apple-access","refreshToken":"apple-refresh","account":{"id":"apple-1","displayName":"Apple User"}}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let storage = InMemoryTokenStorage()
        let client = APIClient(baseURL: "https://test.server", session: makeMockSession(), boundary: SessionBoundary(tokenStorage: storage))

        try await client.signInWithApple(identityToken: "id-token", nonce: "raw-nonce", fullName: "Apple User")

        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/auth/apple/signin")
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: try XCTUnwrap(request.bodyData)) as? [String: String])
        XCTAssertEqual(json["identityToken"], "id-token")
        XCTAssertEqual(json["nonce"], "raw-nonce")
        XCTAssertEqual(json["fullName"], "Apple User")
        XCTAssertEqual(storage.loadCredentials()?.accessToken, "apple-access")
        XCTAssertEqual(storage.loadCredentials()?.refreshToken, "apple-refresh")
    }

    func testDeleteAccountSendsTheAppleAuthorizationCodeAsAJSONBody() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
        }
        let client = APIClient(baseURL: "https://test.server", session: makeMockSession(), boundary: SessionBoundary(tokenStorage: InMemoryTokenStorage()))

        try await client.deleteAccount(appleAuthorizationCode: "apple-code-123")

        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.path, "/api/account")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: try XCTUnwrap(request.bodyData)) as? [String: String])
        XCTAssertEqual(json, ["appleAuthorizationCode": "apple-code-123"])
    }

    func testDeleteAccountWithoutACodeSendsNoBody() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
        }
        let client = APIClient(baseURL: "https://test.server", session: makeMockSession(), boundary: SessionBoundary(tokenStorage: InMemoryTokenStorage()))

        try await client.deleteAccount()

        let request = try XCTUnwrap(capturedRequest)
        XCTAssertNil(request.httpBody)
        XCTAssertNil(request.bodyData)
        XCTAssertNil(request.value(forHTTPHeaderField: "Content-Type"))
    }

    func testDeleteAccountMapsThe409HandshakeToTypedErrors() async {
        let client = APIClient(baseURL: "https://test.server", session: makeMockSession(), boundary: SessionBoundary(tokenStorage: InMemoryTokenStorage()))

        for (code, expected) in [
            ("APPLE_REAUTH_REQUIRED", AccountDeletionError.appleReauthRequired),
            ("APPLE_IDENTITY_MISMATCH", AccountDeletionError.appleIdentityMismatch),
        ] {
            MockURLProtocol.requestHandler = { request in
                let body = #"{"error":{"code":"\#(code)","message":"needs Apple"}}"#
                return (HTTPURLResponse(url: request.url!, statusCode: 409, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
            }
            do {
                try await client.deleteAccount()
                XCTFail("Expected a 409 challenge for \(code)")
            } catch let error as AccountDeletionError {
                XCTAssertEqual(error, expected)
            } catch {
                XCTFail("Unexpected error for \(code): \(error)")
            }
        }
    }

    func testDeleteAccountAccepts204AndRejectsAnythingElse() async throws {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
        }
        let client = APIClient(baseURL: "https://test.server", session: makeMockSession(), boundary: SessionBoundary(tokenStorage: InMemoryTokenStorage()))
        try await client.deleteAccount()

        MockURLProtocol.requestHandler = { request in
            let body = #"{"error":{"code":"503","message":"Temporarily unavailable"}}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        do {
            try await client.deleteAccount()
            XCTFail("Expected non-204 delete to fail")
        } catch let error as PoseAPIError {
            XCTAssertEqual(error.code, "503")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeMockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

private final class InMemoryTokenStorage: TokenStoring, @unchecked Sendable {
    private var credentials: SessionCredentials?
    func saveCredentials(_ credentials: SessionCredentials) { self.credentials = credentials }
    func loadCredentials() -> SessionCredentials? { credentials }
    func clearCredentials() { credentials = nil }
}

/// `URLSession` delivers the request body as a stream through `URLProtocol`, so drain it here
/// instead of reading `httpBody` (which is nil on the receiving side).
private extension URLRequest {
    var bodyData: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

/// Thread-safe `SessionEvent` collector for asserting exactly-one event emissions.
private final class SessionEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [SessionEvent] = []

    func record(_ event: SessionEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    var recorded: [SessionEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}

private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
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
