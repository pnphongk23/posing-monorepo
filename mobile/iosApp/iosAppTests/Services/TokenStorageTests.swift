import XCTest
@testable import iosApp

private final class InMemoryTokenStorage: TokenStoring, @unchecked Sendable {
    private var credentials: SessionCredentials?
    func saveCredentials(_ credentials: SessionCredentials) { self.credentials = credentials }
    func loadCredentials() -> SessionCredentials? { credentials }
    func clearCredentials() { credentials = nil }
}

final class TokenStorageTests: XCTestCase {
    func testKeychainRoundTrip() {
        let storage = KeychainTokenStorage(service: "com.aipose.test.\(UUID().uuidString)")
        storage.clearCredentials()
        let creds = SessionCredentials(accessToken: "access", refreshToken: "refresh")
        storage.saveCredentials(creds)
        XCTAssertEqual(storage.loadCredentials(), creds)
        storage.clearCredentials()
        XCTAssertNil(storage.loadCredentials())
    }

    func testSessionBoundaryRefreshReplacesCredentials() async {
        let storage = InMemoryTokenStorage()
        let boundary = SessionBoundary(tokenStorage: storage)
        await boundary.saveCredentials(SessionCredentials(accessToken: "old", refreshToken: "rt"))
        let refreshed = await boundary.refresh { _ in
            SessionCredentials(accessToken: "new", refreshToken: "rt2")
        }
        XCTAssertTrue(refreshed)
        XCTAssertEqual(storage.loadCredentials()?.accessToken, "new")
    }

    func testSessionBoundaryRefreshFailureClears() async {
        let storage = InMemoryTokenStorage()
        let boundary = SessionBoundary(tokenStorage: storage)
        await boundary.saveCredentials(SessionCredentials(accessToken: "old", refreshToken: "rt"))
        let refreshed = await boundary.refresh { _ in nil }
        XCTAssertFalse(refreshed)
        XCTAssertNil(storage.loadCredentials())
    }
}
