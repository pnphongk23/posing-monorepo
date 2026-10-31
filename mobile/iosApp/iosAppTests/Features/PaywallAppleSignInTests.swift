import Combine
import XCTest
@testable import iosApp

/// App Review 4.8: the paywall's signed-out state offers Google, so it must offer Sign in with
/// Apple too — first, with the same geometry, and landing in the same "continue to plans" outcome.
/// These tests pin the ordering contract, the accessibility ids Maestro/QA query, and the three
/// resolved outcomes of the Apple handoff (success, cancel, failure).
@MainActor
final class PaywallAppleSignInTests: XCTestCase {
    // MARK: - Ordering and identifiers

    func testSignInRequiredPaywallOffersAppleBeforeGoogle() {
        XCTAssertEqual(
            PaywallSignInOption.allCases,
            [.apple, .google, .email],
            "Apple must be offered first — guideline 4.8 forbids making it the subordinate option"
        )
        XCTAssertEqual(PaywallSignInOption.allCases.first, .apple)
        XCTAssertEqual(PaywallSignInOption.apple.accessibilityIdentifier, "paywall.signin.apple")
        XCTAssertEqual(PaywallSignInOption.google.accessibilityIdentifier, "paywall.signin")
        XCTAssertEqual(PaywallSignInOption.email.accessibilityIdentifier, "signin.emailEntry")
    }

    /// The visible wordmark is the shared `ContinueWithAppleButton` copy, not paywall-local text:
    /// one Apple control, one label.
    func testAppleOptionUsesTheSharedAppleButtonCopy() {
        XCTAssertEqual(AppleSignInCopy.title, "Sign in with Apple")
        XCTAssertTrue(AppleSignInCopy.hasVisibleContrast, "the black-on-black regression stays fixed everywhere")
    }

    func testEveryPaywallIdentifierIsDeclaredOnceAndRenderedFromTheConstants() throws {
        let source = try supportScreensSource()
        let identifiers = [
            PaywallAccessibilityID.close,
            PaywallAccessibilityID.signInApple,
            PaywallAccessibilityID.signInGoogle,
            PaywallAccessibilityID.signInEmail,
            PaywallAccessibilityID.planAnnual,
            PaywallAccessibilityID.planMonthly,
            PaywallAccessibilityID.status,
            PaywallAccessibilityID.cta,
        ]

        for identifier in identifiers {
            XCTAssertEqual(
                occurrences(of: "\"\(identifier)\"", in: source),
                1,
                "\(identifier) must be declared exactly once, so a query id cannot be shadowed or renamed in place"
            )
        }
        XCTAssertEqual(Set(identifiers).count, identifiers.count, "no id may be reused for two elements")
    }

    func testPlanCardIdentifiersFollowThePackageTypeNotTheStoreID() {
        let annual = PurchaseProduct(identifier: "premium_annual_store", packageType: .annual, localizedPrice: "$39.99", period: "year")
        let monthly = PurchaseProduct(identifier: "premium_monthly_store", packageType: .monthly, localizedPrice: "$5.99", period: "month")
        let other = PurchaseProduct(identifier: "premium_lifetime_store", packageType: .other, localizedPrice: "$99.99", period: nil)

        XCTAssertEqual(PaywallAccessibilityID.plan(annual), "paywall.plan.annual")
        XCTAssertEqual(PaywallAccessibilityID.plan(monthly), "paywall.plan.monthly")
        XCTAssertNotEqual(PaywallAccessibilityID.plan(annual), PaywallAccessibilityID.plan(monthly))
        XCTAssertEqual(
            PaywallAccessibilityID.plan(other),
            PaywallAccessibilityID.plan(monthly),
            "a dropped package type never renders, so it cannot claim the annual card"
        )
    }

    // MARK: - The Apple handoff's outcomes

