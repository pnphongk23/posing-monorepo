import XCTest
import RevenueCat
@testable import iosApp

// MARK: - Deterministic test seams

/// A one-shot signal: the test waits for it instead of polling.
@MainActor
final class AsyncSignal {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var fired = false

    func fire() {
        fired = true
        let pending = waiters
        waiters = []
        pending.forEach { $0.resume() }
    }

    func wait() async {
        if fired { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

/// Holds a provider call in flight until the test releases it, so an identity change can land
/// exactly inside the await.
@MainActor
final class SuspensionGate {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var released = false

    func release() {
        released = true
        let pending = continuations
        continuations = []
        pending.forEach { $0.resume() }
    }

    func wait() async {
        if released { return }
        await withCheckedContinuation { continuations.append($0) }
    }
}

/// Records the analytics events the adapter emits, so a test can await the moment a snapshot was
/// applied or dropped.
@MainActor
final class AnalyticsSpy {
    private(set) var events: [(name: String, parameters: [String: String])] = []
    var onChange: AsyncSignal?

    func record(_ name: String, _ parameters: [String: String]) {
        events.append((name, parameters))
        onChange?.fire()
        onChange = nil
    }

    func names() -> [String] { events.map(\.name) }

    func lastParameters(for name: String) -> [String: String]? {
        events.last { $0.name == name }?.parameters
    }
}

// MARK: - Fake RevenueCat client

@MainActor
final class FakePurchasesProvider: PurchasesProviding {
    static let anonymousID = "$RCAnonymousID:fake"
    static let entitlementKey = "premium"

    var appUserID: String?
    var isAnonymous: Bool { appUserID?.hasPrefix("$RCAnonymousID:") ?? true }
    var onCustomerInfoUpdated: (() -> Void)?

    var packages: [ProviderPackage]
    var packagesError: Error?
    var purchaseError: Error?
    var restoreError: Error?
    var logInError: Error?
    /// Simulates the SDK landing on an identity other than the one that was requested.
    var logInReturnsIdentity: String?
    /// Mirrors the live provider, which re-validates the transaction identity after its own awaits.
    /// Turning it off proves the adapter's own post-await re-check is load-bearing.
    var validatesTransactionIdentity = true
    /// Accounts whose entitlement the fake reports as active. Everything else is not entitled.
    var entitledAccounts: Set<String>

    private(set) var configuredKeys: [String] = []
    private(set) var logInCalls: [String] = []
    private(set) var logOutCalls = 0
    private(set) var customerInfoCalls = 0
    private(set) var packagesCalls = 0
    private(set) var purchaseCalls: [String] = []
    private(set) var restoreCalls = 0
    /// The Account each store call was authorized for.
    private(set) var authorizedAccountIDs: [String] = []

    var customerInfoStarted: AsyncSignal?
    var customerInfoGate: SuspensionGate?
    var logInStarted: AsyncSignal?
    var logInGate: SuspensionGate?
    /// Per-Account gates, so one login can resolve while another is still in flight.
    var logInGates: [String: SuspensionGate] = [:]
    var logOutStarted: AsyncSignal?
    var logOutGate: SuspensionGate?
    /// Gate only the Nth logout (1-based), so a reconcile logout can settle before the one under
    /// test is held open.
    var logOutGateOnCall: Int?
    var packagesStarted: AsyncSignal?
    var packagesGate: SuspensionGate?
    var purchaseStarted: AsyncSignal?
    var purchaseGate: SuspensionGate?
    var restoreStarted: AsyncSignal?
    var restoreGate: SuspensionGate?

    init(packages: [ProviderPackage] = [], entitledAccounts: Set<String> = []) {
        self.packages = packages
        self.entitledAccounts = entitledAccounts
        self.appUserID = Self.anonymousID
    }

    func configure(apiKey: String) {
        configuredKeys.append(apiKey)
    }

    func logIn(_ accountID: String) async throws -> ProviderCustomer {
        logInCalls.append(accountID)
        logInStarted?.fire()
        await logInGate?.wait()
        await logInGates[accountID]?.wait()
        if let logInError { throw logInError }
        appUserID = logInReturnsIdentity ?? accountID
        return currentCustomer()
    }

    func logOut() async throws -> ProviderCustomer {
        logOutCalls += 1
        if logOutGateOnCall == nil || logOutCalls == logOutGateOnCall {
            logOutStarted?.fire()
            await logOutGate?.wait()
        }
        appUserID = Self.anonymousID
        return currentCustomer()
    }

    func customerInfo() async throws -> ProviderCustomer {
        customerInfoCalls += 1
        customerInfoStarted?.fire()
        // The result belongs to the identity the call started with, exactly like a late SDK
        // callback that must not be attributed to whoever is signed in when it lands.
        let result = currentCustomer()
        await customerInfoGate?.wait()
        return result
    }

    func packages() async throws -> [ProviderPackage] {
        packagesCalls += 1
        packagesStarted?.fire()
        await packagesGate?.wait()
        if let packagesError { throw packagesError }
        return packages
    }

    func purchase(packageID: String, authorizedAccountID: String) async throws -> ProviderCustomer {
        purchaseCalls.append(packageID)
        authorizedAccountIDs.append(authorizedAccountID)
        purchaseStarted?.fire()
        let result = currentCustomer()
        await purchaseGate?.wait()
        if validatesTransactionIdentity, isAnonymous || appUserID != authorizedAccountID {
            throw ProviderIdentityError.identityChanged
        }
        if let purchaseError { throw purchaseError }
        return result
    }

    func restorePurchases(authorizedAccountID: String) async throws -> ProviderCustomer {
        restoreCalls += 1
        authorizedAccountIDs.append(authorizedAccountID)
        restoreStarted?.fire()
        let result = currentCustomer()
        await restoreGate?.wait()
        if validatesTransactionIdentity, isAnonymous || appUserID != authorizedAccountID {
            throw ProviderIdentityError.identityChanged
        }
        if let restoreError { throw restoreError }
        return result
    }

    /// Mirrors the SDK: the entitlement follows the current app user id, and `logIn`/`logOut`
    /// change that id.
    private func currentCustomer() -> ProviderCustomer {
        guard let appUserID, entitledAccounts.contains(appUserID) else {
            return ProviderCustomer()
        }
        return ProviderCustomer(entitlements: [
            Self.entitlementKey: EntitlementFacts(
                isActive: true,
                billingIssueDetectedAt: nil,
                expirationDate: Date().addingTimeInterval(86_400)
            )
        ])
    }
}

// MARK: - Fixtures

private let annualPackage = ProviderPackage(identifier: "annual", packageType: .annual, localizedPrice: "$39.99")
private let monthlyPackage = ProviderPackage(identifier: "monthly", packageType: .monthly, localizedPrice: "$5.99")
private let weeklyPackage = ProviderPackage(identifier: "weekly", packageType: .other, localizedPrice: "$1.99")

@MainActor
final class RevenueCatAdapterTests: XCTestCase {
    private func makeAdapter(
        provider: FakePurchasesProvider,
        entitlementID: String? = FakePurchasesProvider.entitlementKey,
        spy: AnalyticsSpy? = nil
    ) -> RevenueCatAdapter {
        RevenueCatAdapter(provider: provider, entitlementID: entitlementID) { name, parameters in
            spy?.record(name, parameters)
        }
    }

    // MARK: Configuration

    func testPlaceholderEntitlementIDFailsClosed() async {
        for placeholder in ["REPLACE_WITH_ENTITLEMENT_ID", "$(REVENUECAT_ENTITLEMENT_ID)", "", "example_entitlement"] {
            let provider = FakePurchasesProvider(packages: [annualPackage, monthlyPackage])
            let adapter = makeAdapter(provider: provider, entitlementID: placeholder)

            XCTAssertFalse(adapter.isConfigured, "\(placeholder) must not configure the adapter")
            let offering = await adapter.loadOffering()
            XCTAssertEqual(offering.state, .unconfigured)
            let purchase = await adapter.purchase(packageID: "annual")
            XCTAssertEqual(purchase.state, .unconfigured)
            XCTAssertTrue(provider.purchaseCalls.isEmpty, "No store call while unconfigured")
            XCTAssertTrue(provider.packagesCalls == 0)
        }
    }

    func testMissingEntitlementIDFailsClosed() async {
        let provider = FakePurchasesProvider(packages: [annualPackage, monthlyPackage])
        let adapter = makeAdapter(provider: provider, entitlementID: nil)

        XCTAssertFalse(adapter.isConfigured)
        let snapshot = await adapter.loadOffering()
        XCTAssertEqual(snapshot.state, .unconfigured)
        XCTAssertTrue(snapshot.products.isEmpty)
    }

    // MARK: Offering by package type

    func testOfferingSelectsAnnualAndMonthlyByPackageType() async {
        let provider = FakePurchasesProvider(packages: [monthlyPackage, weeklyPackage, annualPackage])
        let adapter = makeAdapter(provider: provider)

        let snapshot = await adapter.loadOffering()

        XCTAssertEqual(snapshot.products.map(\.identifier), ["annual", "monthly"])
        XCTAssertEqual(snapshot.products.map(\.packageType), [.annual, .monthly])
        XCTAssertEqual(snapshot.products.map(\.period), ["year", "month"])
        XCTAssertEqual(snapshot.products.map(\.localizedPrice), ["$39.99", "$5.99"])
        XCTAssertNotEqual(snapshot.state, .noOffering)
    }

    func testOfferingWithoutAnnualOrMonthlyFailsClosed() async {
        let provider = FakePurchasesProvider(packages: [weeklyPackage])
        let adapter = makeAdapter(provider: provider)

        let snapshot = await adapter.loadOffering()

        XCTAssertEqual(snapshot.state, .noOffering)
        XCTAssertTrue(snapshot.products.isEmpty, "A build that cannot buy must not show a plan")
    }

    func testEmptyOfferingFailsClosed() async {
        let provider = FakePurchasesProvider(packages: [])
        let adapter = makeAdapter(provider: provider)

        let snapshot = await adapter.loadOffering()

        XCTAssertEqual(snapshot.state, .noOffering)
    }

    func testOfferingFetchFailureIsNoOffering() async {
        let provider = FakePurchasesProvider(packages: [annualPackage])
        provider.packagesError = ErrorCode.networkError
        let adapter = makeAdapter(provider: provider)

        let snapshot = await adapter.loadOffering()

        XCTAssertEqual(snapshot.state, .noOffering)
    }

    // MARK: Packages

    func testPurchaseRejectsPackageNotInLoadedOffering() async {
        let provider = FakePurchasesProvider(packages: [annualPackage, monthlyPackage], entitledAccounts: ["account-a"])
        let adapter = makeAdapter(provider: provider)
        await adapter.linkAccount("account-a")
        _ = await adapter.loadOffering()

        let snapshot = await adapter.purchase(packageID: "weekly")

        XCTAssertEqual(snapshot.state, .purchaseFailed)
        XCTAssertTrue(provider.purchaseCalls.isEmpty, "An unknown package never reaches the store")
    }

    func testPurchaseBeforeOfferingLoadedFailsClosed() async {
        let provider = FakePurchasesProvider(packages: [annualPackage], entitledAccounts: ["account-a"])
        let adapter = makeAdapter(provider: provider)
        await adapter.linkAccount("account-a")

        let snapshot = await adapter.purchase(packageID: "annual")

        XCTAssertEqual(snapshot.state, .purchaseFailed)
        XCTAssertTrue(provider.purchaseCalls.isEmpty)
    }

    func testPurchaseOfLoadedPackageConfirmsEntitlement() async {
        let provider = FakePurchasesProvider(packages: [annualPackage, monthlyPackage], entitledAccounts: ["account-a"])
        let adapter = makeAdapter(provider: provider)
        await adapter.linkAccount("account-a")
        _ = await adapter.loadOffering()

        let snapshot = await adapter.purchase(packageID: "annual")

        XCTAssertEqual(provider.purchaseCalls, ["annual"])
        XCTAssertEqual(snapshot.state, .entitled)
        XCTAssertEqual(adapter.snapshot.state, .entitled)
    }

    // MARK: Signed-out guard (M2: no guest purchase)

    func testSignedOutPurchaseAndRestoreAreBlockedBeforeTheStore() async {
        let provider = FakePurchasesProvider(packages: [annualPackage, monthlyPackage], entitledAccounts: ["account-a"])
        let adapter = makeAdapter(provider: provider)
        _ = await adapter.loadOffering()

        let purchase = await adapter.purchase(packageID: "annual")
        let restore = await adapter.restore()

        XCTAssertEqual(purchase.state, .signInRequired)
        XCTAssertEqual(restore.state, .signInRequired)
        XCTAssertTrue(provider.purchaseCalls.isEmpty, "No anonymous purchase")
        XCTAssertEqual(provider.restoreCalls, 0, "No anonymous restore")
    }

    func testLinkedAccountAllowsTheStoreCall() async {
        let provider = FakePurchasesProvider(packages: [annualPackage], entitledAccounts: ["account-a"])
        let adapter = makeAdapter(provider: provider)
        await adapter.linkAccount("account-a")
        _ = await adapter.loadOffering()

        _ = await adapter.purchase(packageID: "annual")
        _ = await adapter.restore()

        XCTAssertEqual(provider.purchaseCalls, ["annual"])
        XCTAssertEqual(provider.restoreCalls, 1)
    }

    func testClearAccountDropsAccessEvenForAnEntitledAccount() async {
        let provider = FakePurchasesProvider(packages: [annualPackage], entitledAccounts: ["account-a"])
        let adapter = makeAdapter(provider: provider)
        await adapter.linkAccount("account-a")
        _ = await adapter.loadOffering()
        XCTAssertEqual(adapter.snapshot.state, .entitled)

        await adapter.clearAccount()

        XCTAssertNil(adapter.linkedAccountID)
        XCTAssertEqual(adapter.snapshot.state, .notEntitled)
        XCTAssertEqual(provider.logOutCalls, 1)
    }

    // MARK: Identity re-checks after every await

    func testSignOutDuringPurchaseDropsTheEntitledSnapshot() async {
        let provider = FakePurchasesProvider(packages: [annualPackage], entitledAccounts: ["account-a"])
        let spy = AnalyticsSpy()
        let adapter = makeAdapter(provider: provider, spy: spy)
        await adapter.linkAccount("account-a")
        _ = await adapter.loadOffering()

        let started = AsyncSignal()
        let gate = SuspensionGate()
        provider.purchaseStarted = started
        provider.purchaseGate = gate

        let purchase = Task { await adapter.purchase(packageID: "annual") }
        await started.wait()
        await adapter.clearAccount()
        gate.release()
        _ = await purchase.value

        XCTAssertEqual(adapter.snapshot.state, .notEntitled, "Account A's purchase must not grant access after sign-out")
        XCTAssertTrue(spy.names().contains("purchase_snapshot_dropped"))
    }

    func testSignOutDuringRestoreDropsTheEntitledSnapshot() async {
        let provider = FakePurchasesProvider(packages: [annualPackage], entitledAccounts: ["account-a"])
        let spy = AnalyticsSpy()
        let adapter = makeAdapter(provider: provider, spy: spy)
        await adapter.linkAccount("account-a")
        _ = await adapter.loadOffering()

        let started = AsyncSignal()
        let gate = SuspensionGate()
        provider.restoreStarted = started
        provider.restoreGate = gate

        let restore = Task { await adapter.restore() }
        await started.wait()
        await adapter.clearAccount()
        gate.release()
        _ = await restore.value

        XCTAssertEqual(adapter.snapshot.state, .notEntitled)
        XCTAssertTrue(spy.names().contains("purchase_snapshot_dropped"))
    }

    func testSignOutDuringRefreshDropsTheLateEntitledInfo() async {
        let provider = FakePurchasesProvider(entitledAccounts: ["account-a"])
        let spy = AnalyticsSpy()
        let adapter = makeAdapter(provider: provider, spy: spy)
        await adapter.linkAccount("account-a")

        let started = AsyncSignal()
        let gate = SuspensionGate()
        provider.customerInfoStarted = started
        provider.customerInfoGate = gate

        let refresh = Task { await adapter.refreshSnapshot() }
        await started.wait()
        await adapter.clearAccount()
        gate.release()
        _ = await refresh.value

        XCTAssertEqual(adapter.snapshot.state, .notEntitled)
    }

    func testLinkAccountDuringRefreshAsAnotherAccountDropsTheResult() async {
        let provider = FakePurchasesProvider(entitledAccounts: ["account-a"])
        let adapter = makeAdapter(provider: provider)
        await adapter.linkAccount("account-a")
        XCTAssertEqual(adapter.snapshot.state, .entitled)

        let started = AsyncSignal()
        let gate = SuspensionGate()
        provider.customerInfoStarted = started
        provider.customerInfoGate = gate
        let refresh = Task { await adapter.refreshSnapshot() }
        await started.wait()

        await adapter.linkAccount("account-b")
        gate.release()
        _ = await refresh.value

        XCTAssertEqual(adapter.linkedAccountID, "account-b")
        XCTAssertEqual(adapter.snapshot.state, .notEntitled, "Account A's in-flight result must not land on B")
    }

    func testSignOutDuringLogInDropsTheLink() async {
        let provider = FakePurchasesProvider(entitledAccounts: ["account-a"])
        let adapter = makeAdapter(provider: provider)

        let started = AsyncSignal()
        let gate = SuspensionGate()
        provider.logInStarted = started
        provider.logInGate = gate

        let link = Task { await adapter.linkAccount("account-a") }
        await started.wait()
        // Sign-out is queued behind the in-flight login, but it drops access before it waits.
        let clear = Task { await adapter.clearAccount() }
        await waitUntil("sign-out invalidated access") { adapter.snapshot.state == .notEntitled }
        gate.release()
        _ = await link.value
        await clear.value

        XCTAssertNil(adapter.linkedAccountID, "A logIn that lands after sign-out must not link")
        XCTAssertEqual(adapter.snapshot.state, .notEntitled)
    }

    func testDelegatePushWithUnchangedIdentityIsApplied() async {
        let provider = FakePurchasesProvider(packages: [annualPackage], entitledAccounts: ["account-a"])
        let spy = AnalyticsSpy()
        let adapter = makeAdapter(provider: provider, spy: spy)
        await adapter.linkAccount("account-a")
        _ = await adapter.loadOffering()
        XCTAssertEqual(adapter.snapshot.state, .entitled)

        let applied = AsyncSignal()
        spy.onChange = applied
        provider.onCustomerInfoUpdated?()
        await applied.wait()

        XCTAssertEqual(adapter.snapshot.state, .entitled)
        XCTAssertFalse(spy.names().contains("purchase_snapshot_dropped"))
    }

    /// The whole identity sequence against provider state that tracks `appUserID` the way the SDK
    /// does: the last written snapshot may only reflect the identity that is current at the end.
    func testIdentitySequenceEndsOnTheLastLinkedAccount() async {
        let provider = FakePurchasesProvider(packages: [annualPackage], entitledAccounts: ["account-a"])
        let spy = AnalyticsSpy()
        let adapter = makeAdapter(provider: provider, spy: spy)

        XCTAssertEqual(provider.appUserID, FakePurchasesProvider.anonymousID)
        _ = await adapter.refreshSnapshot()
        XCTAssertEqual(adapter.snapshot.state, .notEntitled, "The anonymous device is not entitled")

        await adapter.linkAccount("account-a")
        XCTAssertEqual(adapter.snapshot.state, .entitled)

        // A delegate push that arrives late, from before the login: only a trigger, never the payload.
        let latePush = AsyncSignal()
        spy.onChange = latePush
        provider.onCustomerInfoUpdated?()
        await latePush.wait()
        XCTAssertEqual(adapter.snapshot.state, .entitled)

        await adapter.clearAccount()
        XCTAssertEqual(adapter.snapshot.state, .notEntitled)

        await adapter.linkAccount("account-b")
        XCTAssertEqual(adapter.linkedAccountID, "account-b")
        XCTAssertEqual(adapter.snapshot.state, .notEntitled, "Account B never inherits Account A's entitlement")
    }

    // MARK: Entitlement mapping

    func testActiveEntitlementWithBillingIssueStaysEntitled() {
        let facts = EntitlementFacts(
            isActive: true,
            billingIssueDetectedAt: Date().addingTimeInterval(-3_600),
            expirationDate: Date().addingTimeInterval(86_400)
        )
        XCTAssertEqual(RevenueCatAdapter.entitlementState(for: facts), .entitled)
    }

    func testInactiveEntitlementWithBillingIssueIsBillingRetry() {
        let facts = EntitlementFacts(
            isActive: false,
            billingIssueDetectedAt: Date().addingTimeInterval(-3_600),
            expirationDate: Date().addingTimeInterval(-60)
        )
        XCTAssertEqual(RevenueCatAdapter.entitlementState(for: facts), .billingRetry)
    }

    func testInactiveEntitlementWithPastExpiryIsExpired() {
        let now = Date()
        let facts = EntitlementFacts(
            isActive: false,
            billingIssueDetectedAt: nil,
            expirationDate: now.addingTimeInterval(-60)
        )
        XCTAssertEqual(RevenueCatAdapter.entitlementState(for: facts, now: now), .expired)
    }

    func testInactiveEntitlementWithoutExpiryIsRevoked() {
        let facts = EntitlementFacts(isActive: false, billingIssueDetectedAt: nil, expirationDate: nil)
        XCTAssertEqual(RevenueCatAdapter.entitlementState(for: facts), .revoked)
    }

    func testMissingEntitlementIsNotEntitled() {
        XCTAssertEqual(RevenueCatAdapter.entitlementState(for: nil), .notEntitled)
    }

    func testEntitlementForAnotherIDDoesNotGrantAccess() async {
        let provider = FakePurchasesProvider(packages: [annualPackage], entitledAccounts: ["account-a"])
        let adapter = makeAdapter(provider: provider, entitlementID: "some-other-entitlement")
        await adapter.linkAccount("account-a")

        XCTAssertEqual(adapter.snapshot.state, .notEntitled, "Only the configured entitlement id counts")
    }

    // MARK: Error mapping

    func testErrorMappingKeepsTheFailureKind() {
        XCTAssertEqual(PurchaseFailure(ErrorCode.receiptAlreadyInUseError), .receiptOwnedByOtherAccount)
        XCTAssertEqual(PurchaseFailure(ErrorCode.receiptInUseByOtherSubscriberError), .receiptOwnedByOtherAccount)
        XCTAssertEqual(PurchaseFailure(ErrorCode.networkError), .network)
        XCTAssertEqual(PurchaseFailure(ErrorCode.purchaseCancelledError), .cancelled)
        XCTAssertEqual(PurchaseFailure(ErrorCode.storeProblemError), .storeProblem)
        XCTAssertEqual(PurchaseFailure(ErrorCode.unknownError), .other)
    }

    func testCancelledPurchaseKeepsTheCancelledKind() async {
        let provider = FakePurchasesProvider(packages: [annualPackage], entitledAccounts: ["account-a"])
        provider.purchaseError = ErrorCode.purchaseCancelledError
        let adapter = makeAdapter(provider: provider)
        await adapter.linkAccount("account-a")
        _ = await adapter.loadOffering()

        let snapshot = await adapter.purchase(packageID: "annual")

        XCTAssertEqual(snapshot.state, .purchaseCancelled)
        XCTAssertEqual(snapshot.failure, .cancelled)
    }

    func testRestoreFailureKeepsTheFailureKind() async {
        let provider = FakePurchasesProvider(packages: [annualPackage], entitledAccounts: ["account-a"])
        provider.restoreError = ErrorCode.receiptAlreadyInUseError
        let adapter = makeAdapter(provider: provider)
        await adapter.linkAccount("account-a")
        _ = await adapter.loadOffering()

        let snapshot = await adapter.restore()

        XCTAssertEqual(snapshot.state, .purchaseFailed)
        XCTAssertEqual(snapshot.failure, .receiptOwnedByOtherAccount)
    }

    func testAnalyticsRecordsTheFailureKindNotRawSDKErrors() async {
        let provider = FakePurchasesProvider(packages: [annualPackage], entitledAccounts: ["account-a"])
        provider.restoreError = ErrorCode.networkError
        let spy = AnalyticsSpy()
        let adapter = makeAdapter(provider: provider, spy: spy)
        await adapter.linkAccount("account-a")
        _ = await adapter.loadOffering()

        _ = await adapter.restore()

        XCTAssertEqual(spy.lastParameters(for: "purchase_state")?["failure"], "network")
    }

    // MARK: Transaction identity boundary

    /// A linked Account whose provider identity drifted (a stale in-memory link, a superseded
    /// login) must never authorize a transaction.
    func testTransactionRequiresProviderIdentityToMatchLinkedAccount() async {
        let provider = FakePurchasesProvider(packages: [annualPackage], entitledAccounts: ["account-a"])
        let adapter = makeAdapter(provider: provider)
        await adapter.linkAccount("account-a")
        _ = await adapter.loadOffering()
        let purchasesBefore = provider.purchaseCalls.count
        let restoresBefore = provider.restoreCalls

        // The SDK identity changed under the adapter (e.g. a late SDK-side login).
        provider.appUserID = "account-b"

        let purchase = await adapter.purchase(packageID: "annual")
        let restore = await adapter.restore()

        XCTAssertEqual(purchase.state, .signInRequired)
        XCTAssertEqual(restore.state, .signInRequired)
        XCTAssertEqual(provider.purchaseCalls.count, purchasesBefore)
        XCTAssertEqual(provider.restoreCalls, restoresBefore)
    }

    /// The provider re-validates after its own nested awaits; when it does, the abort is dropped,
    /// not reported as a failed purchase, and the account keeps its own identity.
    func testPurchaseAbortedByProviderIdentityChangeIsDropped() async {
        let provider = FakePurchasesProvider(packages: [annualPackage], entitledAccounts: ["account-a"])
        let spy = AnalyticsSpy()
        let adapter = makeAdapter(provider: provider, spy: spy)
        await adapter.linkAccount("account-a")
        _ = await adapter.loadOffering()

        let started = AsyncSignal()
        let gate = SuspensionGate()
        provider.purchaseStarted = started
        provider.purchaseGate = gate

        let purchase = Task { await adapter.purchase(packageID: "annual") }
        await started.wait()
        await adapter.clearAccount()
        gate.release()
        _ = await purchase.value

        XCTAssertEqual(adapter.snapshot.state, .notEntitled)
        XCTAssertEqual(provider.purchaseCalls, ["annual"], "The store call happened before the change")
        XCTAssertTrue(spy.names().contains("purchase_snapshot_dropped"))
    }

    /// Even without a provider-side check, the adapter's own post-await re-check is the guard that
    /// refuses a transaction result that crossed a sign-out.
    func testPostAwaitRecheckDropsPurchaseResultAfterSignOut() async {
        let provider = FakePurchasesProvider(packages: [annualPackage], entitledAccounts: ["account-a"])
        let spy = AnalyticsSpy()
        let adapter = makeAdapter(provider: provider, spy: spy)
        await adapter.linkAccount("account-a")
        _ = await adapter.loadOffering()

        provider.validatesTransactionIdentity = false
        let started = AsyncSignal()
        let gate = SuspensionGate()
        provider.purchaseStarted = started
        provider.purchaseGate = gate

        let purchase = Task { await adapter.purchase(packageID: "annual") }
        await started.wait()
        await adapter.clearAccount()
        gate.release()
        _ = await purchase.value

        XCTAssertEqual(adapter.snapshot.state, .notEntitled)
        XCTAssertEqual(
            spy.lastParameters(for: "purchase_snapshot_dropped")?["outcome"],
            "identity_changed",
            "The post-await re-check, not a later guard, must be the one that dropped it"
        )
    }

    // MARK: No entitlement without an owned identity

    func testRestoreAlsoRequiresProviderIdentityToMatchLinkedAccount() async {
        let provider = FakePurchasesProvider(packages: [annualPackage], entitledAccounts: ["account-a"])
        let adapter = makeAdapter(provider: provider)
        await adapter.linkAccount("account-a")
        provider.appUserID = FakePurchasesProvider.anonymousID

        let snapshot = await adapter.restore()

        XCTAssertEqual(snapshot.state, .signInRequired)
        XCTAssertEqual(provider.restoreCalls, 0)
    }

    /// Repro for a persisted provider identity at startup: the SDK can still be signed in to an
    /// entitled Account from an earlier launch while no Account is linked in this process.
    func testRefreshWhileUnlinkedDoesNotGrantPersistedEntitlement() async {
        let provider = FakePurchasesProvider(packages: [annualPackage], entitledAccounts: ["account-a"])
        provider.appUserID = "account-a"
        let spy = AnalyticsSpy()
        let adapter = makeAdapter(provider: provider, spy: spy)

        let snapshot = await adapter.refreshSnapshot()

        XCTAssertEqual(snapshot.state, .notEntitled, "No Account owns this identity in this process")
        XCTAssertEqual(adapter.snapshot.state, .notEntitled)
        XCTAssertTrue(provider.isAnonymous, "The unowned SDK identity is reconciled back to anonymous")
        XCTAssertEqual(provider.logOutCalls, 1)
    }

    func testDelegateRefreshWhileUnlinkedDoesNotGrantPersistedEntitlement() async {
        let provider = FakePurchasesProvider(entitledAccounts: ["account-a"])
        provider.appUserID = "account-a"
        let spy = AnalyticsSpy()
        let adapter = makeAdapter(provider: provider, spy: spy)

        let settled = AsyncSignal()
        spy.onChange = settled
        provider.onCustomerInfoUpdated?()
        await settled.wait()

        XCTAssertEqual(adapter.snapshot.state, .notEntitled)
        XCTAssertNotEqual(adapter.snapshot.state, .entitled)
    }

    // MARK: Identity transitions

    func testLateLoginAfterSignOutIsRejectedAndProviderIsReconciled() async {
        let provider = FakePurchasesProvider(entitledAccounts: ["account-a"])
        let spy = AnalyticsSpy()
        let adapter = makeAdapter(provider: provider, spy: spy)

        let started = AsyncSignal()
        let gate = SuspensionGate()
        provider.logInStarted = started
        provider.logInGate = gate

        let link = Task { await adapter.linkAccount("account-a") }
        await started.wait()
        let clear = Task { await adapter.clearAccount() }
        await waitUntil("sign-out invalidated access") { adapter.snapshot.state == .notEntitled }
        gate.release()
        _ = await link.value
        await clear.value

        XCTAssertNil(adapter.linkedAccountID)
        XCTAssertEqual(adapter.snapshot.state, .notEntitled)
        XCTAssertTrue(provider.isAnonymous, "A superseded login must not leave the SDK signed in")
        XCTAssertEqual(provider.appUserID, FakePurchasesProvider.anonymousID)
        XCTAssertFalse(
            spy.events.contains { $0.parameters["outcome"] == "entitled" },
            "The late login's entitlement must never be adopted, even transiently"
        )
        XCTAssertTrue(spy.names().contains("purchase_snapshot_dropped"))
    }

    /// Switching accounts ends access at once: while B's login is in flight nothing is linked and a
    /// transaction cannot start.
    func testAccountSwitchInvalidatesAccessImmediatelyAndBlocksTransactions() async {
        let provider = FakePurchasesProvider(packages: [annualPackage], entitledAccounts: ["account-a"])
        let adapter = makeAdapter(provider: provider)
        await adapter.linkAccount("account-a")
        _ = await adapter.loadOffering()
        XCTAssertEqual(adapter.snapshot.state, .entitled)

        let started = AsyncSignal()
        let gate = SuspensionGate()
        provider.logInStarted = started
        provider.logInGate = gate
        let purchasesBefore = provider.purchaseCalls.count

        let switchTask = Task { await adapter.linkAccount("account-b") }
        await started.wait()

        XCTAssertNil(adapter.linkedAccountID, "No Account is linked during the transition")
        XCTAssertNotEqual(adapter.snapshot.state, .entitled)
        let blocked = await adapter.purchase(packageID: "annual")
        XCTAssertEqual(blocked.state, .signInRequired)
        XCTAssertEqual(provider.purchaseCalls.count, purchasesBefore)

        gate.release()
        await switchTask.value

        XCTAssertEqual(adapter.linkedAccountID, "account-b")
        XCTAssertEqual(adapter.snapshot.state, .notEntitled)
    }

    /// Two overlapping logins are serialized: while the first login is still in flight the second
    /// switch must not reach the provider, so the earlier login cannot land after it and win.
    func testConcurrentLoginsLeaveProviderOnTheCurrentAccount() async {
        let provider = FakePurchasesProvider(entitledAccounts: ["account-a"])
        let adapter = makeAdapter(provider: provider)

        let started = AsyncSignal()
        let firstGate = SuspensionGate()
        provider.logInStarted = started
        provider.logInGates = ["account-a": firstGate]

        let firstLink = Task { await adapter.linkAccount("account-a") }
        await started.wait()
        let secondLink = Task { await adapter.linkAccount("account-b") }
        await assertStaysFalse("the second login must wait for the first") {
            provider.logInCalls.count > 1
        }
        firstGate.release()
        _ = await firstLink.value
        await secondLink.value

        XCTAssertEqual(adapter.linkedAccountID, "account-b")
        XCTAssertEqual(provider.appUserID, "account-b")
        XCTAssertEqual(adapter.snapshot.state, .notEntitled)
    }

    /// A sign-out that is still waiting on the provider's `logOut` must not keep access in place.
    func testSuspendedLogOutDoesNotLeaveAccess() async {
        let provider = FakePurchasesProvider(packages: [annualPackage], entitledAccounts: ["account-a"])
        let adapter = makeAdapter(provider: provider)
        await adapter.linkAccount("account-a")
        _ = await adapter.loadOffering()
        XCTAssertEqual(adapter.snapshot.state, .entitled)

        let started = AsyncSignal()
        let gate = SuspensionGate()
        provider.logOutStarted = started
        provider.logOutGate = gate

        let clear = Task { await adapter.clearAccount() }
        await started.wait()

        XCTAssertEqual(adapter.snapshot.state, .notEntitled, "Access ends before the provider call")
        XCTAssertNil(adapter.linkedAccountID)
        let blocked = await adapter.purchase(packageID: "annual")
        XCTAssertEqual(blocked.state, .signInRequired)

        gate.release()
        await clear.value
        XCTAssertEqual(adapter.snapshot.state, .notEntitled)
    }

    /// A sign-out during the offering fetch drops that result instead of painting plans for a
    /// session that no longer exists.
    func testSignOutDuringOfferingFetchDropsTheResult() async {
        let provider = FakePurchasesProvider(packages: [annualPackage, monthlyPackage], entitledAccounts: ["account-a"])
        let spy = AnalyticsSpy()
        let adapter = makeAdapter(provider: provider, spy: spy)
        await adapter.linkAccount("account-a")

        let started = AsyncSignal()
        let gate = SuspensionGate()
        provider.packagesStarted = started
        provider.packagesGate = gate

        let load = Task { await adapter.loadOffering() }
        await started.wait()
        await adapter.clearAccount()
        gate.release()
        _ = await load.value

        XCTAssertEqual(adapter.snapshot.state, .notEntitled)
        XCTAssertEqual(
            spy.lastParameters(for: "purchase_snapshot_dropped")?["outcome"],
            "identity_changed"
        )
    }

    func testLinkAccountIsIdempotent() async {
        let provider = FakePurchasesProvider(entitledAccounts: ["account-a"])
        let adapter = makeAdapter(provider: provider)

        await adapter.linkAccount("account-a")
        await adapter.linkAccount("account-a")

        XCTAssertEqual(provider.logInCalls, ["account-a"])
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

    /// Proves a *negative*: something that must not happen while another call is in flight.
    @MainActor
    private func assertStaysFalse(
        _ description: String,
        seconds: TimeInterval = 0.4,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() {
                XCTFail("Timed out waiting: \(description)", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    // MARK: Queued identity requests

    /// Repro: a login queued behind a suspended login must not adopt the sign-out's epoch and link
    /// an Account the user has left. Order: suspend login A, enqueue login B, enqueue sign-out,
    /// release A, then hold the sign-out's logout open.
    func testQueuedLoginCannotLinkAfterSignOut() async {
        let provider = FakePurchasesProvider(
            packages: [annualPackage],
            entitledAccounts: ["account-a", "account-b"]
        )
        let spy = AnalyticsSpy()
        let adapter = makeAdapter(provider: provider, spy: spy)

        let loginAStarted = AsyncSignal()
        let loginAGate = SuspensionGate()
        provider.logInStarted = loginAStarted
        provider.logInGates = ["account-a": loginAGate]

        let linkA = Task { await adapter.linkAccount("account-a") }
        await loginAStarted.wait()

        let linkB = Task { await adapter.linkAccount("account-b") }
        let clear = Task { await adapter.clearAccount() }
        // Both requests must be issued before A's login lands, so the sign-out really is the last
        // identity request and B's login is the one that must be discarded.
        await waitUntil("all three identity requests issued") {
            spy.events.filter { $0.name == "purchase_identity_change" }.count >= 3
        }

        // The superseded login A reconciles with one logout; the sign-out's logout is the second
        // and is held open so the intermediate state is observable.
        let signOutLogOutStarted = AsyncSignal()
        let signOutLogOutGate = SuspensionGate()
        provider.logOutStarted = signOutLogOutStarted
        provider.logOutGate = signOutLogOutGate
        provider.logOutGateOnCall = 2

        loginAGate.release()
        await signOutLogOutStarted.wait()

        XCTAssertNil(adapter.linkedAccountID, "No Account may be linked while the sign-out is in flight")
        XCTAssertEqual(adapter.snapshot.state, .notEntitled)
        XCTAssertEqual(provider.logInCalls, ["account-a"], "The superseded login never reaches the provider")
        let purchase = await adapter.purchase(packageID: "annual")
        XCTAssertEqual(purchase.state, .signInRequired)
        XCTAssertTrue(provider.purchaseCalls.isEmpty)
        let restore = await adapter.restore()
        XCTAssertEqual(restore.state, .signInRequired)
        XCTAssertEqual(provider.restoreCalls, 0)

        signOutLogOutGate.release()
        _ = await linkA.value
        await linkB.value
        await clear.value

        XCTAssertNil(adapter.linkedAccountID)
        XCTAssertEqual(adapter.snapshot.state, .notEntitled)
        XCTAssertTrue(provider.isAnonymous)
    }

    // MARK: No literal ids

    func testNoProductOrEntitlementLiteralInAppSources() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Services
            .deletingLastPathComponent() // iosAppTests
            .deletingLastPathComponent() // iosApp (project dir)
            .appendingPathComponent("iosApp")
        let pattern = try NSRegularExpression(
            pattern: "premium_yearly|premium_monthly|premium_annual|snap pose premium",
            options: [.caseInsensitive]
        )

        var offenders: [String] = []
        let enumerator = FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift", let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if pattern.firstMatch(in: text, options: [], range: range) != nil {
                offenders.append(url.lastPathComponent)
            }
        }

        XCTAssertEqual(offenders, [], "Product and entitlement ids live in configuration, not in sources")
    }
}

// MARK: - Store seam (identity checks around the live provider's SDK calls)

@MainActor
final class FakeRevenueCatSDK: RevenueCatSDK {
    static let anonymousID = "$RCAnonymousID:sdk"

    var appUserID = FakeRevenueCatSDK.anonymousID
    var isConfigured = true
    var isAnonymous: Bool { appUserID.hasPrefix("$RCAnonymousID:") }
    var onCustomerInfoUpdated: (() -> Void)?

    var packages: [ProviderPackage] = []
    var customer = ProviderCustomer()
    var purchaseError: Error?
    var restoreError: Error?

    private(set) var purchaseCalls: [String] = []
    private(set) var restoreCalls = 0
    private(set) var offeringsCalls = 0

    var offeringsStarted: AsyncSignal?
    var offeringsGate: SuspensionGate?

    func configure(apiKey: String) {}

    func logIn(_ accountID: String) async throws -> ProviderCustomer {
        appUserID = accountID
        return customer
    }

    func logOut() async throws -> ProviderCustomer {
        appUserID = Self.anonymousID
        return customer
    }

    func customerInfo() async throws -> ProviderCustomer { customer }

    func offering() async throws -> ProviderOffering {
        offeringsCalls += 1
        offeringsStarted?.fire()
        await offeringsGate?.wait()
        return ProviderOffering(packages: packages)
    }

    func purchase(packageIdentifier: String) async throws -> ProviderPurchaseOutcome {
        purchaseCalls.append(packageIdentifier)
        if let purchaseError { throw purchaseError }
        return ProviderPurchaseOutcome(customer: customer, userCancelled: false)
    }

    func restorePurchases() async throws -> ProviderCustomer {
        restoreCalls += 1
        if let restoreError { throw restoreError }
        return customer
    }
}

@MainActor
final class LivePurchasesProviderTests: XCTestCase {
    /// The nested `offerings()` await inside a purchase can span a sign-out: the provider must
    /// re-prove the identity immediately before the store call.
    func testPurchaseIsAbortedWhenIdentityChangesDuringOfferingFetch() async {
        let sdk = FakeRevenueCatSDK()
        sdk.appUserID = "account-a"
        sdk.packages = [annualPackage]
        let provider = LivePurchasesProvider(sdk: sdk)

        let started = AsyncSignal()
        let gate = SuspensionGate()
        sdk.offeringsStarted = started
        sdk.offeringsGate = gate

        let purchase = Task { try await provider.purchase(packageID: "annual", authorizedAccountID: "account-a") }
        await started.wait()
        sdk.appUserID = "account-b"
        gate.release()

        do {
            _ = try await purchase.value
            XCTFail("A purchase must not reach the store after an identity change")
        } catch {
            XCTAssertEqual(error as? ProviderIdentityError, .identityChanged)
        }
        XCTAssertTrue(sdk.purchaseCalls.isEmpty)
    }

    func testPurchaseIsAbortedWhenTheIdentityBecomesAnonymousDuringOfferingFetch() async {
        let sdk = FakeRevenueCatSDK()
        sdk.appUserID = "account-a"
        sdk.packages = [annualPackage]
        let provider = LivePurchasesProvider(sdk: sdk)

        let started = AsyncSignal()
        let gate = SuspensionGate()
        sdk.offeringsStarted = started
        sdk.offeringsGate = gate

        let purchase = Task { try await provider.purchase(packageID: "annual", authorizedAccountID: "account-a") }
        await started.wait()
        sdk.appUserID = FakeRevenueCatSDK.anonymousID
        gate.release()

        do {
            _ = try await purchase.value
            XCTFail("A guest identity must never transact")
        } catch {
            XCTAssertEqual(error as? ProviderIdentityError, .identityChanged)
        }
        XCTAssertTrue(sdk.purchaseCalls.isEmpty)
    }

    /// The check right after the offering await is its own guard: an identity that changed must be
    /// reported as an identity refusal, never as "this offering has no such package".
    func testIdentityChangeIsReportedBeforeAnyPackageMismatch() async {
        let sdk = FakeRevenueCatSDK()
        sdk.appUserID = "account-a"
        sdk.packages = [monthlyPackage]
        let provider = LivePurchasesProvider(sdk: sdk)

        let started = AsyncSignal()
        let gate = SuspensionGate()
        sdk.offeringsStarted = started
        sdk.offeringsGate = gate

        let purchase = Task { try await provider.purchase(packageID: "annual", authorizedAccountID: "account-a") }
        await started.wait()
        sdk.appUserID = "account-b"
        gate.release()

        do {
            _ = try await purchase.value
            XCTFail("A purchase must not reach the store after an identity change")
        } catch {
            XCTAssertEqual(
                error as? ProviderIdentityError,
                .identityChanged,
                "An unauthorized session must not learn whether the offering carries the package"
            )
        }
        XCTAssertTrue(sdk.purchaseCalls.isEmpty)
    }

    func testRestoreIsAbortedWhenTheIdentityIsNotTheAuthorizedAccount() async {
        let sdk = FakeRevenueCatSDK()
        sdk.appUserID = FakeRevenueCatSDK.anonymousID
        let provider = LivePurchasesProvider(sdk: sdk)

        do {
            _ = try await provider.restorePurchases(authorizedAccountID: "account-a")
            XCTFail("A restore must not run anonymously")
        } catch {
            XCTAssertEqual(error as? ProviderIdentityError, .identityChanged)
        }
        XCTAssertEqual(sdk.restoreCalls, 0)
    }

    func testPurchaseRunsForTheAuthorizedIdentity() async throws {
        let sdk = FakeRevenueCatSDK()
        sdk.appUserID = "account-a"
        sdk.packages = [annualPackage]
        let provider = LivePurchasesProvider(sdk: sdk)

        _ = try await provider.purchase(packageID: "annual", authorizedAccountID: "account-a")

        XCTAssertEqual(sdk.purchaseCalls, ["annual"])
        XCTAssertEqual(sdk.offeringsCalls, 1)
    }

    func testPurchaseRejectsAPackageOutsideTheOffering() async {
        let sdk = FakeRevenueCatSDK()
        sdk.appUserID = "account-a"
        sdk.packages = [monthlyPackage]
        let provider = LivePurchasesProvider(sdk: sdk)

        do {
            _ = try await provider.purchase(packageID: "annual", authorizedAccountID: "account-a")
            XCTFail("A package outside the offering must not be bought")
        } catch {
            XCTAssertEqual(error as? ErrorCode, .productNotAvailableForPurchaseError)
        }
        XCTAssertTrue(sdk.purchaseCalls.isEmpty)
    }
}
