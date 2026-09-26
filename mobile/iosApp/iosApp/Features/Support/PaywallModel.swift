import Foundation

/// Narrow seam over the native RevenueCat owner, so the paywall and its tests never touch
/// StoreKit/RevenueCat directly. Mirrors the KMP `PurchaseGateway` contract.
@MainActor
protocol PurchaseGateway: AnyObject {
    var snapshot: PurchaseSnapshot { get }
    func loadOffering() async -> PurchaseSnapshot
    func purchase(productId: String) async -> PurchaseSnapshot
    func restore() async -> PurchaseSnapshot
}

/// DEC-008 package mapping for the paywall. Product metadata (price, period) comes from StoreKit
/// through the gateway — only which package is the annual highlight is code-owned.
enum PaywallPlanCatalog {
    static let annualProductID = "premium_yearly"
    static let monthlyProductID = "premium_monthly"
    static let productIDs = [annualProductID, monthlyProductID]

    static func isAnnual(_ product: PurchaseProduct) -> Bool {
        product.identifier == annualProductID
            || product.identifier.contains("year")
            || product.identifier.contains("annual")
    }

    static func label(for product: PurchaseProduct) -> String {
        if isAnnual(product) { return "Annual" }
        if product.identifier.contains("month") { return "Monthly" }
        return product.identifier
            .replacingOccurrences(of: "premium_", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    static func periodLabel(for product: PurchaseProduct) -> String {
        product.period ?? (isAnnual(product) ? "year" : "month")
    }

    static func termsLine(for product: PurchaseProduct) -> String {
        isAnnual(product)
            ? "Billed today. Auto-renews yearly until you cancel."
            : "Billed today. Auto-renews monthly until you cancel."
    }

    static func summaryLine(for product: PurchaseProduct) -> String {
        let cadence = isAnnual(product) ? "yearly" : "monthly"
        return "\(product.localizedPrice) billed today. Auto-renews \(cadence) until you cancel."
    }

    /// Annual first (the highlighted package), then the comparison anchor; unknown ids are dropped
    /// so a misconfigured offering cannot render a product this build cannot purchase.
    static func ordered(_ products: [PurchaseProduct]) -> [PurchaseProduct] {
        products
            .filter { productIDs.contains($0.identifier) }
            .sorted { lhs, rhs in
                if isAnnual(lhs) != isAnnual(rhs) { return isAnnual(lhs) }
                let lhsIndex = productIDs.firstIndex(of: lhs.identifier) ?? productIDs.count
                let rhsIndex = productIDs.firstIndex(of: rhs.identifier) ?? productIDs.count
                return lhsIndex < rhsIndex
            }
    }
}

/// Paywall presentation state.
///
/// Two owners meet here: the real offering/purchase through `PurchaseGateway`, and FEAT-011
/// FR-001 — a purchase is account-bound, so a signed-out trigger asks for sign-in first instead
/// of starting an anonymous purchase.
@MainActor
final class PaywallModel: ObservableObject {
    enum Phase: Equatable {
        case signInRequired
        case loadingPlans
        case ready
        /// Retryable: the SDK is unconfigured or the offering is unavailable. Never fabricate plans.
        case unavailable(String)
        case processing
        case purchaseCancelled
        case purchaseFailed
        case entitled
    }

    @Published private(set) var phase: Phase = .loadingPlans
    @Published private(set) var plans: [PurchaseProduct] = []
    @Published private(set) var selectedProductID: String?
    @Published private(set) var isSignedIn = false
    @Published private(set) var isAuthenticating = false
    @Published private(set) var authError: String?

    private let gateway: any PurchaseGateway
    private let boundary: SessionBoundary
    private let signInAction: SignInAction
    private var hasStarted = false

    init(
        gateway: any PurchaseGateway = RevenueCatAdapter.shared,
        boundary: SessionBoundary = ServiceLocator.sessionBoundary,
        signInAction: SignInAction = SignInAction()
    ) {
        self.gateway = gateway
        self.boundary = boundary
        self.signInAction = signInAction
    }

    var selectedPlan: PurchaseProduct? {
        plans.first { $0.identifier == selectedProductID }
    }

    var isBusy: Bool { phase == .processing }

    var ctaTitle: String {
        if phase == .processing { return "Processing…" }
        guard let selectedPlan else { return "Plans unavailable" }
        return "Continue with \(PaywallPlanCatalog.label(for: selectedPlan))"
    }

    /// Banner copy for the states that must be truthful about what happened.
    var statusMessage: String? {
        switch phase {
        case .unavailable(let message): return message
        case .purchaseCancelled: return "Purchase cancelled. No access was granted."
        case .purchaseFailed: return "Purchase could not be completed. Try again."
        case .entitled: return "Premium access confirmed."
        default: return nil
        }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        Task { [weak self] in
            guard let self else { return }
            guard await self.boundary.hasStoredSession() else {
                self.phase = .signInRequired
                return
            }
            self.isSignedIn = true
            await self.loadPlans()
        }
    }

    /// FEAT-011 A0: a signed-out paid trigger enters the sign-in flow, then resumes here.
    func signIn() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        authError = nil
        defer { isAuthenticating = false }

        switch await signInAction.run() {
        case .succeeded:
            await adoptSignedInSession()
        case .cancelled:
            break
        case .failed(let text):
            authError = text
        }
    }

    /// Email sign-in seam (PLAN §4): the sheet signs in through `SessionBoundary`; when it reports
    /// success, the paywall re-checks the same boundary and lands in the same isSignedIn/loadPlans()
    /// outcome as the Google path. Call-site only — the phase machine is untouched.
    func resumeAfterEmailSignIn() async {
        await adoptSignedInSession()
    }

    private func adoptSignedInSession() async {
        isSignedIn = await boundary.hasStoredSession()
        if isSignedIn {
            await loadPlans()
        } else {
            phase = .signInRequired
        }
    }

    func loadPlans() async {
        phase = .loadingPlans
        apply(await gateway.loadOffering())
    }

    func retry() async {
        guard isSignedIn else {
            phase = .signInRequired
            return
        }
        await loadPlans()
    }

    func purchase() async {
        guard let selectedPlan, phase != .processing else { return }
        phase = .processing
        apply(await gateway.purchase(productId: selectedPlan.identifier))
    }

    func restore() async {
        guard phase != .processing else { return }
        phase = .processing
        apply(await gateway.restore())
    }

    func select(_ productID: String) {
        selectedProductID = productID
    }

    // MARK: - state mapping

    private func apply(_ snapshot: PurchaseSnapshot) {
        switch snapshot.state {
        case .unconfigured:
            plans = []
            phase = .unavailable("Premium is temporarily unavailable. Please try again later.")
        case .noOffering:
            plans = []
            phase = .unavailable("Plans are temporarily unavailable. Retry to check again.")
        case .loading, .purchasePending:
            phase = .processing
        case .purchaseCancelled:
            adoptPlans(from: snapshot)
            phase = .purchaseCancelled
        case .purchaseFailed:
            adoptPlans(from: snapshot)
            phase = .purchaseFailed
        case .entitled:
            adoptPlans(from: snapshot)
            phase = .entitled
        case .notEntitled, .billingRetry, .expired, .revoked:
            adoptPlans(from: snapshot)
            // An entitlement lapse (expired/revoked/billing retry) can still buy again, so the
            // plans stay actionable; an empty offering is an unavailable state, not an empty list.
            phase = plans.isEmpty
                ? .unavailable("Plans are temporarily unavailable. Retry to check again.")
                : .ready
        }
    }

    private func adoptPlans(from snapshot: PurchaseSnapshot) {
        plans = PaywallPlanCatalog.ordered(snapshot.products)
        if let selectedProductID, plans.contains(where: { $0.identifier == selectedProductID }) {
            return
        }
        selectedProductID = plans.first(where: PaywallPlanCatalog.isAnnual)?.identifier
            ?? plans.first?.identifier
    }
}
