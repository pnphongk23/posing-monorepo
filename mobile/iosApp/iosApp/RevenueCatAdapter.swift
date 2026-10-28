import Foundation
import Combine
import RevenueCat
import FirebaseAnalytics

enum PurchaseGatewayState: String, Sendable {
    case loading = "LOADING"
    case unconfigured = "UNCONFIGURED"
    case noOffering = "NO_OFFERING"
    case notEntitled = "NOT_ENTITLED"
    case entitled = "ENTITLED"
    case purchasePending = "PURCHASE_PENDING"
    case purchaseCancelled = "PURCHASE_CANCELLED"
    case purchaseFailed = "PURCHASE_FAILED"
    case billingRetry = "BILLING_RETRY"
    case expired = "EXPIRED"
    case revoked = "REVOKED"
    /// M2: purchase and restore are Account-bound, so a signed-out request is routed to sign-in
    /// instead of ever reaching the store with the SDK's anonymous app user id.
    case signInRequired = "SIGN_IN_REQUIRED"
}

/// Code-owned mirror of the RevenueCat package type. The client sells by package type, never by
/// product identifier, so the store's product ids can change without a code change.
enum PurchasePackageType: String, Sendable {
    case annual
    case monthly
    /// Lifetime, weekly, six-month, custom, unknown: not sold by this paywall.
    case other

    init(storeType: PackageType) {
        switch storeType {
        case .annual: self = .annual
        case .monthly: self = .monthly
        default: self = .other
        }
    }
}

struct PurchaseProduct: Sendable, Equatable {
    /// Package identifier from the loaded offering. Never a store product identifier.
    let identifier: String
    let packageType: PurchasePackageType
    let localizedPrice: String
    let period: String?
}

/// Store failure kinds the paywall can act on. RevenueCat's `ErrorCode` is mapped once, here, so
/// the UI never depends on SDK error values and analytics only ever sees a kind.
enum PurchaseFailure: String, Sendable, Equatable {
    case cancelled
    case receiptOwnedByOtherAccount
    case network
    case storeProblem
    case other

    init(_ code: ErrorCode) {
        switch code {
        case .purchaseCancelledError:
            self = .cancelled
        case .receiptAlreadyInUseError, .receiptInUseByOtherSubscriberError, .purchaseBelongsToOtherUser:
            self = .receiptOwnedByOtherAccount
        case .networkError, .offlineConnectionError:
            self = .network
        case .storeProblemError, .productNotAvailableForPurchaseError, .productRequestTimedOut:
            self = .storeProblem
        default:
            self = .other
        }
    }

    init(_ error: Error) {
        if let code = error as? ErrorCode {
            self.init(code)
        } else {
            self = .other
        }
    }
}

struct PurchaseSnapshot: Sendable, Equatable {
    let state: PurchaseGatewayState
    let products: [PurchaseProduct]
    let failure: PurchaseFailure?

    init(
        state: PurchaseGatewayState,
        products: [PurchaseProduct],
        failure: PurchaseFailure? = nil
    ) {
        self.state = state
        self.products = products
        self.failure = failure
    }
}

/// Entitlement facts extracted once from `CustomerInfo.entitlements[id]`, so the state mapping is a
/// pure function the tests can drive without constructing a `CustomerInfo`.
struct EntitlementFacts: Sendable, Equatable {
    let isActive: Bool
    let billingIssueDetectedAt: Date?
    let expirationDate: Date?
}

/// The customer facts a provider call produced. Entitlements stay keyed by id here; the configured
/// id is chosen by the adapter, never the seam. Identity is not carried here on purpose: the pinned
/// SDK's `CustomerInfo` cannot prove which app user id a payload belongs to.
struct ProviderCustomer: Sendable, Equatable {
    let entitlements: [String: EntitlementFacts]

    init(entitlements: [String: EntitlementFacts] = [:]) {
        self.entitlements = entitlements
    }
}

/// One purchasable package of the resolved offering.
struct ProviderPackage: Sendable, Equatable {
    let identifier: String
    let packageType: PurchasePackageType
    let localizedPrice: String
}

