import XCTest
@testable import iosApp

private final class InMemoryTokenStorage: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var credentials: SessionCredentials?

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

/// Counts how many times a refresh closure actually reached the network.
private actor RefreshAttemptCounter {
    private(set) var value = 0
    func record() { value += 1 }
}

final class SessionBoundaryTests: XCTestCase {
    private func makeBoundary() -> (SessionBoundary, InMemoryTokenStorage) {
        let storage = InMemoryTokenStorage()
        return (SessionBoundary(tokenStorage: storage), storage)
    }

    func testHasStoredSessionReflectsStorage() async {
        let (boundary, storage) = makeBoundary()
        var hasSession = await boundary.hasStoredSession()
        XCTAssertFalse(hasSession)

        await boundary.saveCredentials(SessionCredentials(accessToken: "a", refreshToken: "r"))
        hasSession = await boundary.hasStoredSession()
        XCTAssertTrue(hasSession)

        await boundary.signOut()
        hasSession = await boundary.hasStoredSession()
        XCTAssertFalse(hasSession)
        XCTAssertNil(storage.loadCredentials())
    }

    func testSignOutIsRepeatSafeAndDoesNotBumpGenerationTwice() async {
        let (boundary, _) = makeBoundary()
        await boundary.saveCredentials(SessionCredentials(accessToken: "a", refreshToken: "r"))
        let afterSignIn = await boundary.currentGeneration

        await boundary.signOut()
        let afterFirstSignOut = await boundary.currentGeneration
        XCTAssertEqual(afterFirstSignOut, afterSignIn + 1)

        await boundary.signOut()
        let afterSecondSignOut = await boundary.currentGeneration
        XCTAssertEqual(afterSecondSignOut, afterFirstSignOut, "A repeat sign-out must keep the same projection")
    }

    func testEventsReportSignInSignOutAndUnauthorizedClear() async {
        let (boundary, _) = makeBoundary()

        let signInStream = await boundary.events()
        await boundary.saveCredentials(SessionCredentials(accessToken: "a", refreshToken: "r"))
        let signInEvent = await firstEvent(from: signInStream)
        XCTAssertEqual(signInEvent, .signedIn)

        let signOutStream = await boundary.events()
        await boundary.signOut()
        let signOutEvent = await firstEvent(from: signOutStream)
        XCTAssertEqual(signOutEvent, .signedOut)

        let clearedStream = await boundary.events()
        await boundary.saveCredentials(SessionCredentials(accessToken: "b", refreshToken: "r2"))
        let secondSignIn = await firstEvent(from: clearedStream)
        XCTAssertEqual(secondSignIn, .signedIn)

        await boundary.clearForUnauthorized()
        let clearEvent = await firstEvent(from: clearedStream)
        XCTAssertEqual(clearEvent, .signInRequired)
    }

    /// A session projection only needs the latest truth: when mutations land faster than the
    /// consumer wakes up, the older event is coalesced instead of replaying a stale state.
    func testBurstOfSessionChangesCoalescesToTheLatestEvent() async {
        let (boundary, _) = makeBoundary()
        let stream = await boundary.events()

        await boundary.saveCredentials(SessionCredentials(accessToken: "a", refreshToken: "r"))
        await boundary.clearForUnauthorized()

        let event = await firstEvent(from: stream)
        XCTAssertEqual(event, .signInRequired)
    }

    func testFailedRefreshClearsSessionAndSignalsSignInRequired() async {
        let (boundary, storage) = makeBoundary()
        await boundary.saveCredentials(SessionCredentials(accessToken: "a", refreshToken: "r"))

        let stream = await boundary.events()
        let refreshed = await boundary.refresh { _ in nil }

        XCTAssertFalse(refreshed)
        XCTAssertNil(storage.loadCredentials())
        let event = await firstEvent(from: stream)
        XCTAssertEqual(event, .signInRequired)
    }

