import SwiftUI
import Combine
import UIKit
import XCTest
@testable import iosApp

/// Fake purchase gateway: no StoreKit, no RevenueCat. Mirrors the KMP `FakePurchaseGateway`
/// contract for the paywall's state machine.
@MainActor
private final class FakePurchaseGateway: PurchaseGateway {
    private let subject: CurrentValueSubject<PurchaseSnapshot, Never>
    var snapshot: PurchaseSnapshot { subject.value }
    var snapshots: AnyPublisher<PurchaseSnapshot, Never> { subject.eraseToAnyPublisher() }

    var nextLoad: PurchaseSnapshot
    var nextPurchase: PurchaseSnapshot
    var nextRestore: PurchaseSnapshot

    var loadStarted: AsyncSignal?
    var loadGate: SuspensionGate?
    var purchaseStarted: AsyncSignal?
    var purchaseGate: SuspensionGate?
    var restoreStarted: AsyncSignal?
    var restoreGate: SuspensionGate?

    private(set) var loadCount = 0
    private(set) var purchasedPackageIDs: [String] = []
    private(set) var restoreCount = 0

    init(
        snapshot: PurchaseSnapshot = PurchaseSnapshot(state: .notEntitled, products: []),
        nextLoad: PurchaseSnapshot? = nil,
        nextPurchase: PurchaseSnapshot? = nil,
        nextRestore: PurchaseSnapshot? = nil
    ) {
        self.subject = CurrentValueSubject(snapshot)
        self.nextLoad = nextLoad ?? snapshot
        self.nextPurchase = nextPurchase ?? snapshot
        self.nextRestore = nextRestore ?? snapshot
    }

    /// A push from outside the app's own taps: a delegate update, a purchase from another surface.
    func publish(_ snapshot: PurchaseSnapshot) {
        subject.send(snapshot)
    }

    func loadOffering() async -> PurchaseSnapshot {
        loadCount += 1
        loadStarted?.fire()
        await loadGate?.wait()
        subject.send(nextLoad)
        return subject.value
    }

    func purchase(packageID: String) async -> PurchaseSnapshot {
        purchasedPackageIDs.append(packageID)
        purchaseStarted?.fire()
        await purchaseGate?.wait()
        subject.send(nextPurchase)
        return subject.value
    }