/// Seam over the RevenueCat SDK: exactly the calls the adapter makes, in app-domain types.
///
/// The delegate payload is deliberately absent. It cannot prove which identity it belongs to
/// (no aliases API on `CustomerInfo` in purchases-ios 5.87.1 and `originalAppUserId` can stay
/// anonymous after linking), so it is only a refresh trigger.
@MainActor
protocol PurchasesProviding: AnyObject {
    var appUserID: String? { get }
    var onCustomerInfoUpdated: (() -> Void)? { get set }
    func configure(apiKey: String)
    func logIn(_ accountID: String) async throws -> ProviderCustomer
    func logOut() async throws -> ProviderCustomer
    func customerInfo() async throws -> ProviderCustomer
    func packages() async throws -> [ProviderPackage]
    func purchase(packageID: String) async throws -> ProviderCustomer
    func restorePurchases() async throws -> ProviderCustomer
}

/// Native RevenueCat owner. Fails closed when the SDK key or the entitlement id is missing or still
/// a placeholder. The entitlement id comes from `Info.plist` (`REVENUECAT_ENTITLEMENT_ID`), and
/// products are selected from the offering by package type — no product id lives in code.
@MainActor
final class RevenueCatAdapter: NSObject, ObservableObject {
    static let shared = RevenueCatAdapter()

    static let sdkKeyInfoKey = "RevenueCatPublicSDKKey"
    static let entitlementIDInfoKey = "RevenueCatEntitlementID"
    /// Offering used when RevenueCat has no `current` offering selected.
    static let fallbackOfferingID = "default"

    private let provider: any PurchasesProviding
    private let logEvent: (String, [String: String]) -> Void

    private(set) var isConfigured = false
    /// Account currently applied to the RevenueCat customer (`FEAT-011` FR-006). Nil while no
    /// signed-in Account is linked, which is also what makes `linkAccount` idempotent.
    private(set) var linkedAccountID: String?
    /// Bumped by every identity change. A provider result is applied only while the epoch — and the
    /// identity captured with it — still hold after the await.
    private var identityEpoch: UInt64 = 0
    private var entitlementID: String?
    /// Products of the last successfully loaded offering. A purchase of anything else is rejected.
    private var loadedProducts: [PurchaseProduct] = []

    @Published private(set) var lastSnapshot = PurchaseSnapshot(state: .unconfigured, products: [])

    private override init() {
        self.provider = LivePurchasesProvider()
        self.logEvent = Self.analyticsLog
        super.init()
    }

    /// Test seam: a fake provider plus an explicit entitlement id, so the identity and entitlement
    /// state machine runs without the store, a network or a `CustomerInfo`.
    init(
        provider: any PurchasesProviding,
        entitlementID: String?,
        logEvent: @escaping (String, [String: String]) -> Void = { _, _ in }
    ) {
        self.provider = provider
        self.logEvent = logEvent
        super.init()
        self.entitlementID = AppConfigService.isValidIdentifier(entitlementID) ? entitlementID : nil
        isConfigured = self.entitlementID != nil
        observeProviderIfConfigured()
    }

    func configureFromEnvironment() {
        let bundle = Bundle.main
        let key = bundle.object(forInfoDictionaryKey: Self.sdkKeyInfoKey) as? String
        let configuredEntitlementID = bundle.object(forInfoDictionaryKey: Self.entitlementIDInfoKey) as? String

        guard AppConfigService.isValidRevenueCatKey(key),
              let key,
              AppConfigService.isValidIdentifier(configuredEntitlementID),
              let configuredEntitlementID else {
            entitlementID = nil
            isConfigured = false
            lastSnapshot = PurchaseSnapshot(state: .unconfigured, products: [])
            return
        }

        entitlementID = configuredEntitlementID
        isConfigured = true
        observeProviderIfConfigured()
        provider.configure(apiKey: key)
        refreshEntitlement()
    }

    // MARK: - Identity

