import Combine
import Foundation

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
        case .annual: return "Yearly"
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

/// Money read out of a store-localized price string (`PurchaseProduct.localizedPrice`).
///
/// The board's plan copy ("$3.33 per month, billed $39.99 yearly", "Save 44%") is derived from the
/// real RevenueCat packages, never typed in. `localizedPrice` is a *formatted string* in the store's
/// price locale, not a number, so the digits, the decimal separator and the currency symbol are
/// read back out of it; anything that does not parse yields no derived copy instead of a wrong one.
enum PaywallMoney {
    /// How one localized price string is laid out: `$39.99` and `39,99 €` are the same amount with a
    /// different symbol, separator and side.
    struct Style: Equatable {
        let prefix: String
        let suffix: String
        let decimalSeparator: Character?
        let groupingSeparator: Character?
        let groupingSize: Int
        let fractionDigits: Int
    }

    /// Digits, the separators that group or split them, and the currency marks around them.
    private struct Scan {
        let prefix: String
        let suffix: String
        /// Digit runs in order, split at every separator: `999.000` → ["999", "000"].
        let segments: [String]
        /// Separator characters that sat between the first and the last digit.
        let separators: [Character]

        var digits: String { segments.joined() }
        var trailingDigits: Int { segments.last?.count ?? 0 }
    }

    private static let separators: Set<Character> = [".", ",", "'", " ", "\u{00A0}", "\u{202F}", "\u{066B}", "\u{066C}"]

    private static func scan(_ localizedPrice: String) -> Scan? {
        let characters = Array(localizedPrice)
        guard let first = characters.firstIndex(where: \.isNumber),
              let last = characters.lastIndex(where: \.isNumber) else { return nil }
        let prefix = String(characters[..<first])
        let suffix = String(characters[(last + 1)...])
        var segments: [String] = []
        var separatorsSeen: [Character] = []
        var current = ""
        for character in characters[first...last] {
            if character.isNumber {
                current.append(character)
            } else if PaywallMoney.separators.contains(character) {
                segments.append(current)
                current = ""
                separatorsSeen.append(character)
            }
        }
        segments.append(current)
        return Scan(prefix: prefix, suffix: suffix, segments: segments, separators: separatorsSeen)
    }

    /// The last separator is the decimal mark only when one or two digits follow it: `39.99` is
    /// thirty-nine ninety-nine, `1,234` is one thousand two hundred thirty-four.
    static func style(of localizedPrice: String) -> Style? {
        guard let scan = scan(localizedPrice), !scan.digits.isEmpty else { return nil }
        let usesDecimalSeparator = (1...2).contains(scan.trailingDigits) && !scan.separators.isEmpty
        let decimalSeparator = usesDecimalSeparator ? scan.separators.last : nil
        let groupingSeparator = scan.separators.first { $0 != decimalSeparator }
        return Style(
            prefix: scan.prefix,
            suffix: scan.suffix,
            decimalSeparator: decimalSeparator,
            groupingSeparator: groupingSeparator,
            groupingSize: groupingSize(in: scan, decimalSeparator: decimalSeparator),
            fractionDigits: usesDecimalSeparator ? scan.trailingDigits : 0
        )
    }

    /// Digit count of the last group before the decimal mark (`999.000` → 3, `1.234,56` → 3), so
    /// re-formatting keeps the store's own grouping.
    private static func groupingSize(in scan: Scan, decimalSeparator: Character?) -> Int {
        guard let last = scan.segments.last else { return 3 }
        guard decimalSeparator != nil, scan.segments.count >= 2 else { return last.count }
        return scan.segments[scan.segments.count - 2].count
    }

