import XCTest
@testable import iosApp

private final class JobsSessionTokenStorage: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var credentials: SessionCredentials?

    init(credentials: SessionCredentials?) {
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

/// Answers every request with the same job list, but holds request number `holdFrom` until the test
/// releases it, so a refresh can be made to land after a session change.
private class HoldingJobsURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var payload = Data()
    nonisolated(unsafe) static var requestCount = 0
    nonisolated(unsafe) static var holdFrom = Int.max
    nonisolated(unsafe) static var held: HoldingJobsURLProtocol?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestCount += 1
        if Self.requestCount >= Self.holdFrom {
            Self.held = self
            return
        }
        deliver()
    }

    override func stopLoading() {}

    func deliver() {
        guard let url = request.url else { return }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    static func releaseHeld() {
        let request = held
        held = nil
        request?.deliver()
    }

    static func reset() {
        payload = Data()
        requestCount = 0
        holdFrom = Int.max
        held = nil
    }
}

/// `JobsService` behind the shared session scope: the rows belong to the Account, so a refresh that
/// crosses a session change must not write them back over the cleared state.
@MainActor
final class JobsServiceSessionTests: XCTestCase {
    private var boundary: SessionBoundary!
    private var session: URLSession!
    private var service: JobsService!

    override func setUp() {
        super.setUp()
        AppConfig.shared.applyExtractPoseEnabled(true)
        HoldingJobsURLProtocol.reset()
        HoldingJobsURLProtocol.payload = Data(JobsFixtures.extractionJobListJSON.utf8)

        boundary = SessionBoundary(
            tokenStorage: JobsSessionTokenStorage(
                credentials: SessionCredentials(accessToken: "access-a", refreshToken: "refresh-a")
            )
        )
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HoldingJobsURLProtocol.self]
        session = URLSession(configuration: config)
        let client = APIClient(baseURL: "https://test.local", session: session, boundary: boundary)
        service = JobsService(api: PoseAPIService(client: client), boundary: boundary)
    }

    override func tearDown() {
        HoldingJobsURLProtocol.reset()
        AppConfig.shared.applyExtractPoseEnabled(true)
        service = nil
        session.invalidateAndCancel()
        session = nil
        boundary = nil
        super.tearDown()
    }

    func testSignOutClearsTheAccountRowsAndStopsPolling() async {
        await waitForSubscription()
        await service.refresh()
        XCTAssertEqual(service.inProgress.count, 1, "the Account's rows loaded")

        service.startPolling()
        await boundary.signOut()

        await waitUntil("the rows are cleared") { service.inProgress.isEmpty && service.finished.isEmpty }
        XCTAssertEqual(service.activeCount, 0)
        XCTAssertEqual(service.loadState, .idle)
        XCTAssertFalse(service.isOffline)

        let requestsWhenCleared = HoldingJobsURLProtocol.requestCount
        try? await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(
            HoldingJobsURLProtocol.requestCount,
            requestsWhenCleared,
            "polling must stop on sign-out"
        )
    }

    /// A refresh that was on the wire when the Account signed out must not paint A's jobs back over the
    /// cleared state (the hand-written observer had no check for this).
    func testRefreshAcrossSignOutDoesNotWriteThePreviousAccountsJobs() async {
        await waitForSubscription()
        HoldingJobsURLProtocol.holdFrom = 1

        let inFlight = Task { await service.refresh() }
        await waitUntil("the refresh is on the wire") { HoldingJobsURLProtocol.requestCount == 1 }
        XCTAssertEqual(service.loadState, .loading)

        await boundary.signOut()
        await waitUntil("the sign-out cleared the state") { service.loadState == .idle }

        HoldingJobsURLProtocol.releaseHeld()
        await inFlight.value

        XCTAssertTrue(service.inProgress.isEmpty, "A's jobs must not come back after the sign-out")
        XCTAssertTrue(service.finished.isEmpty)
        XCTAssertEqual(service.activeCount, 0)
        XCTAssertEqual(service.loadState, .idle)
    }

    func testSignInRefreshesForTheNewAccount() async {
        await waitForSubscription()
        await boundary.signOut()
        await waitUntil("signed out") { service.loadState == .idle }

        let requestsBefore = HoldingJobsURLProtocol.requestCount
        await boundary.saveCredentials(SessionCredentials(accessToken: "access-b", refreshToken: "refresh-b"))

        await waitUntil("the new Account's jobs loaded") {
            service.loadState == .loaded && !service.inProgress.isEmpty
        }
        XCTAssertGreaterThan(HoldingJobsURLProtocol.requestCount, requestsBefore)
    }

    // MARK: - helpers

    /// The scope registers its subscriber on the next main-actor turn; a test that changes the session
    /// immediately would race an unregistered subscription.
    private func waitForSubscription(timeout: TimeInterval = 5) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await boundary.subscriberCountForTests() > 0 { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTFail("the service never subscribed to the session boundary")
    }

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTFail("timed out waiting for \(description)")
    }
}