    /// Binds the RevenueCat customer to the signed-in Account so a purchase follows that Account
    /// across devices and re-entry instead of the anonymous app user id (`FEAT-011` FR-006).
    func linkAccount(_ accountID: String) async {
        guard isConfigured, !accountID.isEmpty, accountID != linkedAccountID else { return }
        identityEpoch &+= 1
        let token = captureIdentity()
        let products = loadedProducts
        do {
            let customer = try await provider.logIn(accountID)
            // The identity can be cleared or switched while `logIn` is in flight: fail closed.
            guard token.epoch == identityEpoch,
                  token.accountID == linkedAccountID,
                  provider.appUserID == accountID else {
                logDropped()
                return
            }
            linkedAccountID = accountID
            apply(customer, products: products)
        } catch {
            guard token.epoch == identityEpoch else {
                logDropped()
                return
            }
            // A failed link must not leave a stale identity claiming to be current.
            linkedAccountID = nil
            lastSnapshot = PurchaseSnapshot(state: .notEntitled, products: products)
        }
    }

    /// Clears the provider context at sign-out/account switch so the next Account (or a guest) can
    /// never reuse the previous Account's entitlement (`FEAT-011` E4). Local state is dropped before
    /// the provider call so logout never depends on network success.
    func clearAccount() async {
        identityEpoch &+= 1
        let epoch = identityEpoch
        linkedAccountID = nil
        let products = loadedProducts
        guard isConfigured else {
            lastSnapshot = PurchaseSnapshot(state: .unconfigured, products: products)
            return
        }
        lastSnapshot = PurchaseSnapshot(state: .loading, products: products)
        do {
            _ = try await provider.logOut()
        } catch {
            // RevenueCat rejects `logOut` for an already-anonymous customer; the entitlement is gone
            // either way, so the state below is the truthful one.
        }
        // Fail closed regardless of the provider outcome. A concurrent link owns the snapshot.
        guard epoch == identityEpoch, linkedAccountID == nil else {
            logDropped()
            return
        }
        lastSnapshot = PurchaseSnapshot(state: .notEntitled, products: products)
    }

    // MARK: - Entitlement

    func refreshEntitlement() {
        guard isConfigured else { return }
        Task { await self.refreshSnapshot() }
    }

    /// Delegate pushes are only a trigger: the pinned SDK cannot prove which identity a payload
    /// belongs to, so the same epoch-guarded refresh runs instead of applying the payload.
    private func handleProviderUpdate() {
        Task { await self.refreshSnapshot() }
    }

    @discardableResult
    func refreshSnapshot() async -> PurchaseSnapshot {
        guard isConfigured else {
            return failClosed(state: .unconfigured)
        }
        let token = captureIdentity()
        do {
            let customer = try await provider.customerInfo()
            guard identityHolds(token) else { return dropSnapshot() }
            return apply(customer, products: loadedProducts)
        } catch {
            guard identityHolds(token) else { return dropSnapshot() }
            return lastSnapshot
        }
    }

    // MARK: - Offering and store

    func loadOffering() async -> PurchaseSnapshot {
        guard isConfigured else {
            return failClosed(state: .unconfigured)
        }
        let token = captureIdentity()
        let packages: [ProviderPackage]
        do {
            packages = try await provider.packages()
        } catch {
            guard identityHolds(token) else { return dropSnapshot() }
            return failClosed(state: .noOffering)
        }
        guard identityHolds(token) else { return dropSnapshot() }

        let products = PaywallPlanCatalog.ordered(
            packages.map { package in
                PurchaseProduct(
                    identifier: package.identifier,
                    packageType: package.packageType,
                    localizedPrice: package.localizedPrice,
                    period: Self.periodName(package.packageType)
                )
            }
        )
        guard !products.isEmpty else {
            loadedProducts = []
            return failClosed(state: .noOffering)
        }
        loadedProducts = products
        return await refreshSnapshot()
    }