    func testSuccessfulAppleSignInContinuesToPlans() async {
        let storage = InMemoryTokenStorage()
        let gateway = FakePaywallGateway(nextLoad: offering)
        let model = makeModel(
            gateway: gateway,
            storage: storage,
            appleSignIn: { _, _, _ in storage.saveCredentials(storedSession) },
            appleProvider: StubAppleProvider()
        )

        model.start()
        await waitUntil("sign in required") { model.phase == .signInRequired }

        await model.signInWithApple()

        XCTAssertNil(model.authError, "a completed sign-in is not an error")
        XCTAssertTrue(model.isSignedIn)
        XCTAssertEqual(gateway.loadCount, 1, "the paywall continues to plans, exactly like the Google path")
        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.plans.map(\.identifier), ["annual", "monthly"])
        XCTAssertFalse(model.isAuthenticating)
    }

    /// Closing the system Apple sheet is a decision, not a failure: no banner, no phase change.
    func testCancelledAppleSignInShowsNoErrorBanner() async {
        let gateway = FakePaywallGateway(nextLoad: offering)
        let model = makeModel(
            gateway: gateway,
            storage: InMemoryTokenStorage(),
            appleSignIn: { _, _, _ in XCTFail("a cancelled sheet never reaches the backend") },
            appleProvider: StubAppleProvider(error: CancellationError())
        )

        model.start()
        await waitUntil("sign in required") { model.phase == .signInRequired }

        await model.signInWithApple()

        XCTAssertNil(model.authError, "cancelling is not an error the user has to dismiss")
        XCTAssertEqual(model.phase, .signInRequired)
        XCTAssertEqual(gateway.loadCount, 0)
        XCTAssertFalse(model.isAuthenticating)
    }

    func testFailedAppleSignInShowsTheTruthfulErrorAndStaysOnSignIn() async {
        let gateway = FakePaywallGateway(nextLoad: offering)
        let model = makeModel(
            gateway: gateway,
            storage: InMemoryTokenStorage(),
            appleSignIn: { _, _, _ in throw PaywallAppleTestError.backend },
            appleProvider: StubAppleProvider()
        )

        model.start()
        await waitUntil("sign in required") { model.phase == .signInRequired }

        await model.signInWithApple()

        XCTAssertEqual(model.authError, PaywallAppleTestError.backendText)
        XCTAssertEqual(model.phase, .signInRequired)
        XCTAssertEqual(gateway.loadCount, 0, "a failed handoff never loads plans")
        XCTAssertFalse(model.isAuthenticating)
    }

    // MARK: - Helpers

    private func makeModel(
        gateway: FakePaywallGateway,
        storage: InMemoryTokenStorage,
        appleSignIn: @escaping AppleSignInAction.SignIn,
        appleProvider: StubAppleProvider
    ) -> PaywallModel {
        PaywallModel(
            gateway: gateway,
            boundary: SessionBoundary(tokenStorage: storage),
            signInAction: SignInAction(start: {}),
            appleSignInAction: AppleSignInAction(provider: appleProvider, signIn: appleSignIn)
        )
    }

    private func supportScreensSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Features
            .deletingLastPathComponent() // iosAppTests
            .deletingLastPathComponent() // iosApp (project dir)
            .appendingPathComponent("iosApp/Features/Support/SupportScreens.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    @MainActor
    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 3,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(condition(), "Timed out waiting for \(description)", file: file, line: line)
    }
}

private let storedSession = SessionCredentials(accessToken: "access", refreshToken: "refresh")

private let annual = PurchaseProduct(identifier: "annual", packageType: .annual, localizedPrice: "$39.99", period: "year")
private let monthly = PurchaseProduct(identifier: "monthly", packageType: .monthly, localizedPrice: "$5.99", period: "month")
private let offering = PurchaseSnapshot(state: .notEntitled, products: [monthly, annual])

private enum PaywallAppleTestError: Error, LocalizedError, Sendable {
    case backend

    static let backendText = "Apple sign-in failed."

    var errorDescription: String? { Self.backendText }
}

@MainActor
private final class StubAppleProvider: AppleAuthorizationProviding {
    private let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func authorize(_ request: AppleAuthorizationRequest) async throws -> AppleAuthorizationResult {
        if let error { throw error }
        return AppleAuthorizationResult(identityToken: "identity-token", rawNonce: request.rawNonce, fullName: nil)
    }
}

@MainActor
private final class FakePaywallGateway: PurchaseGateway {
    private let subject: CurrentValueSubject<PurchaseSnapshot, Never>
    var snapshot: PurchaseSnapshot { subject.value }
    var snapshots: AnyPublisher<PurchaseSnapshot, Never> { subject.eraseToAnyPublisher() }

    private let nextLoad: PurchaseSnapshot
    private(set) var loadCount = 0

    init(nextLoad: PurchaseSnapshot) {
        self.nextLoad = nextLoad
        self.subject = CurrentValueSubject(PurchaseSnapshot(state: .notEntitled, products: []))
    }

    func loadOffering() async -> PurchaseSnapshot {
        loadCount += 1
        subject.send(nextLoad)
        return nextLoad
    }

    func purchase(packageID: String) async -> PurchaseSnapshot { subject.value }
    func restore() async -> PurchaseSnapshot { subject.value }
}

private final class InMemoryTokenStorage: TokenStoring, @unchecked Sendable {
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
