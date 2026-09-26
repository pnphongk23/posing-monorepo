import SwiftUI
import XCTest
@testable import iosApp

/// Fake purchase gateway: no StoreKit, no RevenueCat. Mirrors the KMP `FakePurchaseGateway`
/// contract for the paywall's state machine.
@MainActor
private final class FakePurchaseGateway: PurchaseGateway {
    var snapshot: PurchaseSnapshot
    var nextLoad: PurchaseSnapshot
    var nextPurchase: PurchaseSnapshot
    var nextRestore: PurchaseSnapshot

    private(set) var loadCount = 0
    private(set) var purchasedProductIDs: [String] = []
    private(set) var restoreCount = 0

    init(
        snapshot: PurchaseSnapshot = PurchaseSnapshot(state: .notEntitled, products: [], errorCode: nil),
        nextLoad: PurchaseSnapshot? = nil,
        nextPurchase: PurchaseSnapshot? = nil,
        nextRestore: PurchaseSnapshot? = nil
    ) {
        self.snapshot = snapshot
        self.nextLoad = nextLoad ?? snapshot
        self.nextPurchase = nextPurchase ?? snapshot
        self.nextRestore = nextRestore ?? snapshot
    }

    func loadOffering() async -> PurchaseSnapshot {
        loadCount += 1
        snapshot = nextLoad
        return snapshot
    }

    func purchase(productId: String) async -> PurchaseSnapshot {
        purchasedProductIDs.append(productId)
        snapshot = nextPurchase
        return snapshot
    }

    func restore() async -> PurchaseSnapshot {
        restoreCount += 1
        snapshot = nextRestore
        return snapshot
    }
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

private let session = SessionCredentials(accessToken: "access", refreshToken: "refresh")

private let annual = PurchaseProduct(
    identifier: PaywallPlanCatalog.annualProductID,
    localizedPrice: "$39.99",
    period: "year"
)
private let monthly = PurchaseProduct(
    identifier: PaywallPlanCatalog.monthlyProductID,
    localizedPrice: "$5.99",
    period: "month"
)
private let readyOffering = PurchaseSnapshot(state: .notEntitled, products: [monthly, annual], errorCode: nil)

@MainActor
final class PaywallModelTests: XCTestCase {
    private func makeModel(
        gateway: FakePurchaseGateway,
        storage: InMemoryTokenStorage = InMemoryTokenStorage(credentials: session),
        signIn: @escaping SignInAction.Starter = {}
    ) -> PaywallModel {
        PaywallModel(
            gateway: gateway,
            boundary: SessionBoundary(tokenStorage: storage),
            signInAction: SignInAction(start: signIn)
        )
    }

    func testSignedOutTriggerAsksForSignInBeforeAnyPurchase() async {
        let gateway = FakePurchaseGateway(nextLoad: readyOffering)
        let model = makeModel(gateway: gateway, storage: InMemoryTokenStorage())

        model.start()
        await waitUntil("sign in required") { model.phase == .signInRequired }
        XCTAssertEqual(gateway.loadCount, 0, "No offering load before the Account-bound purchase can start")
        XCTAssertTrue(gateway.purchasedProductIDs.isEmpty)
    }

    func testSignedInLoadsOfferingAndHighlightsAnnual() async {
        let gateway = FakePurchaseGateway(nextLoad: readyOffering)
        let model = makeModel(gateway: gateway)

        model.start()
        await waitUntil("ready") { model.phase == .ready }
        XCTAssertEqual(gateway.loadCount, 1)
        XCTAssertEqual(model.plans.map(\.identifier), [PaywallPlanCatalog.annualProductID, PaywallPlanCatalog.monthlyProductID])
        XCTAssertEqual(model.selectedProductID, PaywallPlanCatalog.annualProductID, "Annual is the highlighted default")
        XCTAssertEqual(model.ctaTitle, "Continue with Annual")
    }

    func testSelectingMonthlyChangesCTAAndSummary() async {
        let gateway = FakePurchaseGateway(nextLoad: readyOffering)
        let model = makeModel(gateway: gateway)
        model.start()
        await waitUntil("ready") { model.phase == .ready }

        model.select(PaywallPlanCatalog.monthlyProductID)
        XCTAssertEqual(model.ctaTitle, "Continue with Monthly")
        XCTAssertEqual(
            PaywallPlanCatalog.summaryLine(for: monthly),
            "$5.99 billed today. Auto-renews monthly until you cancel."
        )
    }

