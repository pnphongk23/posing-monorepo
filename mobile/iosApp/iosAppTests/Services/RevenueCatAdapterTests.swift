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
    var onCustomerInfoUpdated: (() -> Void)?

    var packages: [ProviderPackage]
    var packagesError: Error?
    var purchaseError: Error?
    var restoreError: Error?
    var logInError: Error?
    /// Accounts whose entitlement the fake reports as active. Everything else is not entitled.
    var entitledAccounts: Set<String>

    private(set) var configuredKeys: [String] = []
    private(set) var logInCalls: [String] = []
    private(set) var logOutCalls = 0
    private(set) var customerInfoCalls = 0
    private(set) var packagesCalls = 0
    private(set) var purchaseCalls: [String] = []
    private(set) var restoreCalls = 0

    var customerInfoStarted: AsyncSignal?
    var customerInfoGate: SuspensionGate?
    var logInStarted: AsyncSignal?
    var logInGate: SuspensionGate?
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
        if let logInError { throw logInError }
        appUserID = accountID
        return currentCustomer()
    }

    func logOut() async throws -> ProviderCustomer {
        logOutCalls += 1
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
        if let packagesError { throw packagesError }
        return packages
    }

    func purchase(packageID: String) async throws -> ProviderCustomer {
        purchaseCalls.append(packageID)
        purchaseStarted?.fire()
        let result = currentCustomer()
        await purchaseGate?.wait()
        if let purchaseError { throw purchaseError }
        return result
    }

    func restorePurchases() async throws -> ProviderCustomer {
        restoreCalls += 1
        restoreStarted?.fire()
        let result = currentCustomer()
        await restoreGate?.wait()
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
        await adapter.clearAccount()
        gate.release()
        _ = await link.value

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
