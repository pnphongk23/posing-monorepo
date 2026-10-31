import XCTest
@testable import iosApp

/// The extraction kill switch (`AppConfig.shared.isExtractPoseEnabled`) must own the whole Jobs
/// surface, not just `retry()`. While it is off, `refresh()` and `startPolling()` are no-ops that put
/// zero requests on the wire and leave the service in a cleared `.idle` state — a flag-off install
/// used to call `listMyExtractJobs` on every `.signedIn` and on every poll tick.
///
/// Mutation target: delete the `canExtractPose` guard at the top of `JobsService.refresh()` and
/// `testFlagOffSignedInEventIssuesNoListRequest` goes red (1 list request, rows painted, `.loaded`).
/// The poll-loop guard in `startPolling()` is pinned from the other side: with it removed this class
/// only stays green because `refresh()` is already a no-op, so a mutant must drop both.
@MainActor
final class JobsFlagGuardTests: XCTestCase {
    /// `JobsService` polls every 5 s; one interval plus a margin is the smallest sleep that proves a
    /// poll loop is *not* running.
    private static let onePollIntervalWithMargin: UInt64 = 5_200_000_000

    private var sessionBoundary: SessionBoundary!
    private var tokenStorage: FlagGuardTokenStorage!
    private var urlSession: URLSession!
    private var apiService: PoseAPIService!
    private var listRequestCount: FlagGuardCounter!

    override func setUp() {
        super.setUp()
        AppConfig.shared.applyExtractPoseEnabled(true)
        listRequestCount = FlagGuardCounter()
        tokenStorage = FlagGuardTokenStorage(
            credentials: SessionCredentials(accessToken: "test_access", refreshToken: "test_refresh")
        )
        sessionBoundary = SessionBoundary(tokenStorage: tokenStorage)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FlagGuardURLProtocol.self]
        urlSession = URLSession(configuration: config)

        let client = APIClient(baseURL: "https://test.local", session: urlSession, boundary: sessionBoundary)
        apiService = PoseAPIService(client: client)

        let counter = listRequestCount!
        let listPath = "/api/me/extract-jobs"
        FlagGuardURLProtocol.requestHandler = { request in
            if request.url?.path == listPath {
                counter.increment()
            }
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data(JobsFixtures.extractionJobListJSON.utf8)
            )
        }
    }

    override func tearDown() {
        AppConfig.shared.applyExtractPoseEnabled(true)
        FlagGuardURLProtocol.requestHandler = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        apiService = nil
        sessionBoundary = nil
        tokenStorage = nil
        listRequestCount = nil
        super.tearDown()
    }

    // MARK: - Flag OFF

    /// (a) A signed-in event on a flag-off build reads nothing: no list request, no rows, `.idle`.
    func testFlagOffSignedInEventIssuesNoListRequest() async {
        AppConfig.shared.applyExtractPoseEnabled(false)
        let service = makeService()

        service.resetForSessionChange(.signedIn)
        // The signed-in path kicks `refresh()` inside a Task; give it the turns it would need to
        // reach the network before asserting that it never did.
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(listRequestCount.value, 0, "a flag-off build must not call listMyExtractJobs")
        XCTAssertEqual(service.inProgress, [])
        XCTAssertEqual(service.finished, [])
        XCTAssertEqual(service.activeCount, 0)
        XCTAssertEqual(service.loadState, .idle)
        XCTAssertFalse(service.isOffline)
    }

    /// (b) Polling never starts while the flag is off — not even one tick.
    func testFlagOffStartPollingIssuesNoRequest() async {
        AppConfig.shared.applyExtractPoseEnabled(false)
        let service = makeService()

        service.startPolling()
        try? await Task.sleep(nanoseconds: Self.onePollIntervalWithMargin)

        XCTAssertEqual(listRequestCount.value, 0, "a flag-off build must not poll the jobs list")
        XCTAssertEqual(service.inProgress, [])
        XCTAssertEqual(service.finished, [])
        XCTAssertEqual(service.loadState, .idle)

        service.stopPolling()
    }

    /// Rows painted while the flag was on are cleared the first time the flag is off, and that
    /// clearing costs no request.
    func testFlagFlippingOffClearsCachedRowsWithoutRequest() async {
        let service = makeService()
        await service.refresh()
        XCTAssertEqual(service.inProgress.count, 1, "flag-on build loads the Account's rows")
        XCTAssertEqual(service.finished.count, 2)
        XCTAssertEqual(service.loadState, .loaded)

        AppConfig.shared.applyExtractPoseEnabled(false)
        await service.refresh()

        XCTAssertEqual(listRequestCount.value, 1, "the flag-off refresh must not hit the network")
        XCTAssertEqual(service.inProgress, [])
        XCTAssertEqual(service.finished, [])
        XCTAssertEqual(service.activeCount, 0)
        XCTAssertEqual(service.loadState, .idle)
        XCTAssertFalse(service.isOffline)
    }

    /// (d) The pre-existing write-path guard is unchanged: retry throws before any request.
    func testFlagOffRetryThrowsExtractPoseDisabled() async {
        AppConfig.shared.applyExtractPoseEnabled(false)
        let service = makeService()

        do {
            try await service.retry(id: "job1")
            XCTFail("Expected extractPoseDisabled")
        } catch JobsError.extractPoseDisabled {
            // Expected: the kill switch blocks retry before the session check and the request.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(listRequestCount.value, 0)
    }

    // MARK: - Flag ON

    /// (c) The guard is a switch, not a removal: a flag-on build still reads exactly once per
    /// signed-in event.
    func testFlagOnSignedInEventIssuesOneRequest() async {
        let service = makeService()

        service.resetForSessionChange(.signedIn)
        await waitUntil("the signed-in refresh lands") {
            service.loadState == .loaded && self.listRequestCount.value >= 1
        }

        // A second read inside the same turn would show up as a duplicate; nothing should schedule one.
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(listRequestCount.value, 1, "one signed-in event reads the list exactly once")
        XCTAssertEqual(service.inProgress.count, 1)
        XCTAssertEqual(service.finished.count, 2)
        XCTAssertEqual(service.activeCount, 1)
    }

    // MARK: - Helpers

    private func makeService() -> JobsService {
        JobsService(api: apiService, boundary: sessionBoundary)
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

private final class FlagGuardCounter: @unchecked Sendable {
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

private final class FlagGuardTokenStorage: TokenStoring, @unchecked Sendable {
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

private final class FlagGuardURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            XCTFail("No FlagGuardURLProtocol requestHandler provided")
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
