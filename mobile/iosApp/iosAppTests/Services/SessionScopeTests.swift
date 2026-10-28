import XCTest
@testable import iosApp

private final class ScopeTestTokenStorage: TokenStoring, @unchecked Sendable {
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

/// Records what the scope asked it to do.
@MainActor
private final class RecordingScopedModel: SessionScoped {
    private(set) var resets: [SessionEvent] = []

    func resetForSessionChange(_ event: SessionEvent) {
        resets.append(event)
    }
}

@MainActor
final class SessionScopeTests: XCTestCase {
    func testScopeKeepsOneSubscriptionForEveryAdoptedModel() async {
        let boundary = SessionBoundary(tokenStorage: ScopeTestTokenStorage(credentials: credentialsA))
        let scope = SessionScope.of(boundary)
        let first = RecordingScopedModel()
        let second = RecordingScopedModel()

        scope.adopt(first)
        scope.adopt(second)
        scope.adopt(second) // idempotent: one model, one reset
        await waitForSubscription(boundary)

        let subscribers = await boundary.subscriberCountForTests()
        XCTAssertEqual(
            subscribers,
            1,
            "two models behind one boundary must share one observeSessions subscription"
        )
        await boundary.signOut()

        await waitUntil("both models reset") { first.resets.count == 1 && second.resets.count == 1 }
        XCTAssertEqual(first.resets, [.signedOut])
        XCTAssertEqual(second.resets, [.signedOut], "adopting twice must not reset twice")
    }

    func testTicketCapturedBeforeAnEventIsStaleAfterIt() async {
        let boundary = SessionBoundary(tokenStorage: ScopeTestTokenStorage(credentials: credentialsA))
        let scope = SessionScope.of(boundary)
        let model = RecordingScopedModel()
        scope.adopt(model)
        await waitForSubscription(boundary)

        let ticket = await scope.beginRequest()
        let validBefore = await scope.isValid(ticket)
        XCTAssertTrue(validBefore)

        await boundary.saveCredentials(credentialsB)
        await waitUntil("the model reset") { model.resets == [.signedIn] }

        XCTAssertFalse(scope.isCurrent(ticket), "a ticket from the previous session must be stale")
        let validAfter = await scope.isValid(ticket)
        XCTAssertFalse(validAfter, "a request that crossed a session change must be discarded")
        let fresh = await scope.beginRequest()
        let validFresh = await scope.isValid(fresh)
        XCTAssertTrue(validFresh, "the current session's ticket is accepted")
    }

    /// The scope's counter moves one main-actor turn behind the boundary mutation, so a request can
    /// start after the credentials changed but before the reset was delivered. That request belongs to
    /// the new session: the late reset must not discard its answer (regression: the ordinary
    /// "A signs out, B signs in, B's first tap" flow answered `.discarded`).
    func testRequestStartedAfterTheCredentialsChangedSurvivesTheLateReset() async {
        let boundary = SessionBoundary(tokenStorage: ScopeTestTokenStorage(credentials: credentialsA))
        let scope = SessionScope.of(boundary)
        let model = RecordingScopedModel()
        scope.adopt(model)
        await waitForSubscription(boundary)

        await boundary.saveCredentials(credentialsB)
        let ticket = await scope.beginRequest()

        await waitUntil("B's reset landed") { model.resets == [.signedIn] }
        let valid = await scope.isValid(ticket)
        XCTAssertTrue(valid, "a request that started after the change belongs to the new session")
    }

    /// Throwaway instances (the composition root rebuilds a model inside `body`) must not keep the
    /// scope busy: members are weak, so the next event simply forgets them.
    func testScopeDoesNotKeepThrowawayModelsAlive() async {
        let boundary = SessionBoundary(tokenStorage: ScopeTestTokenStorage(credentials: credentialsA))
        let scope = SessionScope.of(boundary)
        weak var throwaway: RecordingScopedModel?
        autoreleasepool {
            let model = RecordingScopedModel()
            throwaway = model
            scope.adopt(model)
        }
        let keeper = RecordingScopedModel()
        scope.adopt(keeper)
        await waitForSubscription(boundary)

        XCTAssertNil(throwaway, "the scope must hold its members weakly")
        await boundary.signOut()
        await waitUntil("the surviving model reset") { keeper.resets == [.signedOut] }
    }

    // MARK: - InFlight

    func testInFlightRejectsASecondClaimForTheSameKey() {
        var inFlight = InFlight<String>()
        XCTAssertNotNil(inFlight.begin("pose-1"))
        XCTAssertNil(inFlight.begin("pose-1"), "one request per key at a time")
        XCTAssertTrue(inFlight.contains("pose-1"))
        XCTAssertEqual(inFlight.keys, ["pose-1"])
    }

    /// The bug: a `defer` released whichever claim was standing, so A's late completion cleared B's
    /// claim for the same key. A token can only release its own.
    func testInFlightEndOnlyReleasesTheOwningRequest() {
        var inFlight = InFlight<String>()
        let firstClaim = inFlight.begin("pose-1")
        XCTAssertNotNil(firstClaim)
        inFlight.removeAll() // a session change drops every claim

        let secondClaim = inFlight.begin("pose-1")
        XCTAssertNotNil(secondClaim)
        XCTAssertNotEqual(firstClaim, secondClaim)

        inFlight.end("pose-1", firstClaim ?? 0)
        XCTAssertTrue(inFlight.contains("pose-1"), "A's release must not free B's claim")

        inFlight.end("pose-1", secondClaim ?? 0)
        XCTAssertFalse(inFlight.contains("pose-1"))
        XCTAssertTrue(inFlight.keys.isEmpty)
    }

    // MARK: - helpers

    private var credentialsA: SessionCredentials {
        SessionCredentials(accessToken: "access-a", refreshToken: "refresh-a")
    }

    private var credentialsB: SessionCredentials {
        SessionCredentials(accessToken: "access-b", refreshToken: "refresh-b")
    }

    /// The scope registers its subscriber on the next main-actor turn, so a test that changes the
    /// session immediately would race an unregistered subscription.
    private func waitForSubscription(_ boundary: SessionBoundary, timeout: TimeInterval = 5) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await boundary.subscriberCountForTests() > 0 { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTFail("the scope never subscribed to the session boundary")
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