    func purchase(packageID: String) async -> PurchaseSnapshot {
        guard isConfigured else {
            return failClosed(state: .unconfigured)
        }
        // M2: no guest purchase. The linked Account is the only identity allowed to own a
        // transaction, and this guard is the first line of defence for that rule.
        guard let accountID = linkedAccountID else {
            return failClosed(state: .signInRequired)
        }
        // Only a package of the last loaded offering is purchasable.
        guard loadedProducts.contains(where: { $0.identifier == packageID }) else {
            return failClosed(state: .purchaseFailed, failure: .other)
        }
        let token = captureIdentity()
        do {
            let customer = try await provider.purchase(packageID: packageID)
            guard identityHolds(token), provider.appUserID == accountID else {
                return dropSnapshot()
            }
            return apply(customer, products: loadedProducts)
        } catch {
            let failure = PurchaseFailure(error)
            guard identityHolds(token), provider.appUserID == accountID else {
                return dropSnapshot()
            }
            let state: PurchaseGatewayState = failure == .cancelled ? .purchaseCancelled : .purchaseFailed
            return failClosed(state: state, failure: failure)
        }
    }

    func restore() async -> PurchaseSnapshot {
        guard isConfigured else {
            return failClosed(state: .unconfigured)
        }
        guard let accountID = linkedAccountID else {
            return failClosed(state: .signInRequired)
        }
        let token = captureIdentity()
        do {
            let customer = try await provider.restorePurchases()
            guard identityHolds(token), provider.appUserID == accountID else {
                return dropSnapshot()
            }
            return apply(customer, products: loadedProducts)
        } catch {
            let failure = PurchaseFailure(error)
            guard identityHolds(token), provider.appUserID == accountID else {
                return dropSnapshot()
            }
            return failClosed(state: .purchaseFailed, failure: failure)
        }
    }

    // MARK: - Mapping

    /// Grace period: an Apple billing issue on an active entitlement still grants access.
    /// A billing retry is only reported once the entitlement itself is inactive.
    static func entitlementState(for facts: EntitlementFacts?, now: Date = Date()) -> PurchaseGatewayState {
        guard let facts else { return .notEntitled }
        if facts.isActive { return .entitled }
        if facts.billingIssueDetectedAt != nil { return .billingRetry }
        if let expirationDate = facts.expirationDate {
            return expirationDate < now ? .expired : .notEntitled
        }
        return .revoked
    }

    static func periodName(_ packageType: PurchasePackageType) -> String? {
        switch packageType {
        case .annual: return "year"
        case .monthly: return "month"
        case .other: return nil
        }
    }

    private func apply(_ customer: ProviderCustomer, products: [PurchaseProduct]) -> PurchaseSnapshot {
        let state = Self.entitlementState(for: entitlementFacts(of: customer))
        log(state: state)
        let snapshot = PurchaseSnapshot(state: state, products: products)
        lastSnapshot = snapshot
        return snapshot
    }

    private func failClosed(
        state: PurchaseGatewayState,
        failure: PurchaseFailure? = nil
    ) -> PurchaseSnapshot {
        log(state: state, failure: failure)
        let snapshot = PurchaseSnapshot(state: state, products: loadedProducts, failure: failure)
        lastSnapshot = snapshot
        return snapshot
    }

    private func entitlementFacts(of customer: ProviderCustomer) -> EntitlementFacts? {
        guard let entitlementID else { return nil }
        return customer.entitlements[entitlementID]
    }

    // MARK: - Identity guard

    private struct IdentityToken: Equatable {
        let epoch: UInt64
        let accountID: String?
        let providerUserID: String?
    }

    private func captureIdentity() -> IdentityToken {
        IdentityToken(epoch: identityEpoch, accountID: linkedAccountID, providerUserID: provider.appUserID)
    }

    /// The result of an await belongs to the identity that was current when the call started.
    private func identityHolds(_ token: IdentityToken) -> Bool {
        token == captureIdentity()
    }

    /// A dropped result is silent apart from its analytics event: the snapshot already in place is
    /// the only one that can be attributed to the current identity.
    private func dropSnapshot() -> PurchaseSnapshot {
        logDropped()
        return lastSnapshot
    }