    static func amount(from localizedPrice: String) -> Decimal? {
        guard let scan = scan(localizedPrice), !scan.digits.isEmpty else { return nil }
        let style = style(of: localizedPrice)
        var normalized = scan.digits
        if let fractionDigits = style?.fractionDigits, fractionDigits > 0, normalized.count > fractionDigits {
            let split = normalized.index(normalized.endIndex, offsetBy: -fractionDigits)
            normalized = String(normalized[..<split]) + "." + String(normalized[split...])
        }
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Formats `value` the way the store formatted `sample`, so a derived per-month figure keeps the
    /// price's symbol, separator and fraction digits.
    static func formatted(_ value: Decimal, like sample: String) -> String? {
        guard let style = style(of: sample) else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = style.fractionDigits
        formatter.maximumFractionDigits = style.fractionDigits
        if let decimalSeparator = style.decimalSeparator { formatter.decimalSeparator = String(decimalSeparator) }
        if let groupingSeparator = style.groupingSeparator {
            formatter.usesGroupingSeparator = true
            formatter.groupingSeparator = String(groupingSeparator)
            formatter.groupingSize = style.groupingSize
            formatter.secondaryGroupingSize = style.groupingSize
        } else {
            formatter.usesGroupingSeparator = false
        }
        guard let number = formatter.string(from: NSDecimalNumber(decimal: value)) else { return nil }
        return style.prefix + number + style.suffix
    }

    /// The annual package's price expressed per month, in the price's own format.
    static func perMonth(annualTotal: Decimal, like sample: String) -> String? {
        guard annualTotal > 0 else { return nil }
        return formatted(annualTotal / 12, like: sample)
    }

    /// Whole-percent saving of the annual package over twelve monthly payments, rounded to the
    /// nearest percent. `nil` when the offering cannot support the claim (a monthly package that is
    /// not actually dearer, unparsable prices), because the badge is a promise about the price.
    static func savingsPercent(annualTotal: Decimal, monthlyTotal: Decimal) -> Int? {
        guard annualTotal > 0, monthlyTotal > 0 else { return nil }
        let yearlyAtMonthlyRate = monthlyTotal * 12
        guard yearlyAtMonthlyRate > annualTotal else { return nil }
        let saved = (yearlyAtMonthlyRate - annualTotal) / yearlyAtMonthlyRate
        let percent = NSDecimalNumber(decimal: saved).doubleValue * 100
        let rounded = Int(percent.rounded())
        return (1...95).contains(rounded) ? rounded : nil
    }
}

/// The plan-card copy the boards ask for, derived from the loaded offering.
///
/// Premium unlocks one thing — capturing with the full pose camera (owner decision B5) — so the
/// benefit line and every plan detail stay inside that claim. Prices, the per-month breakdown and
/// the saving badge all come from the store packages; when they cannot be derived the copy degrades
/// to a billing statement rather than inventing a number.
enum PaywallPlanCopy {
    static let benefit = "Capture with the full pose camera"
    static let autoRenewCaption = "Renews automatically until you cancel in Apple ID settings."
    static let monthlyDetail = "Billed monthly"

    /// The two headline fragments, in draw order. The mockup gives the second one its own line in
    /// the accent ink, which is also what keeps a one-word orphan off the first line at 375 pt.
    static let headlineLines = ["Pick a pose.", "Match it. Shoot."]
    /// The approved CTA copy, from `mockups/variant-c-v2.png`. (A short-lived backlog note suggested
    /// "Unlock the shutter" because only the shutter is gated; the owner kept the mockup's wording, and
    /// step 3 says "Premium unlocks the shutter with the full pose camera", so the claim stays exact.)
    static let purchaseCTA = "Unlock the pose camera"

    /// One "free / free / paid" step of the how-it-works block. The order is the funnel order and
    /// the copy is verbatim from the CRO handoff (`handoff-1.2.md` §3), including which step is paid.
    struct Step: Equatable, Identifiable {
        let id: Int
        let title: String
        let detail: String
        let isPremium: Bool
    }

    static let steps: [Step] = [
        Step(id: 1, title: "Pick a pose", detail: "Browse and save poses for free.", isPremium: false),
        Step(id: 2, title: "Match the outline", detail: "The guide shows on your live camera.", isPremium: false),
        Step(id: 3, title: "Shoot", detail: "Premium unlocks the shutter with the full pose camera.", isPremium: true),
    ]

    static func savingsBadge(annual: PurchaseProduct, monthly: PurchaseProduct?) -> String? {
        guard let monthly,
              let annualTotal = PaywallMoney.amount(from: annual.localizedPrice),
              let monthlyTotal = PaywallMoney.amount(from: monthly.localizedPrice),
              let percent = PaywallMoney.savingsPercent(annualTotal: annualTotal, monthlyTotal: monthlyTotal)
        else { return nil }
        return "Save \(percent)%"
    }

