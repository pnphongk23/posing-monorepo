import Foundation
import RevenueCat
import FirebaseAnalytics

/// Native RevenueCat owner for StoreKit, configured only from an injected public key.
/// Compose receives sanitized snapshots through the common purchase contract seam.
final class RevenueCatAdapter: NSObject {
    static let shared = RevenueCatAdapter()
    static let entitlementID = "premium"
    static let offeringID = "default"
    static let productIDs = ["premium_annual", "premium_monthly"]

    private(set) var isConfigured = false
    private var requestObserver: NSObjectProtocol?

    private override init() {}

    func configureFromEnvironment() {
        installRequestObserver()
        guard let key = Bundle.main.object(forInfoDictionaryKey: "RevenueCatPublicSDKKey") as? String,
              !key.isEmpty,
              !key.contains("$("),
              !key.lowercased().contains("placeholder"),
              !key.lowercased().contains("example") else {
            return
        }
        Purchases.configure(withAPIKey: key)
        Purchases.shared.delegate = self
        isConfigured = true
        refreshEntitlement()
    }

    private func installRequestObserver() {
        guard requestObserver == nil else { return }
        requestObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("com.aipose.revenuecat.request"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handle(notification: notification)
        }
    }

    private func handle(notification: Notification) {
        guard let info = notification.userInfo,
              let action = info["action"] as? String,
              let requestId = info["requestId"] as? String else { return }
        switch action {
        case "load_offering":
            post(state: "LOADING")
            loadDefaultOffering { [weak self] offering in
                guard let self else { return }
                guard let offering else {
                self.post(state: self.isConfigured ? "NO_OFFERING" : "UNCONFIGURED", requestId: requestId)
                    return
                }
                Purchases.shared.getCustomerInfo { [weak self] customerInfo, _ in
                    self?.publish(customerInfo: customerInfo, requestId: requestId, offering: offering)
                }
            }
        case "purchase":
            guard let productId = info["productId"] as? String else {
                post(state: "PURCHASE_FAILED", requestId: requestId, errorCode: "invalid_product")
                return
            }
            guard Self.productIDs.contains(productId) else {
                post(state: "PURCHASE_FAILED", requestId: requestId, errorCode: "invalid_product")
                return
            }
            post(state: "PURCHASE_PENDING")
            loadDefaultOffering { [weak self] offering in
                guard let self, let package = offering?.availablePackages.first(where: {
                    $0.storeProduct.productIdentifier == productId
                }) else {
                    self?.post(state: self?.isConfigured == true ? "NO_OFFERING" : "UNCONFIGURED", requestId: requestId)
                    return
                }
                self.purchase(package: package, requestId: requestId)
            }
        case "restore":
            post(state: "LOADING")
            restore(requestId: requestId)
        default:
            post(state: "PURCHASE_FAILED", requestId: requestId, errorCode: "unsupported_action")
        }
    }

    func refreshEntitlement() {
        guard isConfigured else { return }
        Purchases.shared.getCustomerInfo { [weak self] customerInfo, _ in
            self?.publish(customerInfo: customerInfo)
        }
    }

    func loadDefaultOffering(completion: @escaping (Offering?) -> Void) {
        guard isConfigured else { completion(nil); return }
        Purchases.shared.getOfferings { offerings, _ in
            completion(offerings?.offering(identifier: Self.offeringID))
        }
    }

    private func purchase(package: Package, requestId: String) {
        guard isConfigured else {
            log(outcome: "unconfigured")
            post(state: "UNCONFIGURED", requestId: requestId, errorCode: "sdk_not_configured")
            return
        }
        Purchases.shared.purchase(package: package) { [weak self] _, customerInfo, error, userCancelled in
            guard let self else { return }
            if userCancelled {
                self.log(outcome: "cancelled")
                self.post(state: "PURCHASE_CANCELLED", requestId: requestId)
                return
            }
            guard error == nil, let customerInfo else {
                self.log(outcome: "error")
                self.post(state: "PURCHASE_FAILED", requestId: requestId, errorCode: "purchase_failed")
                return
            }
            self.publish(customerInfo: customerInfo, requestId: requestId)
        }
    }

    private func restore(requestId: String) {
        guard isConfigured else { post(state: "UNCONFIGURED", requestId: requestId); return }
        Purchases.shared.restorePurchases { [weak self] customerInfo, error in
            guard let self, error == nil, let customerInfo else {
                self?.log(outcome: "error")
                self?.post(state: "PURCHASE_FAILED", requestId: requestId, errorCode: "restore_failed")
                return
            }
            self.publish(customerInfo: customerInfo, requestId: requestId)
        }
    }

    private func publish(customerInfo: CustomerInfo?, requestId: String? = nil, offering: Offering? = nil) {
        guard let entitlement = customerInfo?.entitlements[Self.entitlementID] else {
            post(state: "NOT_ENTITLED", requestId: requestId, offering: offering)
            return
        }
        let state: String
        if entitlement.billingIssueDetectedAt != nil {
            // RevenueCat exposes the billing issue, but this adapter does not
            // receive a provider-specific grace-period boundary. Keep access
            // conservative until CustomerInfo itself confirms active access.
            state = "BILLING_RETRY"
        } else if entitlement.isActive {
            state = "ENTITLED"
        } else if let expirationDate = entitlement.expirationDate, expirationDate < Date() {
            state = "EXPIRED"
        } else if entitlement.expirationDate == nil {
            state = "REVOKED"
        } else {
            state = "NOT_ENTITLED"
        }
        log(outcome: state.lowercased())
        post(state: state, requestId: requestId, offering: offering)
    }

    private func post(state: String, requestId: String? = nil, offering: Offering? = nil, errorCode: String? = nil) {
        var info: [AnyHashable: Any] = ["state": state]
        if let requestId { info["requestId"] = requestId }
        if let errorCode { info["errorCode"] = errorCode }
        if let offering {
            // Bridge contract: products is an NSArray of NSDictionary values;
            // required fields are strings and the optional period is omitted.
            // This keeps localized StoreKit metadata intact without passing SDK
            // objects, receipts, tokens, or prices from a non-localized source.
            let products: [[String: String]] = offering.availablePackages
                .filter { Self.productIDs.contains($0.storeProduct.productIdentifier) }
                .compactMap { package in
                var product: [String: String] = [
                    "identifier": package.storeProduct.productIdentifier,
                    "localizedPrice": package.storeProduct.localizedPriceString,
                ]
                if let period = Self.periodName(package.storeProduct.subscriptionPeriod?.unit) {
                    product["period"] = period
                }
                return product
            }
            info["products"] = products
        }
        NotificationCenter.default.post(name: Notification.Name("com.aipose.revenuecat.response"), object: nil, userInfo: info)
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
        // Only fixed routing/outcome metadata is emitted. SDK errors, receipts,
        // customer identifiers, tokens, and prices are intentionally excluded.
        Analytics.logEvent("purchase_state", parameters: ["source": "revenuecat", "outcome": outcome])
    }
}

extension RevenueCatAdapter: PurchasesDelegate {
    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        publish(customerInfo: customerInfo)
    }
}
