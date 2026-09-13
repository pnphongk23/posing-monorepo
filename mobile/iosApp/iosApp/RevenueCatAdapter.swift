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
}

struct PurchaseProduct: Sendable, Equatable {
    let identifier: String
    let localizedPrice: String
    let period: String?
}

struct PurchaseSnapshot: Sendable, Equatable {
    let state: PurchaseGatewayState
    let products: [PurchaseProduct]
    let errorCode: String?
}

/// Native RevenueCat owner. Fails closed when SDK key is missing/placeholder or Firebase is unavailable for analytics only.
@MainActor
final class RevenueCatAdapter: NSObject, ObservableObject {
    static let shared = RevenueCatAdapter()
    static let entitlementID = "snap pose premium"
    static let offeringID = "default"
    static let productIDs = ["premium_yearly", "premium_monthly"]

    private(set) var isConfigured = false
    /// Account currently applied to the RevenueCat customer (`FEAT-011` FR-006). Nil while no
    /// signed-in Account is linked, which is also what makes `linkAccount` idempotent.
    private(set) var linkedAccountID: String?

    private override init() {}

    func configureFromEnvironment() {
        let key = Bundle.main.object(forInfoDictionaryKey: "RevenueCatPublicSDKKey") as? String
        guard RemoteConfigService.isValidRevenueCatKey(key) else { return }
        Purchases.configure(withAPIKey: key!)
        Purchases.shared.delegate = self
        isConfigured = true
        refreshEntitlement()
    }

    /// Binds the RevenueCat customer to the signed-in Account so a purchase follows that Account
    /// across devices and re-entry instead of the anonymous app user id (`FEAT-011` FR-006).
    func linkAccount(_ accountID: String) async {
        guard isConfigured, !accountID.isEmpty, accountID != linkedAccountID else { return }
        do {
            let result = try await Purchases.shared.logIn(accountID)
            linkedAccountID = accountID
            lastSnapshot = snapshot(from: result.customerInfo)
        } catch {
            // A failed link must not leave a stale identity claiming to be current.
            linkedAccountID = nil
        }
    }

    /// Clears the provider context at sign-out/account switch so the next Account (or a guest)
    /// can never reuse the previous Account's entitlement (`FEAT-011` E4). Local state is dropped
    /// before the provider call so logout never depends on network success.
    func clearAccount() async {
        linkedAccountID = nil
        let previousProducts = lastSnapshot.products
        guard isConfigured else {
            lastSnapshot = PurchaseSnapshot(state: .unconfigured, products: previousProducts, errorCode: nil)
            return
        }
        lastSnapshot = PurchaseSnapshot(state: .loading, products: previousProducts, errorCode: nil)
        do {
            lastSnapshot = snapshot(from: try await Purchases.shared.logOut())
        } catch {
            // RevenueCat rejects `logOut` for an already-anonymous customer; the entitlement is
            // gone either way, so report the truthful "no confirmed premium" state.
            lastSnapshot = PurchaseSnapshot(state: .notEntitled, products: previousProducts, errorCode: nil)
        }
    }

    func refreshEntitlement() {
        guard isConfigured else { return }
        Purchases.shared.getCustomerInfo { [weak self] customerInfo, _ in
            Task { @MainActor in
                guard let self else { return }
                self.lastSnapshot = self.snapshot(from: customerInfo)
            }
        }
    }

    @Published private(set) var lastSnapshot = PurchaseSnapshot(state: .unconfigured, products: [], errorCode: nil)

    func loadOffering() async -> PurchaseSnapshot {
        guard isConfigured else {
            return failClosed(state: .unconfigured, errorCode: "sdk_not_configured")
        }
        guard let offering = await fetchDefaultOffering() else {
            return failClosed(state: .noOffering)
        }
        let customerInfo = await fetchCustomerInfo()
        return snapshot(from: customerInfo, offering: offering)
    }