    /// "$3.33 per month, billed $39.99 yearly" — both figures read out of the annual package.
    static func annualDetail(for product: PurchaseProduct) -> String {
        let cadence = PaywallPlanCatalog.periodLabel(for: product) + "ly"
        guard let total = PaywallMoney.amount(from: product.localizedPrice),
              let perMonth = PaywallMoney.perMonth(annualTotal: total, like: product.localizedPrice)
        else { return "Billed \(cadence)" }
        return "\(perMonth) per month, billed \(product.localizedPrice) \(cadence)"
    }

    static func detail(for product: PurchaseProduct) -> String {
        PaywallPlanCatalog.isAnnual(product)
            ? annualDetail(for: product)
            : monthlyDetail
    }

    /// One plan card's rendered copy, computed once so the view and the tests read the same strings.
    struct Plan: Equatable, Identifiable {
        let id: String
        let title: String
        let badge: String?
        let detail: String
        let price: String
        let isSelected: Bool
        /// The package type, so the card's accessibility id follows the plan and not its label.
        let isAnnual: Bool
        let accessibilityLabel: String
    }

    static func plan(_ product: PurchaseProduct, monthly: PurchaseProduct?, isSelected: Bool) -> Plan {
        let title = PaywallPlanCatalog.label(for: product)
        let isAnnual = PaywallPlanCatalog.isAnnual(product)
        let badge = isAnnual ? savingsBadge(annual: product, monthly: monthly) : nil
        let detail = detail(for: product)
        let price = product.localizedPrice
        let selection = isSelected ? "selected" : "not selected"
        let badgePart = badge.map { ", \($0)" } ?? ""
        return Plan(
            id: product.identifier,
            title: title,
            badge: badge,
            detail: detail,
            price: price,
            isSelected: isSelected,
            isAnnual: isAnnual,
            accessibilityLabel: "\(title) plan, \(selection)\(badgePart). \(detail). \(PaywallPlanCatalog.summaryLine(for: product))"
        )
    }

    /// The plan rows shown before the offering can be read (signed out, offline, loading): the two
    /// packages this build sells, with the price honestly marked as not available yet.
    static func placeholderPlans(detail: String) -> [Plan] {
        [
            Plan(id: "placeholder.annual", title: "Yearly", badge: nil, detail: detail,
                 price: "—", isSelected: true, isAnnual: true,
                 accessibilityLabel: "Yearly plan, \(detail)"),
            Plan(id: "placeholder.monthly", title: "Monthly", badge: nil, detail: detail,
                 price: "—", isSelected: false, isAnnual: false,
                 accessibilityLabel: "Monthly plan, \(detail)"),
        ]
    }

    static let offlinePlaceholders = placeholderPlans(detail: "Price unavailable offline")
    /// The prices are read before sign-in, so "shown after you sign in" is no longer true: when the
    /// offering cannot be read the card says exactly that and nothing about the account step.
    static let priceUnavailablePlaceholders = placeholderPlans(detail: "Price unavailable")
}

/// Paywall presentation state.
///
/// Two owners meet here: the real offering/purchase through `PurchaseGateway`, and FEAT-011
/// FR-001 — a purchase is account-bound, so a signed-out trigger asks for sign-in first instead
/// of starting an anonymous purchase.
@MainActor
final class PaywallModel: ObservableObject, SessionScoped {
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
    /// Which provider the last attempt used, so a failure can name it (board 11-15).
    @Published private(set) var authProvider: PaywallSignInOption?
    /// The store failure kind behind the last settled snapshot: the error card's copy is chosen from
    /// the real failure, never from a generic string.
    @Published private(set) var failure: PurchaseFailure?
    /// Which operation produced the last settled snapshot. A failed purchase asks for "Try again"
    /// on the primary CTA; a failed restore keeps "Subscribe" and retries inline (boards 11-08/09).
    @Published private(set) var lastOperation: Operation?
    /// Live connectivity. Board 11-11's offline state is the network path, not a parsed error.
    @Published private(set) var isOffline: Bool

    enum Operation: Equatable {
        case purchase
        case restore
    }

