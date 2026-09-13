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
