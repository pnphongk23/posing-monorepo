import Foundation
import XCTest
@testable import iosApp

@MainActor
final class DeleteAccountTests: XCTestCase {
    func test204ClearsCredentialsAndReachesSignedOut() async {
        let storage = DeleteTestTokenStorage(credentials: deleteTestCredentials)
        let model = makeModel(storage: storage, deleteAccount: { _ in })
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
        let model = makeModel(storage: storage) { _ in
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
        let model = makeModel(storage: storage) { _ in
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

    func test409RunsTheAppleSheetOnceAndDeletesWithTheCode() async {
        let storage = DeleteTestTokenStorage(credentials: deleteTestCredentials)
        let calls = DeleteTestCodeLog()
        let apple = DeleteTestCounter()
        let model = makeModel(
            storage: storage,
            deleteAccount: { code in
                calls.append(code)
                if code == nil { throw AccountDeletionError.appleReauthRequired }
            },
            appleReauthorize: {
                apple.increment()
                return "apple-code-123"
            }
        )
        model.start()
        await waitUntil("signed in") { if case .signedIn = model.state { return true }; return false }

        model.deleteAccount()
        await waitUntil("signed out") { model.state == .signedOut }

        XCTAssertEqual(apple.value, 1, "the Apple sheet runs exactly once")
        XCTAssertEqual(calls.values, [nil, "apple-code-123"], "the retry carries the fresh code")
        XCTAssertNil(storage.loadCredentials())
        XCTAssertNil(model.deleteAccountError)
    }

    /// A cancelled sheet sends no second request, so the server was never asked to delete anything.
    func testCancelledAppleSheetSendsOneRequestAndSaysNothingWasDeleted() async {
        let storage = DeleteTestTokenStorage(credentials: deleteTestCredentials)
        let calls = DeleteTestCodeLog()
        let model = makeModel(
            storage: storage,
            deleteAccount: { code in
                calls.append(code)
                throw AccountDeletionError.appleReauthRequired
            },
            appleReauthorize: { throw CancellationError() }
        )
        model.start()
        await waitUntil("signed in") { if case .signedIn = model.state { return true }; return false }

        model.deleteAccount()
        await waitUntil("delete failure") { model.deleteAccountError != nil }

        XCTAssertEqual(calls.values, [nil], "exactly one request in total")
        XCTAssertEqual(model.deleteAccountError, "Deletion cancelled. Your account was not deleted.")
        XCTAssertNotNil(storage.loadCredentials())
        XCTAssertEqual(model.state, .signedIn(deleteTestAccount))
        XCTAssertFalse(model.isDeletingAccount)
    }

    /// The handshake allows one Apple confirmation. A second 409 is terminal for this attempt.
    func testSecond409IssuesNoThirdRequestAndSaysCouldNotConfirm() async {
        let storage = DeleteTestTokenStorage(credentials: deleteTestCredentials)
        let calls = DeleteTestCodeLog()
        let apple = DeleteTestCounter()
        let model = makeModel(
            storage: storage,
            deleteAccount: { code in
                calls.append(code)
                throw AccountDeletionError.appleReauthRequired
            },
            appleReauthorize: {
                apple.increment()
                return "apple-code-123"
            }
        )
        model.start()
        await waitUntil("signed in") { if case .signedIn = model.state { return true }; return false }

        model.deleteAccount()
        await waitUntil("delete failure") { model.deleteAccountError != nil }

        XCTAssertEqual(calls.values, [nil, "apple-code-123"], "no third request")
        XCTAssertEqual(apple.value, 1, "no second Apple sheet")
        XCTAssertEqual(model.deleteAccountError, "Couldn't confirm with Apple. Try again.")
        XCTAssertNotNil(storage.loadCredentials())
    }

    func testAppleIdentityMismatchSurfacesItsOwnCopyAndKeepsTheSession() async {
        let storage = DeleteTestTokenStorage(credentials: deleteTestCredentials)
        let calls = DeleteTestCodeLog()
        let model = makeModel(
            storage: storage,
            deleteAccount: { code in
                calls.append(code)
                throw AccountDeletionError.appleIdentityMismatch
            }
        )
        model.start()
        await waitUntil("signed in") { if case .signedIn = model.state { return true }; return false }

        model.deleteAccount()
        await waitUntil("delete failure") { model.deleteAccountError != nil }

        XCTAssertEqual(calls.values, [nil])
        XCTAssertEqual(model.deleteAccountError, "That Apple ID doesn't match this account. Try again.")
        XCTAssertNotNil(storage.loadCredentials())
    }

    /// A google/email account is deleted by the first request; the Apple sheet never opens.
    func testNonAppleAccountDeletesOnTheFirstRequestWithoutApple() async {
        let storage = DeleteTestTokenStorage(credentials: deleteTestCredentials)
        let calls = DeleteTestCodeLog()
        let apple = DeleteTestCounter()
        let model = makeModel(
            storage: storage,
            deleteAccount: { code in calls.append(code) },
            appleReauthorize: {
                apple.increment()
                return "apple-code-123"
            }
        )
        model.start()
        await waitUntil("signed in") { if case .signedIn = model.state { return true }; return false }

        model.deleteAccount()
        await waitUntil("signed out") { model.state == .signedOut }

        XCTAssertEqual(calls.values, [nil], "one request, no code")
        XCTAssertEqual(apple.value, 0, "no Apple call for a non-Apple account")
        XCTAssertNil(storage.loadCredentials())
    }

    func testAppleSheetFailureKeepsTheAccountAndSaysRetry() async {
        let storage = DeleteTestTokenStorage(credentials: deleteTestCredentials)
        let model = makeModel(
            storage: storage,
            deleteAccount: { _ in throw AccountDeletionError.appleReauthRequired },
            appleReauthorize: { throw AppleReauthorizationError(message: "Apple did not return an authorization code.") }
        )
        model.start()
        await waitUntil("signed in") { if case .signedIn = model.state { return true }; return false }

        model.deleteAccount()
        await waitUntil("delete failure") { model.deleteAccountError != nil }

        XCTAssertEqual(model.deleteAccountError, "Couldn't confirm with Apple. Try again.")
        XCTAssertNotNil(storage.loadCredentials())
        XCTAssertEqual(model.state, .signedIn(deleteTestAccount))
    }

    func testDoubleConfirmIssuesExactlyOneRequest() async {
        let storage = DeleteTestTokenStorage(credentials: deleteTestCredentials)
        let calls = DeleteTestCounter()
        let model = makeModel(storage: storage) { _ in
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

    /// The whole deletion reset, with the pieces the app actually wires together: the Account screen
    /// ends up signed out, the Saved surface falls back to its sign-in gate, the persisted Saved rows
    /// are gone, and the store identity is released exactly once.
    @MainActor func test204ResetsSessionSavedCatalogAndPurchaseIdentity() async throws {
        let temp = try DeleteTestDatabase()
        defer { temp.cleanUp() }
        try await temp.seedSavedRow("mine-1")
        let cache = PoseCatalogCacheStore(repository: temp.repository, scheduler: DeleteTestRefreshScheduler())

        let storage = DeleteTestTokenStorage(credentials: deleteTestCredentials)
        let boundary = SessionBoundary(tokenStorage: storage)
        let provider = FakePurchasesProvider()
        let purchases = RevenueCatAdapter(provider: provider, entitlementID: FakePurchasesProvider.entitlementKey)
        let coordinator = SessionScopeCoordinator(
            boundary: boundary,
            cache: cache,
            purchases: purchases,
            readAccount: { deleteTestAccount }
        )
        coordinator.start()
        await waitUntil("the store identity is linked") { purchases.linkedAccountID == deleteTestAccount.id }

        let model = makeModel(storage: storage, boundary: boundary, deleteAccount: { _ in })
        model.start()
        await waitUntil("signed in") { if case .signedIn = model.state { return true }; return false }
        let seeded = try await temp.savedRowCount()
        XCTAssertEqual(seeded, 1, "the account starts with a Saved row")

        model.deleteAccount()
        await waitUntil("signed out") { model.state == .signedOut }
        // Polled inline rather than through the closure: `temp` is a test DB holder, and capturing it
        // in an escaping async closure is exactly the data race Swift 6 rejects.
        var remainingSaved = try await temp.savedRowCount()
        let savedDeadline = Date().addingTimeInterval(5)
        while remainingSaved != 0, Date() < savedDeadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
            remainingSaved = try await temp.savedRowCount()
        }
        await waitUntil("the store identity is released") { provider.logOutCalls == 1 }

        let hasSession = await boundary.hasStoredSession()
        XCTAssertFalse(hasSession)
        XCTAssertEqual(
            SavedSurfaceStage.resolve(isSessionResolved: true, isSignedIn: hasSession),
            .signInRequired,
            "the Saved surface offers sign-in instead of another Account's rows"
        )
        XCTAssertEqual(remainingSaved, 0, "the Saved catalog is cleared")
        XCTAssertEqual(provider.logOutCalls, 1, "the store identity is released exactly once")
        XCTAssertNil(purchases.linkedAccountID)
    }

    /// A failed deletion changes nothing: the session, the Saved rows and the store identity survive
    /// so the user can retry.
    @MainActor func test503LeavesSessionCatalogAndPurchaseIdentityUntouched() async throws {
        let temp = try DeleteTestDatabase()
        defer { temp.cleanUp() }
        try await temp.seedSavedRow("mine-1")
        let cache = PoseCatalogCacheStore(repository: temp.repository, scheduler: DeleteTestRefreshScheduler())

        let storage = DeleteTestTokenStorage(credentials: deleteTestCredentials)
        let boundary = SessionBoundary(tokenStorage: storage)
        let provider = FakePurchasesProvider()
        let purchases = RevenueCatAdapter(provider: provider, entitlementID: FakePurchasesProvider.entitlementKey)
        let coordinator = SessionScopeCoordinator(
            boundary: boundary,
            cache: cache,
            purchases: purchases,
            readAccount: { deleteTestAccount }
        )
        coordinator.start()
        await waitUntil("the store identity is linked") { purchases.linkedAccountID == deleteTestAccount.id }

        let model = makeModel(storage: storage, boundary: boundary) { _ in
            throw PoseAPIError(code: "503", message: "Account deletion is pending runtime validation")
        }
        model.start()
        await waitUntil("signed in") { if case .signedIn = model.state { return true }; return false }

        model.deleteAccount()
        await waitUntil("delete failure") { model.deleteAccountError != nil }

        XCTAssertEqual(model.state, .signedIn(deleteTestAccount))
        let hasSession = await boundary.hasStoredSession()
        XCTAssertTrue(hasSession)
        let remainingSaved = try await temp.savedRowCount()
        XCTAssertEqual(remainingSaved, 1, "a failed deletion must not touch the Saved catalog")
        XCTAssertEqual(provider.logOutCalls, 0, "a failed deletion must not release the store identity")
    }

    func testConfirmationCopyStatesIrreversibilityWithoutSubscriptionClaim() {
        let copy = AccountStateCopy.deleteAccountConfirmationMessage
        XCTAssertTrue(copy.localizedCaseInsensitiveContains("cannot be recovered"))
        XCTAssertFalse(copy.localizedCaseInsensitiveContains("subscription"))
        XCTAssertFalse(copy.localizedCaseInsensitiveContains("Apple"))
    }

    /// `boundary` is injectable so a test that also runs `SessionScopeCoordinator` wires *one*
    /// boundary: two instances over the same storage would not share session events, and the
    /// coordinator would never learn about the sign-out.
    private func makeModel(
        storage: DeleteTestTokenStorage,
        boundary sharedBoundary: SessionBoundary? = nil,
        deleteAccount: @escaping AccountSessionModel.AccountDeleter,
        appleReauthorize: @escaping AccountSessionModel.AppleReauthorizer = { "unused-apple-code" }
    ) -> AccountSessionModel {
        AccountSessionModel(
            boundary: sharedBoundary ?? SessionBoundary(tokenStorage: storage),
            readAccount: { deleteTestAccount },
            signInAction: SignInAction(start: {}),
            deleteAccount: deleteAccount,
            appleReauthorize: appleReauthorize
        )
    }

    private func waitUntil(_ label: String, _ condition: @escaping () async -> Bool) async {
        for _ in 0..<400 {
            if await condition() { return }
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

/// One temp catalog plus the rows a deletion reset has to tell apart.
private final class DeleteTestDatabase {
    let root: URL
    let database: AppDatabase

    var repository: PoseRepository { PoseRepository(database: database) }

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("delete-account-\(UUID().uuidString)", isDirectory: true)
        database = try AppDatabase(
            location: AppDatabaseLocation(url: root.appendingPathComponent("aipose.db"), kind: .freshInstall)
        )
    }

    func seedSavedRow(_ id: String) async throws {
        try await repository.upsert([
            PoseRecord(
                poseId: id,
                ownerAccountId: PoseCatalogBucket.saved.rawValue,
                name: "Mine",
                description: nil,
                tags: "[]",
                difficulty: nil,
                bodyParts: "[]",
                status: PoseCatalogMapping.savedStatus,
                originalPath: "",
                skeletonPath: "/s.png",
                thumbnailPath: "/t.png",
                currentJobId: nil,
                createdAt: "2024-03-01T00:00:00Z",
                updatedAt: "2024-03-01T00:00:00Z"
            )
        ])
    }

    func savedRowCount() async throws -> Int {
        try await repository.cached().filter { $0.status == PoseCatalogMapping.savedStatus }.count
    }

    func cleanUp() {
        try? database.pool.close()
        try? FileManager.default.removeItem(at: root)
    }
}

private struct DeleteTestRefreshScheduler: PoseRefreshScheduling {
    func schedule(_ operation: @escaping @Sendable () async -> Void) {}
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

/// Records the authorization code of every delete request, in order, so the handshake is observable.
private final class DeleteTestCodeLog: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String?] = []

    func append(_ code: String?) { lock.lock(); recorded.append(code); lock.unlock() }

    var values: [String?] { lock.lock(); defer { lock.unlock() }; return recorded }
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
