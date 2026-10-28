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

/// The provider refused a transaction because its live identity is no longer the Account the
/// adapter authorized. It is never a store failure: the result is dropped, not reported as a buy.
enum ProviderIdentityError: Error, Equatable {
    case identityChanged
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
///
/// Store-changing calls take the Account the adapter authorized and must re-validate the live
/// provider identity themselves, immediately before touching the store: only the provider knows
/// whether an identity change landed inside its own awaits.
@MainActor
protocol PurchasesProviding: AnyObject {
    var appUserID: String? { get }
    var isAnonymous: Bool { get }
    var onCustomerInfoUpdated: (() -> Void)? { get set }
    func configure(apiKey: String)
    func logIn(_ accountID: String) async throws -> ProviderCustomer
    func logOut() async throws -> ProviderCustomer
    func customerInfo() async throws -> ProviderCustomer
    func packages() async throws -> [ProviderPackage]
    func purchase(packageID: String, authorizedAccountID: String) async throws -> ProviderCustomer
    func restorePurchases(authorizedAccountID: String) async throws -> ProviderCustomer
}

/// Native RevenueCat owner. Fails closed when the SDK key or the entitlement id is missing or still
/// a placeholder. The entitlement id comes from `Info.plist` (`REVENUECAT_ENTITLEMENT_ID`), and
/// products are selected from the offering by package type — no product id lives in code.
///
/// Three rules hold the access model together:
/// 1. nothing is entitled unless a linked Account is also the provider identity;
/// 2. no store transaction runs without that same identity, re-checked after every await;
/// 3. identity changes are serialized, invalidate access immediately and reconcile the provider, so
///    a superseded login can never leave the SDK (or the snapshot) on a stranger's identity.
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
    /// signed-in Account is linked — including during an identity transition.
    private(set) var linkedAccountID: String?
    /// Bumped by every identity change. A provider result is applied only while the epoch — and the
    /// identity captured with it — still hold after the await.
    private var identityEpoch: UInt64 = 0
    /// Serializes provider identity changes so two overlapping logins cannot interleave.
    private var identityChain: Task<Void, Never>?
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
        guard isConfigured, !accountID.isEmpty else { return }
        guard accountID != linkedAccountID || provider.appUserID != accountID else { return }
        // Access ends before the provider call: during the transition nobody is linked.
        invalidateForIdentityTransition(next: .loading, event: "account_link_requested")
        await enqueueIdentityChange(accountID: accountID)
    }

    /// Clears the provider context at sign-out/account switch so the next Account (or a guest) can
    /// never reuse the previous Account's entitlement (`FEAT-011` E4). Local state is dropped before
    /// the provider call so logout never depends on network success.
    func clearAccount() async {
        // Access ends before the provider call, whatever the network does.
        invalidateForIdentityTransition(next: .notEntitled, event: "sign_out_requested")
        await enqueueIdentityChange(accountID: nil)
    }

    /// No access survives an identity transition, and no transaction can start while it runs.
    private func invalidateForIdentityTransition(next: PurchaseGatewayState, event: String) {
        identityEpoch &+= 1
        linkedAccountID = nil
        lastSnapshot = PurchaseSnapshot(state: isConfigured ? next : .unconfigured, products: loadedProducts)
        logEvent("purchase_identity_change", ["source": "revenuecat", "outcome": event])
    }

    /// Identity changes run one at a time: a `logIn` that started earlier must finish before the
    /// next transition touches the provider identity.
    private func enqueueIdentityChange(accountID: String?) async {
        let previous = identityChain
        // The epoch belongs to the request, not to the moment the queue reaches it: a request that a
        // later sign-out or account switch already superseded must never reach the provider, or it
        // would adopt the newer epoch and link an Account the user has left.
        let requestEpoch = identityEpoch
        let task = Task { @MainActor [weak self] in
            _ = await previous?.value
            await self?.performIdentityChange(accountID: accountID, requestEpoch: requestEpoch)
        }
        identityChain = task
        await task.value
    }

    private func performIdentityChange(accountID: String?, requestEpoch: UInt64) async {
        guard isConfigured else {
            lastSnapshot = PurchaseSnapshot(state: .unconfigured, products: loadedProducts)
            return
        }
        guard requestEpoch == identityEpoch else {
            logDropped(reason: "identity_superseded")
            return
        }
        let epoch = requestEpoch
        do {
            if let accountID {
                let customer = try await provider.logIn(accountID)
                guard epoch == identityEpoch else {
                    // Superseded: never adopt the result, and put the SDK back where we own it.
                    lastSnapshot = PurchaseSnapshot(state: .notEntitled, products: loadedProducts)
                    await performReconcile(reason: "identity_superseded")
                    return
                }
                guard provider.appUserID == accountID, !provider.isAnonymous else {
                    linkedAccountID = nil
                    lastSnapshot = PurchaseSnapshot(state: .notEntitled, products: loadedProducts)
                    await performReconcile(reason: "provider_identity_mismatch")
                    return
                }
                linkedAccountID = accountID
                apply(customer, products: loadedProducts, authorizedAccountID: accountID)
            } else {
                _ = try await provider.logOut()
                guard epoch == identityEpoch else {
                    lastSnapshot = PurchaseSnapshot(state: .notEntitled, products: loadedProducts)
                    await performReconcile(reason: "identity_superseded")
                    return
                }
                linkedAccountID = nil
                lastSnapshot = PurchaseSnapshot(state: .notEntitled, products: loadedProducts)
            }
        } catch {
            guard epoch == identityEpoch else {
                lastSnapshot = PurchaseSnapshot(state: .notEntitled, products: loadedProducts)
                await performReconcile(reason: "identity_superseded")
                return
            }
            // A failed link must not leave a stale identity claiming to be current.
            linkedAccountID = nil
            lastSnapshot = PurchaseSnapshot(state: .notEntitled, products: loadedProducts)
        }
    }

    /// Queued reconciliation: a dropped or superseded provider call may still have changed the SDK
    /// identity, so bring the SDK back to the identity this adapter actually owns.
    private func reconcileProviderIdentity() async {
        let previous = identityChain
        let task = Task { @MainActor [weak self] in
            _ = await previous?.value
            await self?.performReconcile(reason: "identity_reconciled")
        }
        identityChain = task
        await task.value
    }

    private func performReconcile(reason: String) async {
        guard isConfigured else { return }
        if let owned = linkedAccountID {
            guard provider.appUserID != owned || provider.isAnonymous else { return }
            _ = try? await provider.logIn(owned)
            guard provider.appUserID == owned else {
                logDropped(reason: reason)
                return
            }
            return
        }
        guard !provider.isAnonymous, provider.appUserID != nil else { return }
        _ = try? await provider.logOut()
        logDropped(reason: reason)
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
        let customer: ProviderCustomer
        do {
            customer = try await provider.customerInfo()
        } catch {
            guard identityHolds(token) else {
                return dropSnapshot(reason: "identity_changed")
            }
            return lastSnapshot
        }
        guard identityHolds(token) else {
            return dropSnapshot(reason: "identity_changed")
        }
        guard let accountID = ownedAccountID(for: token) else {
            // The provider may still hold an entitled identity from an earlier launch or a
            // superseded login. No Account owns it, so access is dropped before anything else runs,
            // then the SDK is put back on the anonymous identity instead of being left entitled.
            let snapshot = PurchaseSnapshot(state: .notEntitled, products: loadedProducts)
            lastSnapshot = snapshot
            await reconcileProviderIdentity()
            return snapshot
        }
        return apply(customer, products: loadedProducts, authorizedAccountID: accountID)
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
            guard identityHolds(token) else {
                return dropSnapshot(reason: "identity_changed")
            }
            return failClosed(state: .noOffering)
        }
        guard identityHolds(token) else {
            return dropSnapshot(reason: "identity_changed")
        }

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
        // M2: no guest purchase, and no transaction under an identity this adapter does not own.
        guard let token = transactionIdentity(), let accountID = token.accountID else {
            return failClosed(state: .signInRequired)
        }
        // Only a package of the last loaded offering is purchasable.
        guard loadedProducts.contains(where: { $0.identifier == packageID }) else {
            return failClosed(state: .purchaseFailed, failure: .other)
        }
        do {
            let customer = try await provider.purchase(
                packageID: packageID,
                authorizedAccountID: accountID
            )
            guard identityHolds(token) else {
                return dropSnapshot(reason: "identity_changed")
            }
            return apply(customer, products: loadedProducts, authorizedAccountID: accountID)
        } catch {
            if error is ProviderIdentityError {
                await reconcileProviderIdentity()
                return dropSnapshot(reason: "provider_identity_changed")
            }
            let failure = PurchaseFailure(error)
            guard identityHolds(token) else {
                return dropSnapshot(reason: "identity_changed")
            }
            let state: PurchaseGatewayState = failure == .cancelled ? .purchaseCancelled : .purchaseFailed
            return failClosed(state: state, failure: failure)
        }
    }

    func restore() async -> PurchaseSnapshot {
        guard isConfigured else {
            return failClosed(state: .unconfigured)
        }
        guard let token = transactionIdentity(), let accountID = token.accountID else {
            return failClosed(state: .signInRequired)
        }
        do {
            let customer = try await provider.restorePurchases(authorizedAccountID: accountID)
            guard identityHolds(token) else {
                return dropSnapshot(reason: "identity_changed")
            }
            return apply(customer, products: loadedProducts, authorizedAccountID: accountID)
        } catch {
            if error is ProviderIdentityError {
                await reconcileProviderIdentity()
                return dropSnapshot(reason: "provider_identity_changed")
            }
            let failure = PurchaseFailure(error)
            guard identityHolds(token) else {
                return dropSnapshot(reason: "identity_changed")
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

    /// Entitlement facts are only ever applied to the Account that owns the provider identity.
    @discardableResult
    private func apply(
        _ customer: ProviderCustomer,
        products: [PurchaseProduct],
        authorizedAccountID: String?
    ) -> PurchaseSnapshot {
        guard let authorizedAccountID,
              linkedAccountID == authorizedAccountID,
              provider.appUserID == authorizedAccountID,
              !provider.isAnonymous else {
            logDropped(reason: "unlinked_identity")
            let snapshot = PurchaseSnapshot(state: .notEntitled, products: products)
            lastSnapshot = snapshot
            return snapshot
        }
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

    /// A linked Account that is provably the provider identity, or nil.
    private func ownedAccountID(for token: IdentityToken) -> String? {
        guard let accountID = token.accountID,
              token.providerUserID == accountID,
              !provider.isAnonymous else { return nil }
        return accountID
    }

    /// A store transaction needs the same proof, re-taken immediately before the call.
    private func transactionIdentity() -> IdentityToken? {
        let token = captureIdentity()
        guard ownedAccountID(for: token) != nil else { return nil }
        return token
    }

    /// A dropped result is silent apart from its analytics event: the snapshot already in place is
    /// the only one that can be attributed to the current identity.
    private func dropSnapshot(reason: String) -> PurchaseSnapshot {
        logDropped(reason: reason)
        return lastSnapshot
    }

    private func logDropped(reason: String) {
        logEvent("purchase_snapshot_dropped", ["source": "revenuecat", "outcome": reason])
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

    var snapshots: AnyPublisher<PurchaseSnapshot, Never> {
        $lastSnapshot.eraseToAnyPublisher()
    }
}

// MARK: - Store seam

/// One offering in app-domain types, so the identity boundary above the SDK can be driven by a fake
/// that suspends `offering()`.
struct ProviderOffering: Sendable, Equatable {
    let packages: [ProviderPackage]
}

struct ProviderPurchaseOutcome: Sendable, Equatable {
    let customer: ProviderCustomer
    let userCancelled: Bool
}

/// The SDK calls the live provider makes, in app-domain types.
///
/// Only `LiveRevenueCatSDK` touches `Purchases.shared`. Everything above this line is
/// store-agnostic, so the identity re-check around a transaction is testable with a fake SDK that
/// suspends `offering()` — the same shape the real SDK has.
@MainActor
protocol RevenueCatSDK: AnyObject {
    var isConfigured: Bool { get }
    var isAnonymous: Bool { get }
    var appUserID: String { get }
    var onCustomerInfoUpdated: (() -> Void)? { get set }
    func configure(apiKey: String)
    func logIn(_ accountID: String) async throws -> ProviderCustomer
    func logOut() async throws -> ProviderCustomer
    func customerInfo() async throws -> ProviderCustomer
    func offering() async throws -> ProviderOffering
    /// The authorization callback runs synchronously inside the implementation, immediately before
    /// the store call, with no suspension in between. A switched identity therefore aborts before
    /// any transaction is created.
    func purchase(packageIdentifier: String, authorize: () throws -> Void) async throws -> ProviderPurchaseOutcome
    func restorePurchases() async throws -> ProviderCustomer
}

/// The identity boundary around the store: no transaction reaches the SDK unless the live identity
/// is still exactly the Account the adapter authorized, re-checked after every nested await.
@MainActor
final class LivePurchasesProvider: PurchasesProviding {
    private let sdk: any RevenueCatSDK

    /// Production wiring: the live RevenueCat SDK.
    convenience init() {
        self.init(sdk: LiveRevenueCatSDK())
    }

    init(sdk: any RevenueCatSDK) {
        self.sdk = sdk
    }

    var appUserID: String? { sdk.isConfigured ? sdk.appUserID : nil }

    var isAnonymous: Bool { !sdk.isConfigured || sdk.isAnonymous }

    var onCustomerInfoUpdated: (() -> Void)? {
        get { sdk.onCustomerInfoUpdated }
        set { sdk.onCustomerInfoUpdated = newValue }
    }

    func configure(apiKey: String) {
        sdk.configure(apiKey: apiKey)
    }

    func logIn(_ accountID: String) async throws -> ProviderCustomer {
        try await translate { try await sdk.logIn(accountID) }
    }

    func logOut() async throws -> ProviderCustomer {
        try await translate { try await sdk.logOut() }
    }

    func customerInfo() async throws -> ProviderCustomer {
        try await translate { try await sdk.customerInfo() }
    }

    func packages() async throws -> [ProviderPackage] {
        try await translate { try await sdk.offering().packages }
    }

    func purchase(packageID: String, authorizedAccountID: String) async throws -> ProviderCustomer {
        let offering = try await translate { try await sdk.offering() }
        // The offering await can span a sign-out or an account switch: prove the live identity again
        // immediately before the store is touched, not only at the adapter's entry.
        try validateTransactionIdentity(authorizedAccountID)
        guard offering.packages.contains(where: { $0.identifier == packageID }) else {
            throw ErrorCode.productNotAvailableForPurchaseError
        }
        try validateTransactionIdentity(authorizedAccountID)
        let outcome = try await translate {
            try await sdk.purchase(packageIdentifier: packageID) {
                // Runs at the transaction boundary, after every await: no identity change can slip
                // between this check and the store call.
                try validateTransactionIdentity(authorizedAccountID)
            }
        }
        guard !outcome.userCancelled else {
            throw ErrorCode.purchaseCancelledError
        }
        return outcome.customer
    }

    func restorePurchases(authorizedAccountID: String) async throws -> ProviderCustomer {
        // A restore attributes the store's receipts to whoever the SDK is signed in as, so the
        // identity has to be proven immediately before the call.
        try validateTransactionIdentity(authorizedAccountID)
        return try await translate { try await sdk.restorePurchases() }
    }

    private func validateTransactionIdentity(_ authorizedAccountID: String) throws {
        guard sdk.isConfigured, !sdk.isAnonymous, sdk.appUserID == authorizedAccountID else {
            throw ProviderIdentityError.identityChanged
        }
    }

    private func translate<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch {
            if error is ProviderIdentityError { throw error }
            throw (error as NSError).asErrorCode ?? ErrorCode.unknownError
        }
    }
}

// MARK: - Live SDK

/// Forwards the seam to `Purchases.shared`. No product, entitlement or secret value lives here:
/// ids arrive from the store metadata and from build configuration.
@MainActor
final class LiveRevenueCatSDK: NSObject, RevenueCatSDK {
    var onCustomerInfoUpdated: (() -> Void)?

    var isConfigured: Bool { Purchases.isConfigured }

    var isAnonymous: Bool { !Purchases.isConfigured || Purchases.shared.isAnonymous }

    var appUserID: String { Purchases.isConfigured ? Purchases.shared.appUserID : "" }

    /// The offering resolved by `offering()`. A purchase looks its package up here instead of
    /// fetching the offering again: a second fetch would put a suspension between the identity
    /// check and the store call, and a sign-out could land in it.
    private var lastResolvedOffering: Offering?

    func configure(apiKey: String) {
        Purchases.configure(withAPIKey: apiKey)
        Purchases.shared.delegate = self
    }

    func logIn(_ accountID: String) async throws -> ProviderCustomer {
        Self.customer(try await translate { try await Purchases.shared.logIn(accountID) }.customerInfo)
    }

    func logOut() async throws -> ProviderCustomer {
        Self.customer(try await translate { try await Purchases.shared.logOut() })
    }

    func customerInfo() async throws -> ProviderCustomer {
        Self.customer(try await translate { try await Purchases.shared.customerInfo() })
    }

    func offering() async throws -> ProviderOffering {
        let offering = try await fetchOffering()
        lastResolvedOffering = offering
        return ProviderOffering(
            packages: offering.availablePackages.map { package in
                ProviderPackage(
                    identifier: package.identifier,
                    packageType: PurchasePackageType(storeType: package.packageType),
                    localizedPrice: package.localizedPriceString
                )
            }
        )
    }

    func purchase(packageIdentifier: String, authorize: () throws -> Void) async throws -> ProviderPurchaseOutcome {
        // Everything above the store call below is synchronous on purpose: no await may sit
        // between the authorization check and `Purchases.shared.purchase(package:)`, or a sign-out
        // landing in that window would let the store charge under the wrong identity.
        guard let offering = lastResolvedOffering,
              let package = offering.availablePackages.first(where: { $0.identifier == packageIdentifier }) else {
            throw ErrorCode.productNotAvailableForPurchaseError
        }
        try authorize()
        let result = try await translate { try await Purchases.shared.purchase(package: package) }
        return ProviderPurchaseOutcome(
            customer: Self.customer(result.customerInfo),
            userCancelled: result.userCancelled
        )
    }

    func restorePurchases() async throws -> ProviderCustomer {
        Self.customer(try await translate { try await Purchases.shared.restorePurchases() })
    }

    private func fetchOffering() async throws -> Offering {
        let offerings = try await translate { try await Purchases.shared.offerings() }
        guard let offering = offerings.current
            ?? offerings.offering(identifier: RevenueCatAdapter.fallbackOfferingID) else {
            throw ErrorCode.productNotAvailableForPurchaseError
        }
        return offering
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

extension LiveRevenueCatSDK: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor [weak self] in
            self?.onCustomerInfoUpdated?()
        }
    }
}