    func testRefreshReplacesCredentialsWithoutEmittingSessionChange() async {
        let (boundary, storage) = makeBoundary()
        await boundary.saveCredentials(SessionCredentials(accessToken: "old", refreshToken: "r"))

        let stream = await boundary.events()
        let refreshed = await boundary.refresh { _ in
            SessionCredentials(accessToken: "new", refreshToken: "r2")
        }

        XCTAssertTrue(refreshed)
        XCTAssertEqual(storage.loadCredentials()?.accessToken, "new")
        // A refresh stays inside the same session, so nothing is emitted for observers.
        let event = await firstEvent(from: stream, timeout: 0.2)
        XCTAssertNil(event)
    }

    /// A burst of 401s shares one refresh. The token rotates server-side, so a second concurrent
    /// attempt would present a token the first one already consumed, and its failure would clear a
    /// session that had just refreshed successfully.
    func testConcurrentRefreshesShareOneAttempt() async {
        let (boundary, storage) = makeBoundary()
        await boundary.saveCredentials(SessionCredentials(accessToken: "old", refreshToken: "r"))
        let attempts = RefreshAttemptCounter()

        async let first = boundary.refresh { _ in
            await attempts.record()
            try? await Task.sleep(nanoseconds: 50_000_000)
            return SessionCredentials(accessToken: "new", refreshToken: "r2")
        }
        async let second = boundary.refresh { _ in
            await attempts.record()
            try? await Task.sleep(nanoseconds: 50_000_000)
            return SessionCredentials(accessToken: "new", refreshToken: "r2")
        }

        let firstResult = await first
        let secondResult = await second
        let attemptCount = await attempts.value
        XCTAssertTrue(firstResult)
        XCTAssertTrue(secondResult)
        XCTAssertEqual(attemptCount, 1, "Both callers must share one network attempt")
        XCTAssertEqual(storage.loadCredentials()?.accessToken, "new")
    }

    /// Coalescing must not turn into caching: the next 401 after the in-flight refresh settled
    /// starts a fresh attempt, and it presents the rotated token.
    func testRefreshAfterTheInFlightOneSettlesStartsAgain() async {
        let (boundary, storage) = makeBoundary()
        await boundary.saveCredentials(SessionCredentials(accessToken: "a", refreshToken: "r"))
        let attempts = RefreshAttemptCounter()

        let first = await boundary.refresh { token in
            await attempts.record()
            return SessionCredentials(accessToken: "b", refreshToken: "\(token)-2")
        }
        let second = await boundary.refresh { token in
            await attempts.record()
            return SessionCredentials(accessToken: "c", refreshToken: "\(token)-3")
        }
        let attemptCount = await attempts.value

        XCTAssertTrue(first)
        XCTAssertTrue(second)
        XCTAssertEqual(attemptCount, 2)
        XCTAssertEqual(storage.loadCredentials()?.refreshToken, "r-2-3", "The second attempt must present the rotated token")
    }

    /// A failed shared refresh still reports one failure and signals sign-in exactly once.
    func testConcurrentFailedRefreshesReportOneFailure() async {
        let (boundary, storage) = makeBoundary()
        await boundary.saveCredentials(SessionCredentials(accessToken: "a", refreshToken: "r"))
        let attempts = RefreshAttemptCounter()
        let stream = await boundary.events()

        async let first = boundary.refresh { _ in
            await attempts.record()
            try? await Task.sleep(nanoseconds: 20_000_000)
            return nil
        }
        async let second = boundary.refresh { _ in
            await attempts.record()
            return nil
        }

        let firstResult = await first
        let secondResult = await second
        let attemptCount = await attempts.value
        XCTAssertFalse(firstResult)
        XCTAssertFalse(secondResult)
        XCTAssertEqual(attemptCount, 1)
        XCTAssertNil(storage.loadCredentials())
        let event = await firstEvent(from: stream)
        XCTAssertEqual(event, .signInRequired)
    }

    // MARK: - helpers

    private func firstEvent(from stream: AsyncStream<SessionEvent>, timeout: TimeInterval = 2) async -> SessionEvent? {
        await withTaskGroup(of: SessionEvent?.self) { group in
            group.addTask {
                for await event in stream { return event }
                return nil
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }
}