    func purchase(productId: String) async -> PurchaseSnapshot {
        guard isConfigured else {
            return failClosed(state: .unconfigured, errorCode: "sdk_not_configured")
        }
        guard Self.productIDs.contains(productId) else {
            return failClosed(state: .purchaseFailed, errorCode: "invalid_product")
        }
        guard let offering = await fetchDefaultOffering(),
              let package = offering.availablePackages.first(where: { $0.storeProduct.productIdentifier == productId }) else {
            return failClosed(state: isConfigured ? .noOffering : .unconfigured)
        }
        return await withCheckedContinuation { continuation in
            Purchases.shared.purchase(package: package) { [weak self] _, customerInfo, error, userCancelled in
                Task { @MainActor in
                    guard let self else {
                        continuation.resume(returning: PurchaseSnapshot(state: .purchaseFailed, products: [], errorCode: "internal"))
                        return
                    }
                    if userCancelled {
                        self.log(outcome: "cancelled")
                        continuation.resume(returning: self.failClosed(state: .purchaseCancelled))
                        return
                    }
                    guard error == nil, let customerInfo else {
                        self.log(outcome: "error")
                        continuation.resume(returning: self.failClosed(state: .purchaseFailed, errorCode: "purchase_failed"))
                        return
                    }
                    continuation.resume(returning: self.snapshot(from: customerInfo, offering: offering))
                }
            }
        }
    }

    func restore() async -> PurchaseSnapshot {
        guard isConfigured else {
            return failClosed(state: .unconfigured)
        }
        return await withCheckedContinuation { continuation in
            Purchases.shared.restorePurchases { [weak self] customerInfo, error in
                Task { @MainActor in
                    guard let self, error == nil, let customerInfo else {
                        self?.log(outcome: "error")
                        continuation.resume(returning: self?.failClosed(state: .purchaseFailed, errorCode: "restore_failed")
                            ?? PurchaseSnapshot(state: .purchaseFailed, products: [], errorCode: "restore_failed"))
                        return
                    }
                    continuation.resume(returning: self.snapshot(from: customerInfo))
                }
            }
        }
    }

    private func fetchDefaultOffering() async -> Offering? {
        await withCheckedContinuation { continuation in
            Purchases.shared.getOfferings { offerings, _ in
                continuation.resume(returning: offerings?.offering(identifier: Self.offeringID))
            }
        }
    }

    private func fetchCustomerInfo() async -> CustomerInfo? {
        await withCheckedContinuation { continuation in
            Purchases.shared.getCustomerInfo { info, _ in continuation.resume(returning: info) }
        }
    }

    private func snapshot(from customerInfo: CustomerInfo?, offering: Offering? = nil) -> PurchaseSnapshot {
        let products = productList(from: offering)
        guard let entitlement = customerInfo?.entitlements[Self.entitlementID] else {
            let snap = PurchaseSnapshot(state: .notEntitled, products: products, errorCode: nil)
            lastSnapshot = snap
            log(outcome: "not_entitled")
            return snap
        }
        let state: PurchaseGatewayState
        if entitlement.billingIssueDetectedAt != nil {
            state = .billingRetry
        } else if entitlement.isActive {
            state = .entitled
        } else if let expirationDate = entitlement.expirationDate, expirationDate < Date() {
            state = .expired
        } else if entitlement.expirationDate == nil {
            state = .revoked
        } else {
            state = .notEntitled
        }
        log(outcome: state.rawValue.lowercased())
        let snap = PurchaseSnapshot(state: state, products: products, errorCode: nil)
        lastSnapshot = snap
        return snap
    }

    private func productList(from offering: Offering?) -> [PurchaseProduct] {
        guard let offering else { return [] }
        return offering.availablePackages
            .filter { Self.productIDs.contains($0.storeProduct.productIdentifier) }
            .map { package in
                PurchaseProduct(
                    identifier: package.storeProduct.productIdentifier,
                    localizedPrice: package.storeProduct.localizedPriceString,
                    period: Self.periodName(package.storeProduct.subscriptionPeriod?.unit)
                )
            }
    }

    private func failClosed(state: PurchaseGatewayState, errorCode: String? = nil) -> PurchaseSnapshot {
        log(outcome: state.rawValue.lowercased())
        let snap = PurchaseSnapshot(state: state, products: [], errorCode: errorCode)
        lastSnapshot = snap
        return snap
    }

    private static func periodName(_ unit: SubscriptionPeriod.Unit?) -> String? {
        guard let unit else { return nil }
        switch unit {
        case .day: return "day"
        case .week: return "week"
        case .month: return "month"
        case .year: return "year"
        @unknown default: return nil
        }
    }

    private func log(outcome: String) {
        Analytics.logEvent("purchase_state", parameters: ["source": "revenuecat", "outcome": outcome])
    }
}

extension RevenueCatAdapter: PurchaseGateway {
    var snapshot: PurchaseSnapshot { lastSnapshot }
}

extension RevenueCatAdapter: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            self.lastSnapshot = self.snapshot(from: customerInfo)
        }
    }
}