    func restore() async -> PurchaseSnapshot {
        restoreCount += 1
        restoreStarted?.fire()
        await restoreGate?.wait()
        subject.send(nextRestore)
        return subject.value
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
    identifier: "annual",
    packageType: .annual,
    localizedPrice: "$39.99",
    period: "year"
)
private let monthly = PurchaseProduct(
    identifier: "monthly",
    packageType: .monthly,
    localizedPrice: "$5.99",
    period: "month"
)
private let readyOffering = PurchaseSnapshot(state: .notEntitled, products: [monthly, annual])

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
        XCTAssertTrue(gateway.purchasedPackageIDs.isEmpty)
    }

    func testSignedInLoadsOfferingAndHighlightsAnnual() async {
        let gateway = FakePurchaseGateway(nextLoad: readyOffering)
        let model = makeModel(gateway: gateway)

        model.start()
        await waitUntil("ready") { model.phase == .ready }
        XCTAssertEqual(gateway.loadCount, 1)
        XCTAssertEqual(model.plans.map(\.identifier), [annual.identifier, monthly.identifier])
        XCTAssertEqual(model.selectedProductID, annual.identifier, "Yearly is the highlighted default")
        // Board 11-01: the primary action is "Subscribe"; the selected plan is shown by the card,
        // not by the button's label.
        XCTAssertEqual(model.ctaTitle, "Subscribe")
        XCTAssertTrue(model.isCTAEnabled)
    }

    func testSelectingMonthlyChangesTheSelectedPlanAndSummary() async {
        let gateway = FakePurchaseGateway(nextLoad: readyOffering)
        let model = makeModel(gateway: gateway)
        model.start()
        await waitUntil("ready") { model.phase == .ready }

        model.select(monthly.identifier)
        XCTAssertEqual(model.ctaTitle, "Subscribe")
        XCTAssertEqual(
            model.planPresentations.first { $0.isSelected }?.title,
            "Monthly",
            "the card, not the CTA label, carries the selection"
        )
        XCTAssertEqual(
            PaywallPlanCatalog.summaryLine(for: monthly),
            "$5.99 billed today. Auto-renews monthly until you cancel."
        )
    }

    func testPurchaseConfirmsEntitlement() async {
        let gateway = FakePurchaseGateway(
            nextLoad: readyOffering,
            nextPurchase: PurchaseSnapshot(state: .entitled, products: [monthly, annual])
        )
        let model = makeModel(gateway: gateway)
        model.start()
        await waitUntil("ready") { model.phase == .ready }

        await model.purchase()
        XCTAssertEqual(gateway.purchasedPackageIDs, [annual.identifier])
        XCTAssertEqual(model.phase, .entitled)
        XCTAssertEqual(model.statusMessage, "Premium access confirmed.")
    }

    func testCancelledPurchaseNeverReportsAccess() async {
        let gateway = FakePurchaseGateway(
            nextLoad: readyOffering,
            nextPurchase: PurchaseSnapshot(state: .purchaseCancelled, products: [monthly, annual])
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
            nextPurchase: PurchaseSnapshot(state: .purchaseFailed, products: [monthly, annual])
        )
        let model = makeModel(gateway: gateway)
        model.start()
        await waitUntil("ready") { model.phase == .ready }

        await model.purchase()
        XCTAssertEqual(model.phase, .purchaseFailed)
        XCTAssertFalse(model.plans.isEmpty, "A failed purchase must not throw the plans away")
        // Board 11-08: a failed purchase promotes the recovery onto the primary action.
        XCTAssertEqual(model.ctaTitle, "Try again")
        XCTAssertTrue(model.isCTAEnabled, "the retry is tappable, not a dead button")
    }

    func testUnconfiguredSdkIsTruthfulAndRetryable() async {
        let gateway = FakePurchaseGateway(nextLoad: PurchaseSnapshot(state: .unconfigured, products: []))
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
        let gateway = FakePurchaseGateway(snapshot: PurchaseSnapshot(state: .noOffering, products: []))
        let model = makeModel(gateway: gateway)
        model.start()
        await waitUntil("no offering") { model.phase == .unavailable("Plans are temporarily unavailable. Retry to check again.") }
    }

    func testEmptyOfferingDoesNotRenderAnEmptyPlanList() async {
        let gateway = FakePurchaseGateway(nextLoad: PurchaseSnapshot(state: .notEntitled, products: []))
        let model = makeModel(gateway: gateway)
        model.start()
        await waitUntil("unavailable") { model.phase == .unavailable("Plans are temporarily unavailable. Retry to check again.") }
    }

    func testRestoreUsesGatewayAndCanGrantAccess() async {
        let gateway = FakePurchaseGateway(
            nextLoad: readyOffering,
            nextRestore: PurchaseSnapshot(state: .entitled, products: [monthly, annual])
        )
        let model = makeModel(gateway: gateway)
        model.start()
        await waitUntil("ready") { model.phase == .ready }

        await model.restore()
        XCTAssertEqual(gateway.restoreCount, 1)
        XCTAssertEqual(model.phase, .entitled)
    }

    func testExpiredEntitlementCanBuyAgain() async {
        let gateway = FakePurchaseGateway(nextLoad: PurchaseSnapshot(state: .expired, products: [monthly, annual]))
        let model = makeModel(gateway: gateway)
        model.start()
        await waitUntil("ready") { model.phase == .ready }
        XCTAssertEqual(model.ctaTitle, "Subscribe")
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

    /// M2 defence in depth: the adapter refuses a store call without a linked Account, and the
    /// paywall must send the user back to sign-in instead of showing plans it cannot sell.
    func testSignInRequiredSnapshotRoutsBackToSignIn() async {
        let gateway = FakePurchaseGateway(
            nextLoad: readyOffering,
            nextPurchase: PurchaseSnapshot(state: .signInRequired, products: [annual, monthly])
        )
        let model = makeModel(gateway: gateway)
        model.start()
        await waitUntil("ready") { model.phase == .ready }

        await model.purchase()

        XCTAssertEqual(model.phase, .signInRequired)
        XCTAssertTrue(model.plans.isEmpty)
        XCTAssertEqual(gateway.purchasedPackageIDs, [annual.identifier])
    }

    // MARK: - Account-dependent state (the gateway owns the entitlement)

    /// A sign-out while the offering is still loading must not paint plans for a dead session.
    func testSignOutDuringLoadOfferingDropsTheStaleResult() async {
        let storage = InMemoryTokenStorage(credentials: session)
        let boundary = SessionBoundary(tokenStorage: storage)
        let gateway = FakePurchaseGateway(nextLoad: readyOffering)
        let model = PaywallModel(
            gateway: gateway,
            boundary: boundary,
            signInAction: SignInAction(start: {})
        )
        let started = AsyncSignal()
        let gate = SuspensionGate()
        gateway.loadStarted = started
        gateway.loadGate = gate

        model.start()
        await started.wait()
        await boundary.signOut()
        gate.release()

        await waitUntil("sign in required") { model.phase == .signInRequired }
        XCTAssertTrue(model.plans.isEmpty, "A result that crossed sign-out must be dropped")
        XCTAssertFalse(model.isSignedIn)
    }

    func testPurchaseResultAfterSignOutIsRejected() async {
        let storage = InMemoryTokenStorage(credentials: session)
        let boundary = SessionBoundary(tokenStorage: storage)
        let gateway = FakePurchaseGateway(
            nextLoad: readyOffering,
            nextPurchase: PurchaseSnapshot(state: .entitled, products: [monthly, annual])
        )
        let model = PaywallModel(
            gateway: gateway,
            boundary: boundary,
            signInAction: SignInAction(start: {})
        )
        model.start()
        await waitUntil("ready") { model.phase == .ready }

        let started = AsyncSignal()
        let gate = SuspensionGate()
        gateway.purchaseStarted = started
        gateway.purchaseGate = gate

        let purchase = Task { await model.purchase() }
        await started.wait()
        await boundary.signOut()
        gate.release()
        await purchase.value

        await waitUntil("sign in required") { model.phase == .signInRequired }
        XCTAssertNotEqual(model.phase, .entitled)
    }

    /// Access removed elsewhere (another surface, a delegate update) is mirrored, so an open
    /// paywall never keeps showing premium.
    func testGatewayEntitlementDropClosesAnOpenPaywall() async {
        let gateway = FakePurchaseGateway(nextLoad: readyOffering)
        let model = makeModel(gateway: gateway)
        model.start()
        await waitUntil("ready") { model.phase == .ready }

        gateway.publish(PurchaseSnapshot(state: .entitled, products: [monthly, annual]))
        await waitUntil("entitled") { model.phase == .entitled }

        gateway.publish(PurchaseSnapshot(state: .notEntitled, products: [monthly, annual]))
        await waitUntil("not entitled") { model.phase != .entitled }
        XCTAssertNotEqual(model.phase, .entitled)
    }

    func testSignOutInvalidatesAnEntitledPaywall() async {
        let storage = InMemoryTokenStorage(credentials: session)
        let boundary = SessionBoundary(tokenStorage: storage)
        let gateway = FakePurchaseGateway(
            nextLoad: readyOffering,
            nextPurchase: PurchaseSnapshot(state: .entitled, products: [monthly, annual])
        )
        let model = PaywallModel(
            gateway: gateway,
            boundary: boundary,
            signInAction: SignInAction(start: {})
        )
        model.start()
        await waitUntil("ready") { model.phase == .ready }
        await model.purchase()
        XCTAssertEqual(model.phase, .entitled)

        await boundary.signOut()

        await waitUntil("sign in required") { model.phase == .signInRequired }
        XCTAssertTrue(model.plans.isEmpty)
        XCTAssertNil(model.selectedProductID)
        XCTAssertFalse(model.isSignedIn)
    }

    /// Repro: a stale offering result that crossed an identity transition must not park the sheet in
    /// a busy phase, and the new identity's settled snapshot must always be able to take over.
    func testStaleOfferingResultDuringIdentityTransitionDoesNotWedgeThePaywall() async {
        let storage = InMemoryTokenStorage(credentials: session)
        let boundary = SessionBoundary(tokenStorage: storage)
        let gateway = FakePurchaseGateway(nextLoad: readyOffering)
        let model = PaywallModel(
            gateway: gateway,
            boundary: boundary,
            signInAction: SignInAction(start: {})
        )

        let started = AsyncSignal()
        let gate = SuspensionGate()
        gateway.loadStarted = started
        gateway.loadGate = gate
        model.start()
        await started.wait()

        // The gateway enters an identity transition while the offering fetch is in flight, and the
        // fetch returns that transient state.
        gateway.publish(PurchaseSnapshot(state: .loading, products: []))
        gateway.nextLoad = PurchaseSnapshot(state: .loading, products: [])
        gate.release()

        await waitUntil("not busy") { !model.isBusy }
        XCTAssertNotEqual(model.phase, .processing, "A transient result must not own the busy phase")

        // The new identity settles: the settled snapshot must clear whatever the stale fetch left.
        gateway.publish(PurchaseSnapshot(state: .notEntitled, products: [monthly, annual]))
        await waitUntil("ready") { model.phase == .ready }

        XCTAssertFalse(model.isBusy)
        XCTAssertEqual(model.plans.count, 2)

        await model.purchase()
        XCTAssertEqual(gateway.purchasedPackageIDs, [annual.identifier], "Purchase must be reachable again")
    }

    /// A purchase superseded by a sign-in plus a newer restore must not release the newer
    /// operation's busy phase: the operation claim is a token, not a shared flag.
    func testSupersededOperationCannotReleaseTheCurrentOperation() async {
        let storage = InMemoryTokenStorage(credentials: session)
        let boundary = SessionBoundary(tokenStorage: storage)
        let gateway = FakePurchaseGateway(nextLoad: readyOffering)
        let model = PaywallModel(
            gateway: gateway,
            boundary: boundary,
            signInAction: SignInAction(start: {})
        )
        model.start()
        await waitUntil("ready") { model.phase == .ready }

        let purchaseStarted = AsyncSignal()
        let purchaseGate = SuspensionGate()
        gateway.purchaseStarted = purchaseStarted
        gateway.purchaseGate = purchaseGate
        let purchase = Task { await model.purchase() }
        await purchaseStarted.wait()

        // The session changes under the in-flight purchase (sign-out, then sign-in), and a new
        // operation starts before the stale purchase resolves.
        await boundary.signOut()
        await waitUntil("signed out") { model.phase == .signInRequired }
        await boundary.saveCredentials(session)

        let restoreStarted = AsyncSignal()
        let restoreGate = SuspensionGate()
        gateway.restoreStarted = restoreStarted
        gateway.restoreGate = restoreGate
        let restore = Task { await model.restore() }
        await restoreStarted.wait()
        XCTAssertEqual(model.phase, .processing)

        // The stale purchase resolves while the restore still owns the phase.
        purchaseGate.release()
        await purchase.value
        gateway.publish(PurchaseSnapshot(state: .notEntitled, products: [monthly, annual]))
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(model.phase, .processing, "The restore still owns the busy phase")

        restoreGate.release()
        await restore.value
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
    func testAnnualIsOrderedFirstAndOtherPackageTypesAreDropped() {
        let weekly = PurchaseProduct(identifier: "weekly", packageType: .other, localizedPrice: "$1.99", period: "week")
        let lifetime = PurchaseProduct(identifier: "lifetime", packageType: .other, localizedPrice: "$99.99", period: nil)
        let ordered = PaywallPlanCatalog.ordered([monthly, weekly, lifetime, annual])
        XCTAssertEqual(ordered.map(\.identifier), [annual.identifier, monthly.identifier])
    }

    /// A single-package offering still renders: monthly alone is a plan, not a crash and not a
    /// silently missing highlight.
    func testMonthlyOnlyOfferingKeepsOneSelectablePlan() {
        let ordered = PaywallPlanCatalog.ordered([monthly])
        XCTAssertEqual(ordered.map(\.identifier), [monthly.identifier])
        XCTAssertFalse(PaywallPlanCatalog.isAnnual(monthly))
        XCTAssertEqual(PaywallPlanCatalog.label(for: monthly), "Monthly")
    }

    /// Labels come from the package type, so a renamed store product cannot rename the plan.
    func testLabelsAreKeyedOnPackageTypeNotOnIdentifier() {
        let renamed = PurchaseProduct(identifier: "acme_tier_1", packageType: .annual, localizedPrice: "$1.00", period: nil)
        XCTAssertEqual(PaywallPlanCatalog.label(for: renamed), "Yearly")
        XCTAssertEqual(PaywallPlanCatalog.periodLabel(for: renamed), "year")
        XCTAssertTrue(PaywallPlanCatalog.isAnnual(renamed))
    }

    func testLabelsPeriodsAndTerms() {
        XCTAssertEqual(PaywallPlanCatalog.label(for: annual), "Yearly")
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
        let localized = PurchaseProduct(identifier: annual.identifier, packageType: .annual, localizedPrice: "₫999.000", period: "year")
        XCTAssertEqual(
            PaywallPlanCatalog.summaryLine(for: localized),
            "₫999.000 billed today. Auto-renews yearly until you cancel."
        )
    }
}

/// Board 11-02's derived figures ("$3.33 per month", "Save 44%") come from the store's localized
/// price strings. These pin the reading of those strings, including the locales the store can serve.
final class PaywallMoneyTests: XCTestCase {
    func testReadsTheAmountOutOfTheStoreFormattedPrice() {
        XCTAssertEqual(PaywallMoney.amount(from: "$39.99"), Decimal(string: "39.99"))
        XCTAssertEqual(PaywallMoney.amount(from: "$5.99"), Decimal(string: "5.99"))
        XCTAssertEqual(PaywallMoney.amount(from: "39,99 €"), Decimal(string: "39.99"))
        XCTAssertEqual(PaywallMoney.amount(from: "1.234,56 €"), Decimal(string: "1234.56"))
        XCTAssertEqual(PaywallMoney.amount(from: "$1,234.56"), Decimal(string: "1234.56"))
    }

    /// A three-digit trailing group is grouping, not a decimal mark: VND prices carry no decimals.
    func testThreeDigitTrailingGroupIsGrouping() {
        XCTAssertEqual(PaywallMoney.amount(from: "₫999.000"), Decimal(999_000))
        XCTAssertNil(PaywallMoney.style(of: "₫999.000")?.decimalSeparator)
        XCTAssertEqual(PaywallMoney.style(of: "₫999.000")?.fractionDigits, 0)
    }

    func testUnparsablePriceYieldsNoAmount() {
        XCTAssertNil(PaywallMoney.amount(from: "Free"))
        XCTAssertNil(PaywallMoney.amount(from: ""))
        XCTAssertNil(PaywallMoney.style(of: "—"))
    }

    func testDerivedFiguresKeepTheStoreFormat() {
        XCTAssertEqual(PaywallMoney.perMonth(annualTotal: Decimal(string: "39.99")!, like: "$39.99"), "$3.33")
        XCTAssertEqual(PaywallMoney.perMonth(annualTotal: Decimal(999_000), like: "₫999.000"), "₫83.250")
        XCTAssertEqual(PaywallMoney.perMonth(annualTotal: Decimal(string: "39.99")!, like: "39,99 €"), "3,33 €")
    }

    /// The badge is a promise about the price: it appears only when the offering supports it.
    func testSavingsPercentIsDerivedAndRefusesAnUnsupportableClaim() {
        XCTAssertEqual(
            PaywallMoney.savingsPercent(annualTotal: Decimal(string: "39.99")!, monthlyTotal: Decimal(string: "5.99")!),
            44
        )
        XCTAssertEqual(PaywallMoney.savingsPercent(annualTotal: Decimal(999_000), monthlyTotal: Decimal(199_000)), 58)
        XCTAssertNil(
            PaywallMoney.savingsPercent(annualTotal: Decimal(string: "39.99")!, monthlyTotal: Decimal(string: "3.00")!),
            "a yearly price that is not cheaper than twelve months must not claim a saving"
        )
        XCTAssertNil(PaywallMoney.savingsPercent(annualTotal: 0, monthlyTotal: 0))
    }
}

/// The plan-card copy the boards ask for, computed from the real packages.
final class PaywallPlanCopyTests: XCTestCase {
    func testAnnualCardCopyIsDerivedFromTheRealPrices() {
        XCTAssertEqual(PaywallPlanCopy.savingsBadge(annual: annual, monthly: monthly), "Save 44%")
        XCTAssertEqual(PaywallPlanCopy.annualDetail(for: annual), "$3.33 per month, billed $39.99 yearly")
        XCTAssertEqual(PaywallPlanCopy.detail(for: monthly), "Billed monthly")
    }

    /// A different offering produces different copy: nothing is typed in.
    func testDifferentPricesProduceDifferentCopy() {
        let dongAnnual = PurchaseProduct(identifier: "a", packageType: .annual, localizedPrice: "₫999.000", period: "year")
        let dongMonthly = PurchaseProduct(identifier: "m", packageType: .monthly, localizedPrice: "₫199.000", period: "month")
        XCTAssertEqual(PaywallPlanCopy.savingsBadge(annual: dongAnnual, monthly: dongMonthly), "Save 58%")
        XCTAssertEqual(PaywallPlanCopy.annualDetail(for: dongAnnual), "₫83.250 per month, billed ₫999.000 yearly")
    }

    /// No monthly package, or an unparsable price: the card states the billing cadence instead of
    /// inventing a per-month figure or a saving.
    func testCopyDegradesWithoutAComputablePrice() {
        XCTAssertNil(PaywallPlanCopy.savingsBadge(annual: annual, monthly: nil))
        let opaque = PurchaseProduct(identifier: "a", packageType: .annual, localizedPrice: "—", period: "year")
        XCTAssertEqual(PaywallPlanCopy.annualDetail(for: opaque), "Billed yearly")
    }

    /// The single benefit line stays inside what Premium actually unlocks.
    func testBenefitCopyIsShutterOnly() {
        XCTAssertEqual(PaywallPlanCopy.benefit, "Capture with the full pose camera")
        let forbidden = ["guide", "opacity", "grid", "timer", "ratio", "quota", "free shot", "offline pose", "share", "save"]
        for word in forbidden {
            XCTAssertFalse(
                PaywallPlanCopy.benefit.lowercased().contains(word),
                "Premium unlocks the shutter only; '\(word)' must not appear in the benefit line"
            )
        }
        XCTAssertFalse(PaywallPlanCopy.benefit.lowercased().contains("discover"))
        XCTAssertFalse(PaywallPlanCopy.benefit.lowercased().contains("keep"))
    }

    func testPlanAccessibilityLabelCarriesSelectionPriceAndRenewal() {
        let plan = PaywallPlanCopy.plan(annual, monthly: monthly, isSelected: true)
        XCTAssertEqual(plan.title, "Yearly")
        XCTAssertTrue(plan.accessibilityLabel.contains("selected"))
        XCTAssertTrue(plan.accessibilityLabel.contains("Save 44%"))
        XCTAssertTrue(plan.accessibilityLabel.contains("$3.33 per month, billed $39.99 yearly"))
        XCTAssertTrue(plan.accessibilityLabel.contains("Auto-renews yearly"), "the renewal term stays spoken")
    }

    /// Before the offering can be read the rows keep their shape and say so: no invented price.
    func testPlaceholdersNeverShowAPrice() {
        for placeholders in [PaywallPlanCopy.offlinePlaceholders, PaywallPlanCopy.signedOutPlaceholders] {
            XCTAssertEqual(placeholders.count, 2)
            XCTAssertEqual(placeholders.map(\.title), ["Yearly", "Monthly"])
            XCTAssertTrue(placeholders.allSatisfy { $0.price == "—" })
            XCTAssertTrue(placeholders.allSatisfy { $0.badge == nil })
        }
        XCTAssertEqual(PaywallPlanCopy.offlinePlaceholders.first?.detail, "Price unavailable offline")
        XCTAssertEqual(PaywallPlanCopy.signedOutPlaceholders.first?.detail, "Price shown after you sign in")
    }
}

@MainActor
private final class FakeConnectivity: ConnectivityReporting {
    private let subject: CurrentValueSubject<Bool, Never>
    var isOffline: Bool { subject.value }
    var changes: AnyPublisher<Bool, Never> { subject.eraseToAnyPublisher() }
    private(set) var startCount = 0

    init(isOffline: Bool = false) {
        subject = CurrentValueSubject(isOffline)
    }

    func start() { startCount += 1 }

    func set(isOffline offline: Bool) { subject.send(offline) }
}

/// The state copy the boards draw: what the CTA says, what the error card says, and what the offline
/// and signed-out states show instead of a price.
@MainActor
final class PaywallStateCopyTests: XCTestCase {
    private let connectivity = FakeConnectivity()

    private func makeModel(
        gateway: FakePurchaseGateway,
        storage: InMemoryTokenStorage = InMemoryTokenStorage(credentials: session),
        appleSignIn: @escaping AppleSignInAction.SignIn = { _, _, _ in },
        appleProvider: AppleAuthorizationProviding = PaywallStateAppleProvider()
    ) -> PaywallModel {
        PaywallModel(
            gateway: gateway,
            boundary: SessionBoundary(tokenStorage: storage),
            signInAction: SignInAction(start: {}),
            appleSignInAction: AppleSignInAction(provider: appleProvider, signIn: appleSignIn),
            connectivity: connectivity
        )
    }
    func testSignedOutKeepsThePlanRowsAndAsksForSignInFirst() async {
        let gateway = FakePurchaseGateway(nextLoad: readyOffering)
        let model = makeModel(gateway: gateway, storage: InMemoryTokenStorage())
        model.start()
        await waitUntil("sign in required") { model.phase == .signInRequired }

        XCTAssertEqual(model.ctaTitle, "Sign in to subscribe")
        XCTAssertTrue(model.isCTAEnabled, "the primary action opens the sign-in sheet")
        XCTAssertEqual(model.ctaHelper, "Sign in first so Premium follows you.")
        XCTAssertEqual(model.planPresentations, [], "no offering is read before sign-in")
        XCTAssertEqual(model.placeholderPlans, PaywallPlanCopy.signedOutPlaceholders)
        XCTAssertTrue(model.placeholderPlans.allSatisfy { $0.price == "—" }, "no price is invented")
    }

    func testLoadingPlansKeepsTheCTAOnScreenDisabled() async {
        let gateway = FakePurchaseGateway(nextLoad: readyOffering)
        let model = makeModel(gateway: gateway)
        let started = AsyncSignal()
        let gate = SuspensionGate()
        gateway.loadStarted = started
        gateway.loadGate = gate

        model.start()
        await started.wait()

        XCTAssertEqual(model.phase, .loadingPlans)
        XCTAssertEqual(model.ctaTitle, "Subscribe")
        XCTAssertFalse(model.isCTAEnabled, "there is nothing to buy yet")
        XCTAssertEqual(model.ctaHelper, "Subscribe turns on when plans load.")

        gate.release()
        await waitUntil("ready") { model.phase == .ready }
        XCTAssertTrue(model.isCTAEnabled)
        XCTAssertNil(model.ctaHelper)
    }

    func testOfflineDisablesTheCTAAndMarksThePriceUnavailable() async {
        let gateway = FakePurchaseGateway(nextLoad: PurchaseSnapshot(state: .noOffering, products: []))
        let model = makeModel(gateway: gateway)
        model.start()
        await waitUntil("unavailable") { model.phase != .loadingPlans }

        connectivity.set(isOffline: true)
        await waitUntil("offline") { model.isOffline }

        XCTAssertEqual(model.ctaTitle, "Plans unavailable", "the unbuyable label is unchanged")
        XCTAssertFalse(model.isCTAEnabled)
        XCTAssertEqual(model.ctaHelper, "Connect to the internet to subscribe.")
        XCTAssertEqual(model.placeholderPlans, PaywallPlanCopy.offlinePlaceholders)
    }

    /// Coming back online retries the offering that could not load, instead of leaving the user to
    /// find the retry themselves.
    func testReconnectingRetriesAnOfferingThatCouldNotLoad() async {
        let gateway = FakePurchaseGateway(nextLoad: PurchaseSnapshot(state: .noOffering, products: []))
        let model = makeModel(gateway: gateway)
        model.start()
        await waitUntil("unavailable") { model.phase != .loadingPlans }
        XCTAssertEqual(gateway.loadCount, 1)

        connectivity.set(isOffline: true)
        await waitUntil("offline") { model.isOffline }
        gateway.nextLoad = readyOffering
        connectivity.set(isOffline: false)

        await waitUntil("reloaded") { model.phase == .ready }
        XCTAssertEqual(gateway.loadCount, 2)
        XCTAssertTrue(model.isCTAEnabled)
    }

    func testPurchaseFailureCardUsesTheStoreFailureKind() async {
        let gateway = FakePurchaseGateway(
            nextLoad: readyOffering,
            nextPurchase: PurchaseSnapshot(state: .purchaseFailed, products: [monthly, annual], failure: .network)
        )
        let model = makeModel(gateway: gateway)
        model.start()
        await waitUntil("ready") { model.phase == .ready }

        await model.purchase()

        XCTAssertEqual(model.ctaTitle, "Try again")
        XCTAssertEqual(model.notice?.title, "The purchase didn't go through")
        XCTAssertEqual(model.notice?.message, "Check your connection and try again.")
        XCTAssertNil(model.notice?.action, "the retry is the primary action here")
    }

    /// Board 11-09: a failed restore keeps "Subscribe" as the primary action and retries inline.
    func testRestoreFailureKeepsSubscribeAndRetriesInline() async {
        let gateway = FakePurchaseGateway(
            nextLoad: readyOffering,
            nextRestore: PurchaseSnapshot(state: .purchaseFailed, products: [monthly, annual], failure: .storeProblem)
        )
        let model = makeModel(gateway: gateway)
        model.start()
        await waitUntil("ready") { model.phase == .ready }

        await model.restore()

        XCTAssertEqual(model.ctaTitle, "Subscribe")
        XCTAssertEqual(model.notice?.title, "Couldn't restore purchases")
        XCTAssertEqual(model.notice?.action, .retryRestore)
        XCTAssertEqual(model.notice?.actionTitle, "Try again")
        XCTAssertEqual(model.notice?.message, "The App Store didn't respond. Check your connection and try again.")
    }

    func testGoogleFailureNamesGoogleAndOffersTheRetryRow() async {
        let gateway = FakePurchaseGateway(nextLoad: readyOffering)
        let model = PaywallModel(
            gateway: gateway,
            boundary: SessionBoundary(tokenStorage: InMemoryTokenStorage()),
            signInAction: SignInAction(start: { throw OAuthCallbackError.invalidCallback }),
            connectivity: connectivity
        )
        model.start()
        await waitUntil("sign in required") { model.phase == .signInRequired }

        await model.signIn()

        XCTAssertEqual(model.authProvider, .google)
        XCTAssertEqual(model.notice?.title, "Couldn't sign in with Google")
        XCTAssertEqual(model.notice?.action, .retryGoogle)
        XCTAssertEqual(model.notice?.message, "Unable to start Google sign-in.")
    }

    func testAppleFailureNamesApple() async {
        let gateway = FakePurchaseGateway(nextLoad: readyOffering)
        let model = makeModel(
            gateway: gateway,
            storage: InMemoryTokenStorage(),
            appleSignIn: { _, _, _ in throw PaywallStateTestError.backend },
            appleProvider: PaywallStateAppleProvider()
        )
        model.start()
        await waitUntil("sign in required") { model.phase == .signInRequired }

        await model.signInWithApple()

        XCTAssertEqual(model.authProvider, .apple)
        XCTAssertEqual(model.notice?.title, "Couldn't sign in with Apple")
        XCTAssertEqual(model.notice?.message, PaywallStateTestError.backendText)
    }

    /// A cancelled purchase is not an error card; it keeps the existing, quieter status line.
    func testCancelledPurchaseKeepsTheStatusLineWithoutACard() async {
        let gateway = FakePurchaseGateway(
            nextLoad: readyOffering,
            nextPurchase: PurchaseSnapshot(state: .purchaseCancelled, products: [monthly, annual])
        )
        let model = makeModel(gateway: gateway)
        model.start()
        await waitUntil("ready") { model.phase == .ready }

        await model.purchase()

        XCTAssertNil(model.notice)
        XCTAssertEqual(model.statusMessage, "Purchase cancelled. No access was granted.")
        XCTAssertEqual(model.ctaTitle, "Subscribe")
        XCTAssertTrue(model.isCTAEnabled)
    }

    /// The identity line never prints an email: the account payload carries none, so the paywall
    /// states what is actually true.
    func testSignedInLineDoesNotInventAnEmail() async {
        let gateway = FakePurchaseGateway(nextLoad: readyOffering)
        let model = makeModel(gateway: gateway)
        model.start()
        await waitUntil("ready") { model.phase == .ready }

        XCTAssertEqual(PaywallModel.signedInLine, "Signed in. Premium follows your account.")
        XCTAssertFalse(PaywallModel.signedInLine.contains("@"))
        XCTAssertNil(model.ctaHelper)
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

private enum PaywallStateTestError: Error, LocalizedError, Sendable {
    case backend

    static let backendText = "Apple sign-in failed."

    var errorDescription: String? { Self.backendText }
}

@MainActor
private final class PaywallStateAppleProvider: AppleAuthorizationProviding {
    func authorize(_ request: AppleAuthorizationRequest) async throws -> AppleAuthorizationResult {
        AppleAuthorizationResult(identityToken: "identity-token", rawNonce: request.rawNonce, fullName: nil)
    }
}

/// Visual check for the redesign: the paywall and its sign-in sheet rendered at the board's states,
/// written to `/tmp/shots/PW/` so they can be compared to the page-11 boards. Not an image diff —
/// the PNGs are the artifact, and the geometry assertions catch a collapsed or clipped screen.
@MainActor
final class PaywallSnapshotTests: XCTestCase {
    private let outputDirectory = URL(fileURLWithPath: "/tmp/shots/PW")
    private let phone = CGSize(width: 390, height: 844)

    override func setUp() {
        super.setUp()
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }

    private func render<Content: View>(
        _ view: Content,
        style: UIUserInterfaceStyle,
        size: CGSize? = nil,
        contentSize: ContentSizeCategory = .large,
        filename: String
    ) {
        let size = size ?? phone
        let host = UIHostingController(
            rootView: view.environment(\.sizeCategory, contentSize)
        )
        host.overrideUserInterfaceStyle = style
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        XCTAssertEqual(image.size, size)
        guard let data = image.pngData() else {
            XCTFail("no PNG for \(filename)")
            return
        }
        let url = outputDirectory.appendingPathComponent(filename)
        try? data.write(to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    private func readyModel() async -> PaywallModel {
        let gateway = FakePurchaseGateway(nextLoad: readyOffering)
        let model = PaywallModel(
            gateway: gateway,
            boundary: SessionBoundary(tokenStorage: InMemoryTokenStorage(credentials: session)),
            signInAction: SignInAction(start: {}),
            connectivity: FakeConnectivity()
        )
        model.start()
        let deadline = Date().addingTimeInterval(3)
        while model.phase != .ready && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(model.phase, .ready)
        return model
    }

    func testCapturePaywallLightDarkAndAccessibility() async {
        let model = await readyModel()
        render(PaywallScreen(model: model), style: .light, filename: "paywall-light.png")
        render(PaywallScreen(model: model), style: .dark, filename: "paywall-dark.png")
        render(
            PaywallScreen(model: model),
            style: .light,
            contentSize: .accessibilityExtraExtraExtraLarge,
            filename: "paywall-ax3.png"
        )
    }

    /// Board 11-06: signed out, the plans keep their shape and the primary action is sign-in.
    func testCaptureSignedOutPaywall() async {
        let gateway = FakePurchaseGateway(nextLoad: readyOffering)
        let model = PaywallModel(
            gateway: gateway,
            boundary: SessionBoundary(tokenStorage: InMemoryTokenStorage()),
            signInAction: SignInAction(start: {}),
            connectivity: FakeConnectivity()
        )
        model.start()
        let deadline = Date().addingTimeInterval(3)
        while model.phase != .signInRequired && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(model.phase, .signInRequired)
        render(PaywallScreen(model: model), style: .light, filename: "paywall-signed-out.png")
    }

    /// Boards 11-12/11-17: the sign-in sheet and the email form with both field messages.
    func testCaptureSignInSheetAndEmailValidation() {
        let model = PaywallModel(
            gateway: FakePurchaseGateway(nextLoad: readyOffering),
            boundary: SessionBoundary(tokenStorage: InMemoryTokenStorage()),
            signInAction: SignInAction(start: {}),
            connectivity: FakeConnectivity()
        )
        render(
            PaywallSignInSheet(
                model: model,
                onApple: {},
                onGoogle: {},
                onEmail: {},
                onClose: {}
            ),
            style: .light,
            size: CGSize(width: 390, height: 420),
            filename: "signin-sheet-light.png"
        )

        let email = EmailSignInModel(connectivity: FakeConnectivity())
        email.email = "maya@"
        _ = email.validate()
        render(
            EmailSignInScreen(model: email, intentLine: "Your purchase is tied to your account."),
            style: .light,
            filename: "email-validation.png"
        )
        render(
            EmailSignInScreen(model: email, intentLine: "Your purchase is tied to your account."),
            style: .dark,
            contentSize: .accessibilityExtraExtraExtraLarge,
            filename: "email-validation-ax3-dark.png"
        )
    }
}