    private let gateway: any PurchaseGateway
    private let boundary: SessionBoundary
    private let signInAction: SignInAction
    /// The Apple handoff is the same `AppleSignInAction` the Account sheet's `AppleSignInModel`
    /// wraps — one provider seam, one API call, one error-copy mapping. The paywall adds no second
    /// Apple implementation; it only decides what a resolved attempt means for its phase.
    private let appleSignInAction: AppleSignInAction
    private let connectivity: ConnectivityReporting
    private let analytics: PaywallAnalyticsSink
    private let scope: SessionScope
    private var hasStarted = false
    /// One presentation, one `paywall_view`: a re-entrant `start()` cannot double-count the funnel.
    private var hasEmittedView = false
    private var hasNotedDismissal = false
    /// True while this presentation shows store prices without an Account. The offering is a store
    /// fact, not account state, so a signed-out provider push must not blank the price cards.
    private var showsPreSignInPrices = false
    /// Where this presentation came from. Owned by the model so every event carries it instead of
    /// each call site inventing one; the two triggers are `.shutter` and `.settings`.
    var trigger: PaywallTrigger = .shutter
    private var connectivityCancellable: AnyCancellable?
    /// Bumped on every session change so a result that crosses a sign-out or account switch is
    /// dropped instead of being painted into the paywall.
    ///
    /// This is not the session subscription: it also guards gateway pushes (a delegate update, a
    /// purchase from another surface), which no session event announces, so it stays local to the model.
    private var sessionEpoch: UInt64 = 0
    private var snapshotCancellable: AnyCancellable?
    /// The operation that currently owns the busy phase. A token, not a flag, so a superseded
    /// purchase resolving during a newer restore cannot release the restore's claim.
    private var activeOperation: UInt64?
    private var operationCounter: UInt64 = 0

    init(
        gateway: any PurchaseGateway = RevenueCatAdapter.shared,
        boundary: SessionBoundary = ServiceLocator.sessionBoundary,
        signInAction: SignInAction = SignInAction(),
        appleSignInAction: AppleSignInAction = AppleSignInAction(),
        connectivity: ConnectivityReporting = NetworkConnectivityMonitor.shared,
        analytics: @escaping PaywallAnalyticsSink = PaywallAnalytics.production
    ) {
        self.gateway = gateway
        self.boundary = boundary
        self.signInAction = signInAction
        self.appleSignInAction = appleSignInAction
        self.connectivity = connectivity
        self.analytics = analytics
        self.isOffline = connectivity.isOffline
        self.scope = SessionScope.of(boundary)
        observeGateway()
        observeConnectivity()
    }

    var selectedPlan: PurchaseProduct? {
        plans.first { $0.identifier == selectedProductID }
    }

    var isBusy: Bool { phase == .processing }

    /// Board 11-01: one primary action per state, labelled with what the tap does. The unbuyable
    /// build keeps its existing "Plans unavailable" wording: the CTA is disabled there and the
    /// error card beside it carries the retry.
    var ctaTitle: String {
        switch phase {
        case .signInRequired: return "Sign in to subscribe"
        case .purchaseFailed where lastOperation == .purchase: return "Try again"
        case .unavailable: return "Plans unavailable"
        default: return PaywallPlanCopy.purchaseCTA
        }
    }

    /// The line above the CTA (handoff §6): what today's charge would be for the selected plan, read
    /// out of the store package. Nil until a real plan is loaded, so no price is ever invented and
    /// the line follows the selection instead of being a rendered constant.
    var purchaseSummary: String? {
        guard let plan = selectedPlan else { return nil }
        return "\(PaywallPlanCatalog.label(for: plan)) plan · \(plan.localizedPrice) billed today"
    }

    /// The CTA is always on screen — a state without a usable action still shows the action that is
    /// coming — and is disabled rather than hidden (boards 11-10/11-11).
    var isCTAEnabled: Bool {
        guard !isBusy, !isOffline else { return false }
        switch phase {
        case .signInRequired: return !isAuthenticating
        case .ready, .purchaseCancelled, .entitled, .purchaseFailed: return selectedPlan != nil
        case .loadingPlans, .processing, .unavailable: return false
        }
    }

    /// One line of helper copy above a disabled CTA that says why it cannot be tapped yet.
    var ctaHelper: String? {
        if isOffline { return "Connect to the internet to subscribe." }
        switch phase {
        case .signInRequired: return PaywallModel.signedOutLine
        case .loadingPlans: return "Subscribe turns on when plans load."
        default: return nil
        }
    }