    func testPurchaseConfirmsEntitlement() async {
        let gateway = FakePurchaseGateway(
            nextLoad: readyOffering,
            nextPurchase: PurchaseSnapshot(state: .entitled, products: [monthly, annual], errorCode: nil)
        )
        let model = makeModel(gateway: gateway)
        model.start()
        await waitUntil("ready") { model.phase == .ready }

        await model.purchase()
        XCTAssertEqual(gateway.purchasedProductIDs, [PaywallPlanCatalog.annualProductID])
        XCTAssertEqual(model.phase, .entitled)
        XCTAssertEqual(model.statusMessage, "Premium access confirmed.")
    }

    func testCancelledPurchaseNeverReportsAccess() async {
        let gateway = FakePurchaseGateway(
            nextLoad: readyOffering,
            nextPurchase: PurchaseSnapshot(state: .purchaseCancelled, products: [monthly, annual], errorCode: nil)
        )
        let model = makeModel(gateway: gateway)
        model.start()
        await waitUntil("ready") { model.phase == .ready }

        await model.purchase()
        XCTAssertEqual(model.phase, .purchaseCancelled)
        XCTAssertEqual(model.statusMessage, "Purchase cancelled. No access was granted.")
    }

    func testFailedPurchaseIsRetryableAndKeepsPlans() async {
        let gateway = FakePurchaseGateway(
            nextLoad: readyOffering,
            nextPurchase: PurchaseSnapshot(state: .purchaseFailed, products: [monthly, annual], errorCode: nil)
        )
        let model = makeModel(gateway: gateway)
        model.start()
        await waitUntil("ready") { model.phase == .ready }

        await model.purchase()
        XCTAssertEqual(model.phase, .purchaseFailed)
        XCTAssertFalse(model.plans.isEmpty, "A failed purchase must not throw the plans away")
        XCTAssertEqual(model.ctaTitle, "Continue with Annual")
    }

    func testUnconfiguredSdkIsTruthfulAndRetryable() async {
        let gateway = FakePurchaseGateway(nextLoad: PurchaseSnapshot(state: .unconfigured, products: [], errorCode: nil))
        let model = makeModel(gateway: gateway)
        model.start()
        await waitUntil("unavailable") { model.phase == .unavailable("Premium is temporarily unavailable. Please try again later.") }
        XCTAssertTrue(model.plans.isEmpty, "Never fabricate purchasable plans")
        XCTAssertEqual(model.ctaTitle, "Plans unavailable")

        gateway.nextLoad = readyOffering
        await model.retry()
        XCTAssertEqual(model.phase, .ready)
    }

    func testNoOfferingIsReportedSeparatelyFromUnconfigured() async {
        let gateway = FakePurchaseGateway(snapshot: PurchaseSnapshot(state: .noOffering, products: [], errorCode: nil))
        let model = makeModel(gateway: gateway)
        model.start()
        await waitUntil("no offering") { model.phase == .unavailable("Plans are temporarily unavailable. Retry to check again.") }
    }

    func testEmptyOfferingDoesNotRenderAnEmptyPlanList() async {
        let gateway = FakePurchaseGateway(nextLoad: PurchaseSnapshot(state: .notEntitled, products: [], errorCode: nil))
        let model = makeModel(gateway: gateway)
        model.start()
        await waitUntil("unavailable") { model.phase == .unavailable("Plans are temporarily unavailable. Retry to check again.") }
    }

    func testRestoreUsesGatewayAndCanGrantAccess() async {
        let gateway = FakePurchaseGateway(
            nextLoad: readyOffering,
            nextRestore: PurchaseSnapshot(state: .entitled, products: [monthly, annual], errorCode: nil)
        )
        let model = makeModel(gateway: gateway)
        model.start()
        await waitUntil("ready") { model.phase == .ready }

        await model.restore()
        XCTAssertEqual(gateway.restoreCount, 1)
        XCTAssertEqual(model.phase, .entitled)
    }

    func testExpiredEntitlementCanBuyAgain() async {
        let gateway = FakePurchaseGateway(nextLoad: PurchaseSnapshot(state: .expired, products: [monthly, annual], errorCode: nil))
        let model = makeModel(gateway: gateway)
        model.start()
        await waitUntil("ready") { model.phase == .ready }
        XCTAssertEqual(model.ctaTitle, "Continue with Annual")
    }

    func testSignInFailureSurfacesErrorAndKeepsRequiringSignIn() async {
        let gateway = FakePurchaseGateway(nextLoad: readyOffering)
        let model = makeModel(
            gateway: gateway,
            storage: InMemoryTokenStorage(),
            signIn: { throw OAuthCallbackError.invalidCallback }
        )
        model.start()
        await waitUntil("sign in required") { model.phase == .signInRequired }

        await model.signIn()
        XCTAssertEqual(model.authError, "Unable to start Google sign-in.")
        XCTAssertEqual(model.phase, .signInRequired)
        XCTAssertFalse(model.isAuthenticating)
        XCTAssertEqual(gateway.loadCount, 0)
    }