    private func logDropped() {
        logEvent("purchase_snapshot_dropped", ["source": "revenuecat", "outcome": "identity_changed"])
    }

    private func log(state: PurchaseGatewayState, failure: PurchaseFailure? = nil) {
        var parameters = ["source": "revenuecat", "outcome": state.rawValue.lowercased()]
        if let failure {
            parameters["failure"] = failure.rawValue
        }
        logEvent("purchase_state", parameters)
    }

    private func observeProviderIfConfigured() {
        guard isConfigured else { return }
        provider.onCustomerInfoUpdated = { [weak self] in
            self?.handleProviderUpdate()
        }
    }

    private static func analyticsLog(_ name: String, _ parameters: [String: String]) {
        Analytics.logEvent(name, parameters: parameters)
    }
}

extension RevenueCatAdapter: PurchaseGateway {
    var snapshot: PurchaseSnapshot { lastSnapshot }
}

// MARK: - Live provider

/// Forwards the seam to `Purchases.shared`. No product, entitlement or secret value lives here:
/// ids arrive from the store metadata and from build configuration.
@MainActor
final class LivePurchasesProvider: NSObject, PurchasesProviding {
    var onCustomerInfoUpdated: (() -> Void)?

    var appUserID: String? {
        Purchases.isConfigured ? Purchases.shared.appUserID : nil
    }

    func configure(apiKey: String) {
        Purchases.configure(withAPIKey: apiKey)
        Purchases.shared.delegate = self
    }

    func logIn(_ accountID: String) async throws -> ProviderCustomer {
        let result = try await translate { try await Purchases.shared.logIn(accountID) }
        return Self.customer(result.customerInfo)
    }

    func logOut() async throws -> ProviderCustomer {
        Self.customer(try await translate { try await Purchases.shared.logOut() })
    }

    func customerInfo() async throws -> ProviderCustomer {
        Self.customer(try await translate { try await Purchases.shared.customerInfo() })
    }

    func packages() async throws -> [ProviderPackage] {
        let offerings = try await translate { try await Purchases.shared.offerings() }
        guard let offering = offerings.current ?? offerings.offering(identifier: RevenueCatAdapter.fallbackOfferingID) else {
            throw ErrorCode.productNotAvailableForPurchaseError
        }
        return offering.availablePackages.map { package in
            ProviderPackage(
                identifier: package.identifier,
                packageType: PurchasePackageType(storeType: package.packageType),
                localizedPrice: package.localizedPriceString
            )
        }
    }

    func purchase(packageID: String) async throws -> ProviderCustomer {
        let offerings = try await translate { try await Purchases.shared.offerings() }
        let offering = offerings.current ?? offerings.offering(identifier: RevenueCatAdapter.fallbackOfferingID)
        guard let package = offering?.availablePackages.first(where: { $0.identifier == packageID }) else {
            throw ErrorCode.productNotAvailableForPurchaseError
        }
        let result = try await translate { try await Purchases.shared.purchase(package: package) }
        guard !result.userCancelled else {
            throw ErrorCode.purchaseCancelledError
        }
        return Self.customer(result.customerInfo)
    }

    func restorePurchases() async throws -> ProviderCustomer {
        Self.customer(try await translate { try await Purchases.shared.restorePurchases() })
    }

    private func translate<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch {
            throw (error as NSError).asErrorCode ?? ErrorCode.unknownError
        }
    }

    private static func customer(_ info: CustomerInfo) -> ProviderCustomer {
        ProviderCustomer(
            entitlements: info.entitlements.all.mapValues { entitlement in
                EntitlementFacts(
                    isActive: entitlement.isActive,
                    billingIssueDetectedAt: entitlement.billingIssueDetectedAt,
                    expirationDate: entitlement.expirationDate
                )
            }
        )
    }
}

extension LivePurchasesProvider: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor [weak self] in
            self?.onCustomerInfoUpdated?()
        }
    }
}