    /// Truthful identity line above the CTA. The account payload carries no email address, so the
    /// paywall never prints one: it states what is actually true, that Premium follows the account.
    static let signedInLine = "Signed in. Premium follows your account."
    static let signedOutLine = "Sign in first so Premium follows you."

    /// The plan cards the body renders for the current offering (empty until one is loaded).
    var planPresentations: [PaywallPlanCopy.Plan] {
        let monthly = plans.first { $0.packageType == .monthly }
        return plans.map { product in
            PaywallPlanCopy.plan(
                product,
                monthly: monthly,
                isSelected: product.identifier == selectedProductID
            )
        }
    }

    /// The plan rows shown when no offering can be read: signed out, offline, or still loading.
    var placeholderPlans: [PaywallPlanCopy.Plan] {
        guard plans.isEmpty else { return [] }
        if isOffline { return PaywallPlanCopy.offlinePlaceholders }
        if !isSignedIn { return PaywallPlanCopy.priceUnavailablePlaceholders }
        return []
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

    /// The board's error card (11-08/11-09): a titled message with the action that fixes it.
    var notice: SupportNotice? {
        switch phase {
        case .unavailable(let message):
            return SupportNotice(title: "Couldn't load plans", message: message, action: .retryLoad)
        case .purchaseFailed:
            if lastOperation == .restore {
                return SupportNotice(
                    title: "Couldn't restore purchases",
                    message: restoreFailureMessage,
                    action: .retryRestore
                )
            }
            return SupportNotice(
                title: "The purchase didn't go through",
                message: purchaseFailureMessage,
                action: .retryPurchase
            )
        case .signInRequired:
            guard let authError else { return nil }
            return SupportNotice(
                title: authFailureTitle,
                message: authError,
                action: authProvider == .google ? .retryGoogle : nil
            )
        case .loadingPlans, .ready, .processing, .purchaseCancelled, .entitled:
            return nil
        }
    }

    /// True when the card in the offer area *is* the settled outcome — a purchase that failed — so
    /// the surface states it through the outcome banner QA reads (`paywall.status`) rather than
    /// through the offer-area notice id. A failed restore and an unavailable offering stay notices:
    /// their copy is about the offering, not about a purchase that did not complete.
    var noticeIsSettledOutcome: Bool {
        phase == .purchaseFailed && lastOperation == .purchase
    }

    private var purchaseFailureMessage: String {
        switch failure {
        case .network:
            return "Check your connection and try again."
        case .receiptOwnedByOtherAccount:
            return "This purchase belongs to another account. Restore purchases to use it here."
        case .storeProblem:
            return "The App Store didn't finish it. Try again in a moment."
        case .cancelled, .other, .none:
            return "The App Store didn't finish it. If you were charged, tap Restore purchases."
        }
    }

    private var restoreFailureMessage: String {
        switch failure {
        case .network:
            return "Check your connection and try again."
        default:
            return "The App Store didn't respond. Check your connection and try again."
        }
    }

    private var authFailureTitle: String {
        switch authProvider {
        case .apple: return "Couldn't sign in with Apple"
        case .google: return "Couldn't sign in with Google"
        case .email, .none: return "Couldn't sign in"
        }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        connectivity.start()
        isOffline = connectivity.isOffline
        // The paywall ignores session events before `start()`, so adoption happens here rather than in
        // `init`; the scope owns the subscription from now on.
        scope.adopt(self)
        Task { [weak self] in
            guard let self else { return }
            guard await self.boundary.hasStoredSession() else {
                self.phase = .signInRequired
                self.showsPreSignInPrices = true
                self.emitView()
                // Prices before sign-in (owner decision, 1.1 (20)): the offering is read without an
                // Account and only the packages are adopted, so the cards show the store's real
                // price and saving before the account step.
                await self.loadSignedOutPrices()
                return
            }
            self.showsPreSignInPrices = false
            self.isSignedIn = true
            await self.loadPlans()
            self.emitView()
        }
    }

    /// FEAT-011 A0: a signed-out paid trigger enters the sign-in flow, then resumes here.
    func signIn() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        authError = nil
        authProvider = .google
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

    /// Sign in with Apple from the paywall (App Review 4.8): a third-party sign-in is offered, so
    /// Apple's must be offered beside it and land in the same outcome. Success resumes exactly like
    /// the Google path (`adoptSignedInSession` → `loadPlans`); a dismissed Apple sheet is a no-op
    /// with no banner, because the user chose to cancel rather than failed to sign in.
    func signInWithApple() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        authError = nil
        authProvider = .apple
        defer { isAuthenticating = false }

        switch await appleSignInAction.run() {
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
            showsPreSignInPrices = false
            await loadPlans()
        } else {
            phase = .signInRequired
        }
    }