    func testSignInSuccessResumesIntoPlans() async {
        let storage = InMemoryTokenStorage()
        let boundary = SessionBoundary(tokenStorage: storage)
        let gateway = FakePurchaseGateway(nextLoad: readyOffering)
        let model = PaywallModel(
            gateway: gateway,
            boundary: boundary,
            signInAction: SignInAction(start: { await boundary.saveCredentials(session) })
        )

        model.start()
        await waitUntil("sign in required") { model.phase == .signInRequired }
        await model.signIn()

        await waitUntil("ready") { model.phase == .ready }
        XCTAssertTrue(model.isSignedIn)
        XCTAssertNil(model.authError)
        XCTAssertEqual(gateway.loadCount, 1)
    }

    /// Email sign-in seam (PLAN §4): the sheet signed in through `SessionBoundary`, so re-checking
    /// the boundary lands in the same isSignedIn/loadPlans() outcome as the Google path.
    func testResumeAfterEmailSignInLoadsPlansWhenSessionStored() async {
        let storage = InMemoryTokenStorage()
        let boundary = SessionBoundary(tokenStorage: storage)
        let gateway = FakePurchaseGateway(nextLoad: readyOffering)
        let model = PaywallModel(
            gateway: gateway,
            boundary: boundary,
            signInAction: SignInAction(start: {})
        )
        model.start()
        await waitUntil("sign in required") { model.phase == .signInRequired }

        // Simulate the sheet having signed in through the same boundary.
        await boundary.saveCredentials(session)
        await model.resumeAfterEmailSignIn()

        await waitUntil("ready") { model.phase == .ready }
        XCTAssertTrue(model.isSignedIn)
        XCTAssertNil(model.authError)
        XCTAssertEqual(gateway.loadCount, 1)
    }

    /// Cancelling the sheet without signing in leaves the gate exactly as it was.
    func testResumeAfterEmailSignInWithoutSessionStaysOnSignInRequired() async {
        let gateway = FakePurchaseGateway(nextLoad: readyOffering)
        let model = makeModel(gateway: gateway, storage: InMemoryTokenStorage())
        model.start()
        await waitUntil("sign in required") { model.phase == .signInRequired }

        await model.resumeAfterEmailSignIn()

        XCTAssertEqual(model.phase, .signInRequired)
        XCTAssertFalse(model.isSignedIn)
        XCTAssertEqual(gateway.loadCount, 0)
    }

    func testStartIsIdempotent() async {
        let gateway = FakePurchaseGateway(nextLoad: readyOffering)
        let model = makeModel(gateway: gateway)
        model.start()
        await waitUntil("ready") { model.phase == .ready }
        model.start()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(gateway.loadCount, 1)
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

final class PaywallPlanCatalogTests: XCTestCase {
    func testAnnualIsOrderedFirstAndUnknownProductsAreDropped() {
        let unknown = PurchaseProduct(identifier: "premium_weekly", localizedPrice: "$1.99", period: "week")
        let ordered = PaywallPlanCatalog.ordered([monthly, unknown, annual])
        XCTAssertEqual(ordered.map(\.identifier), [PaywallPlanCatalog.annualProductID, PaywallPlanCatalog.monthlyProductID])
    }

    func testLabelsPeriodsAndTerms() {
        XCTAssertEqual(PaywallPlanCatalog.label(for: annual), "Annual")
        XCTAssertEqual(PaywallPlanCatalog.label(for: monthly), "Monthly")
        XCTAssertEqual(PaywallPlanCatalog.periodLabel(for: annual), "year")
        XCTAssertEqual(PaywallPlanCatalog.periodLabel(for: monthly), "month")
        XCTAssertTrue(PaywallPlanCatalog.termsLine(for: annual).contains("yearly"))
        XCTAssertTrue(PaywallPlanCatalog.termsLine(for: monthly).contains("monthly"))
        XCTAssertTrue(PaywallPlanCatalog.isAnnual(annual))
        XCTAssertFalse(PaywallPlanCatalog.isAnnual(monthly))
    }

    /// StoreKit metadata wins: the prototype's hardcoded prices must not survive anywhere.
    func testSummaryUsesStoreKitPriceNotAHardcodedOne() {
        let localized = PurchaseProduct(identifier: PaywallPlanCatalog.annualProductID, localizedPrice: "₫999.000", period: "year")
        XCTAssertEqual(
            PaywallPlanCatalog.summaryLine(for: localized),
            "₫999.000 billed today. Auto-renews yearly until you cancel."
        )
    }
}
