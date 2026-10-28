import Foundation
import Combine

/// Narrow seam over the native RevenueCat owner, so the paywall and its tests never touch
/// StoreKit/RevenueCat directly. Mirrors the KMP `PurchaseGateway` contract.
@MainActor
protocol PurchaseGateway: AnyObject {
    var snapshot: PurchaseSnapshot { get }
    /// The gateway owns the entitlement. The paywall mirrors these pushes instead of keeping a
    /// private copy of access it may no longer be able to justify.
    var snapshots: AnyPublisher<PurchaseSnapshot, Never> { get }
    func loadOffering() async -> PurchaseSnapshot
    func purchase(packageID: String) async -> PurchaseSnapshot
    func restore() async -> PurchaseSnapshot
}

/// DEC-008 package mapping for the paywall. Which package is the annual highlight is code-owned;
/// price and period come from the offering through the gateway. Packages are identified by package
/// type, never by a store product id, so the ids can change in App Store Connect alone.
enum PaywallPlanCatalog {
    static func isAnnual(_ product: PurchaseProduct) -> Bool {
        product.packageType == .annual
    }

    static func label(for product: PurchaseProduct) -> String {
        switch product.packageType {
        case .annual: return "Annual"
        case .monthly: return "Monthly"
        case .other: return "Premium"
        }
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

    /// Annual first (the highlighted package), then the comparison anchor. Other package types are
    /// dropped so a misconfigured offering cannot render a plan this build does not sell.
    static func ordered(_ products: [PurchaseProduct]) -> [PurchaseProduct] {
        products
            .filter { $0.packageType != .other }
            .sorted { lhs, rhs in
                if lhs.packageType != rhs.packageType { return isAnnual(lhs) }
                return lhs.identifier < rhs.identifier
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
    /// Bumped on every session change so a result that crosses a sign-out or account switch is
    /// dropped instead of being painted into the paywall.
    private var sessionEpoch: UInt64 = 0
    private var snapshotCancellable: AnyCancellable?
    private var sessionEvents: Task<Void, Never>?
    /// True only while this model's own purchase/restore is running: that operation owns the busy
    /// phase, and nothing else may park the sheet there.
    private var isRunningOperation = false

    init(
        gateway: any PurchaseGateway = RevenueCatAdapter.shared,
        boundary: SessionBoundary = ServiceLocator.sessionBoundary,
        signInAction: SignInAction = SignInAction()
    ) {
        self.gateway = gateway
        self.boundary = boundary
        self.signInAction = signInAction
        observeGateway()
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
        observeSession()
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
        let epoch = sessionEpoch
        phase = .loadingPlans
        let snapshot = await gateway.loadOffering()
        guard epoch == sessionEpoch else { return }
        guard await boundary.hasStoredSession() else {
            invalidateAccountState()
            return
        }
        // An offering fetch that resolved to a transient provider state crossed an identity
        // transition: it holds no plans, so it must not overwrite the phase the gateway's own pushes
        // establish (and it must never own the busy phase).
        guard snapshot.state != .loading, snapshot.state != .purchasePending else { return }
        apply(snapshot)
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
        let epoch = sessionEpoch
        isRunningOperation = true
        phase = .processing
        let snapshot = await gateway.purchase(packageID: selectedPlan.identifier)
        isRunningOperation = false
        guard epoch == sessionEpoch else { return }
        guard await boundary.hasStoredSession() else {
            invalidateAccountState()
            return
        }
        apply(snapshot, fromOperation: true)
    }

    func restore() async {
        guard phase != .processing else { return }
        let epoch = sessionEpoch
        isRunningOperation = true
        phase = .processing
        let snapshot = await gateway.restore()
        isRunningOperation = false
        guard epoch == sessionEpoch else { return }
        guard await boundary.hasStoredSession() else {
            invalidateAccountState()
            return
        }
        apply(snapshot, fromOperation: true)
    }

    func select(_ productID: String) {
        selectedProductID = productID
    }

    // MARK: - ownership of account-dependent state

    private func observeGateway() {
        snapshotCancellable = gateway.snapshots.sink { [weak self] snapshot in
            guard let self else { return }
            Task { await self.reconcile(with: snapshot) }
        }
    }

    /// Sign-out and unauthorized clears invalidate the paywall's account-dependent state, including
    /// while a sheet is already open.
    private func observeSession() {
        guard sessionEvents == nil else { return }
        sessionEvents = Task { [weak self, boundary] in
            for await event in await boundary.events() {
                guard let self else { return }
                await self.handleSessionEvent(event)
            }
        }
    }

    private func handleSessionEvent(_ event: SessionEvent) async {
        switch event {
        case .signedOut, .signInRequired:
            invalidateAccountState()
        case .signedIn:
            break
        }
    }

    /// The gateway can grant or drop entitlement outside a tap here (a delegate push, a purchase
    /// from another surface, a sign-out that clears the provider). Mirror it, and never keep access
    /// the current identity cannot justify.
    private func reconcile(with snapshot: PurchaseSnapshot) async {
        let epoch = sessionEpoch
        let signedIn = await boundary.hasStoredSession()
        guard epoch == sessionEpoch else { return }
        isSignedIn = signedIn
        guard signedIn else {
            // Clear the session before reading it, so a stale "entitled" snapshot cannot survive a
            // sign-out that simply arrived after it.
            invalidateAccountState()
            return
        }
        switch snapshot.state {
        case .entitled:
            adoptPlans(from: snapshot)
            phase = .entitled
        case .signInRequired:
            invalidateAccountState()
        case .loading, .purchasePending:
            // A transient provider state is not an outcome: a settled snapshot always decides the
            // phase, so a transition in the gateway can never park the sheet in a busy state.
            break
        default:
            apply(snapshot)
        }
    }

    private func invalidateAccountState() {
        sessionEpoch &+= 1
        isRunningOperation = false
        isSignedIn = false
        plans = []
        selectedProductID = nil
        authError = nil
        isAuthenticating = false
        phase = .signInRequired
    }

    // MARK: - state mapping

    private func apply(_ snapshot: PurchaseSnapshot, fromOperation: Bool = false) {
        // Only this model's own operation may keep the sheet busy, and only its own result (or an
        // entitlement that already landed) may replace that phase. Any other settled snapshot takes
        // over, so a stale busy phase cannot block purchase and restore forever.
        if isRunningOperation && !fromOperation && snapshot.state != .entitled { return }
        switch snapshot.state {
        case .unconfigured:
            plans = []
            phase = .unavailable("Premium is temporarily unavailable. Please try again later.")
        case .noOffering:
            plans = []
            phase = .unavailable("Plans are temporarily unavailable. Retry to check again.")
        case .loading, .purchasePending:
            phase = fromOperation ? .processing : .loadingPlans
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
        case .signInRequired:
            // M2: the adapter refused a store call because no Account is linked. Show sign-in
            // instead of a plan list that cannot be bought.
            plans = []
            phase = .signInRequired
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