    func loadPlans() async {
        await loadOffering(keepingPhase: false)
    }

    /// Signed out, the offering is read for display only. The phase stays `.signInRequired` because a
    /// purchase is Account-bound (`RevenueCatAdapter.purchase` refuses a guest) and no guest state may
    /// ever look purchasable; adopting the packages cannot grant anything, it only un-blanks the
    /// prices.
    private func loadSignedOutPrices() async {
        await loadOffering(keepingPhase: true)
    }

    private func loadOffering(keepingPhase: Bool) async {
        let epoch = sessionEpoch
        if !keepingPhase { phase = .loadingPlans }
        let snapshot = await gateway.loadOffering()
        if keepingPhase {
            // The prices are account-agnostic, so a session event does not invalidate them; a
            // sign-in that landed while they loaded owns the state from here on.
            guard !isSignedIn else { return }
            adoptPreviewPlans(from: snapshot)
            return
        }
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

    /// Packages only: a signed-out snapshot is `.notEntitled` (a guest is granted nothing), so its
    /// state must not decide the phase here.
    private func adoptPreviewPlans(from snapshot: PurchaseSnapshot) {
        let products = PaywallPlanCatalog.ordered(snapshot.products)
        guard !products.isEmpty else { return }
        plans = products
        if let selectedProductID, products.contains(where: { $0.identifier == selectedProductID }) {
            return
        }
        selectedProductID = products.first(where: PaywallPlanCatalog.isAnnual)?.identifier
            ?? products.first?.identifier
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
        let operation = beginOperation()
        lastOperation = .purchase
        failure = nil
        phase = .processing
        let snapshot = await gateway.purchase(packageID: selectedPlan.identifier)
        endOperation(operation)
        guard epoch == sessionEpoch else { return }
        guard await boundary.hasStoredSession() else {
            invalidateAccountState()
            return
        }
        apply(snapshot, fromOperation: operation)
    }

    func restore() async {
        guard phase != .processing else { return }
        emit(PaywallEvent.restoreTap, accountParameters)
        let epoch = sessionEpoch
        let operation = beginOperation()
        lastOperation = .restore
        failure = nil
        phase = .processing
        let snapshot = await gateway.restore()
        endOperation(operation)
        guard epoch == sessionEpoch else { return }
        guard await boundary.hasStoredSession() else {
            invalidateAccountState()
            return
        }
        apply(snapshot, fromOperation: operation)
    }

    func select(_ productID: String) {
        selectedProductID = productID
        guard plans.contains(where: { $0.identifier == productID }) else { return }
        emit(PaywallEvent.planSelect, accountParameters.merging(["plan": planKey]) { _, new in new })
    }

    // MARK: - Primary action and the funnel seam

    /// What the one primary button does in the current state. The decision lives here, not in a
    /// `View` body, because the build-18 HIGH blocker was a signed-out CTA that did nothing and no
    /// test could reach a decision made inside `body`.
    enum PaywallPrimaryAction: Equatable {
        case purchase
        case signIn
        case blocked
    }

    func tapPrimary() -> PaywallPrimaryAction {
        guard isCTAEnabled else { return .blocked }
        let action: PaywallPrimaryAction = isSignedIn ? .purchase : .signIn
        var parameters = accountParameters
        parameters["action"] = action == .purchase ? "purchase" : "sign_in"
        parameters["plan"] = planKey
        emit(PaywallEvent.ctaTap, parameters)
        return action
    }

    /// The cover is gone (the X, or the platform dismissing it). Called by the presentation, guarded
    /// so one dismissal is one event.
    func noteDismissed() {
        guard !hasNotedDismissal else { return }
        hasNotedDismissal = true
        var parameters = accountParameters
        parameters["entitled"] = phase == .entitled ? "true" : "false"
        emit(PaywallEvent.close, parameters)
    }

    /// The parameters every paywall event carries. Enumerated strings only: no account id, no email,
    /// no app user id, no token and no price.
    private var accountParameters: [String: String] {
        ["trigger": trigger.rawValue, "signed_in": isSignedIn ? "true" : "false"]
    }

    private var planKey: String {
        guard let plan = selectedPlan else { return "none" }
        return PaywallPlanCatalog.isAnnual(plan) ? "annual" : "monthly"
    }

    /// `plans_state` reports what the sheet actually shows at the moment the view event fires.
    private var plansState: String {
        if isOffline { return "offline" }
        switch phase {
        case .signInRequired: return "signin"
        case .loadingPlans: return "loading"
        case .unavailable: return "unavailable"
        case .ready, .processing, .purchaseCancelled, .purchaseFailed, .entitled: return "ready"
        }
    }

    private func emitView() {
        guard !hasEmittedView else { return }
        hasEmittedView = true
        var parameters = accountParameters
        parameters["plans_state"] = plansState
        emit(PaywallEvent.view, parameters)
    }

    private func emit(_ name: String, _ parameters: [String: String]) {
        analytics(name, parameters)
    }

    // MARK: - ownership of account-dependent state

    private func observeGateway() {
        snapshotCancellable = gateway.snapshots.sink { [weak self] snapshot in
            guard let self else { return }
            Task { await self.reconcile(with: snapshot) }
        }
    }

    /// Connectivity is a real input to the state machine: the offline boards (11-11, 11-20) are drawn
    /// from the network path, and coming back online retries the offering that could not load.
    private func observeConnectivity() {
        connectivityCancellable = connectivity.changes
            // The subscription closure belongs to the main actor; delivering the path change on the
            // main queue is what makes that isolation true at the call site.
            .receive(on: DispatchQueue.main)
            .sink { [weak self] offline in
                guard let self else { return }
                Task { await self.applyConnectivity(isOffline: offline) }
            }
    }

    private func applyConnectivity(isOffline offline: Bool) async {
        let reconnected = isOffline && !offline
        guard offline != isOffline else { return }
        isOffline = offline
        guard reconnected, isSignedIn, !isBusy else { return }
        if case .unavailable = phase {
            await loadPlans()
        }
    }

    /// Sign-out and unauthorized clears invalidate the paywall's account-dependent state, including
    /// while a sheet is already open. Same rule the hand-written event loop applied.
    func resetForSessionChange(_ event: SessionEvent) {
        switch event {
        case .signedOut, .signInRequired:
            // A model that is already signed out holds nothing account-bound to drop, and clearing
            // it here would race the price preview (the session probe fires this event right after
            // `start()`). A live session is still invalidated, sheet open or not.
            guard isSignedIn else { return }
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
        activeOperation = nil
        isSignedIn = false
        // Prices are a store fact, not account state: a guest view keeps the cards it read before
        // sign-in instead of blanking to "—" on every provider push.
        if !showsPreSignInPrices {
            plans = []
            selectedProductID = nil
        }
        authError = nil
        authProvider = nil
        failure = nil
        lastOperation = nil
        isAuthenticating = false
        phase = .signInRequired
    }

    // MARK: - state mapping

    private func beginOperation() -> UInt64 {
        operationCounter &+= 1
        activeOperation = operationCounter
        return operationCounter
    }

    /// Only the operation that still owns the phase may release it.
    private func endOperation(_ token: UInt64) {
        guard activeOperation == token else { return }
        activeOperation = nil
    }

    private func apply(_ snapshot: PurchaseSnapshot, fromOperation: UInt64? = nil) {
        // Only the operation that currently owns the phase may keep the sheet busy: another
        // operation's result (a superseded purchase, say) leaves the live one alone. Once nothing
        // is running, any settled snapshot takes over, so a stale busy phase cannot wedge the sheet.
        if let activeOperation, fromOperation != activeOperation { return }
        // The failure kind belongs to the settled snapshot that carries it; a snapshot without one
        // clears it, so an old error can never caption a later state.
        failure = snapshot.failure
        switch snapshot.state {
        case .unconfigured:
            plans = []
            phase = .unavailable("Premium is temporarily unavailable. Please try again later.")
        case .noOffering:
            plans = []
            phase = .unavailable("Plans are temporarily unavailable. Retry to check again.")
        case .loading, .purchasePending:
            phase = fromOperation != nil ? .processing : .loadingPlans
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
