import SwiftUI

// MARK: - Paywall

/// Every accessibility identifier the paywall exposes, in one place: Maestro flows and the id test
/// read the same strings, so a rename cannot silently break a query.
enum PaywallAccessibilityID {
    static let close = "paywall.close"
    static let signInApple = "paywall.signin.apple"
    static let signInGoogle = "paywall.signin"
    /// Shared with the Account sheet: it presents the same email sign-in sheet, so both surfaces
    /// keep one id and QA can drive either one.
    static let signInEmail = "signin.emailEntry"
    static let planAnnual = "paywall.plan.annual"
    static let planMonthly = "paywall.plan.monthly"
    static let status = "paywall.status"
    /// The retry control on a card: the action that settles the state the card reports.
    static let retry = "paywall.retry"
    static let cta = "paywall.cta"
    /// New on the redesign: the single benefit line, the offline banner, the error card and the
    /// sign-in sheet's own surface and close control.
    static let benefit = "paywall.benefit"
    static let offline = "paywall.offline"
    static let notice = "paywall.notice"
    static let signInSheet = "paywall.signin.sheet"
    static let signInClose = "paywall.signin.close"

    /// The 3.1.2 links and the auto-renew disclosure each get their own id, so a flow asserts the
    /// destination instead of matching a label (the handoff and TC-PAY-015 both ask for this).
    static let restore = "paywall.restore"
    static let terms = "paywall.terms"
    static let privacy = "paywall.privacy"
    static let autoRenewDisclosure = "paywall.disclosure.autoRenew"
    /// The line above the CTA when it is about the purchase (the selected plan and today's charge,
    /// or why it cannot be bought yet).
    static let selectedPlanLine = "paywall.disclosure.selection"
    /// The line above the CTA when it is about the account ("Signed in…" / "Sign in first…").
    /// It carries no email: the account payload has none and the paywall never prints one.
    static let accountStatus = "paywall.account.status"
    /// The retry control of an offering that could not be read, distinct from the purchase retry.
    static let offerRetry = "paywall.offer.retry"
    /// The how-it-works block, and the paid step in it (which keeps the old benefit id).
    static let steps = "paywall.steps"
    /// The derived annual figures, so a flow can read the per-month breakdown and the saving badge
    /// without matching the card's combined label. The card ids stay `paywall.plan.annual` /
    /// `paywall.plan.monthly` because Maestro already drives those.
    static let planAnnualPerMonth = "paywall.plan.yearly.permonth"
    static let planAnnualSavings = "paywall.plan.yearly.savings"

    /// A plan card's id follows the package type the catalog sells, never the store product id.
    static func plan(_ product: PurchaseProduct) -> String {
        PaywallPlanCatalog.isAnnual(product) ? planAnnual : planMonthly
    }
}

/// The paywall's sign-in options, in presentation order.
///
/// Apple comes first: App Review guideline 4.8 requires Sign in with Apple wherever another
/// third-party sign-in (Google) is offered, and it must not be the subordinate option. The order
/// lives in `allCases` because the sign-in sheet builds its buttons from it, so the rendered order and
/// the asserted order cannot drift apart.
enum PaywallSignInOption: String, CaseIterable, Identifiable {
    case apple, google, email

    var id: String { rawValue }

    var accessibilityIdentifier: String {
        switch self {
        case .apple: return PaywallAccessibilityID.signInApple
        case .google: return PaywallAccessibilityID.signInGoogle
        case .email: return PaywallAccessibilityID.signInEmail
        }
    }
}

/// Paid-access surface (`FEAT-011`). Plans, prices and renewal terms come from the StoreKit
/// offering through `PurchaseGateway`; every derived figure (per-month breakdown, saving badge) is
/// computed from those packages by `PaywallMoney`, so no price is ever typed into the UI.
///
/// Layout is the approved CRO variant C: a full-bleed hero with the status-bar scrim, the
/// "Pick a pose. Match it. Shoot." headline, the three free/free/paid steps, the two plan cards, the
/// auto-renew disclosure and a pinned purchase region (helper line, CTA, Restore/Terms/Privacy).
/// Every state — loading, offline, purchase error, restore error, signed out — keeps those
/// disclosures on screen.
struct PaywallScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var model: PaywallModel
    /// The email attempt lives on the screen, not in the sheet content (S4).
    @StateObject private var emailSignIn = EmailSignInModel()
    @State private var showsSignInSheet = false
    @State private var showsEmailSignIn = false
    /// Where the presentation came from, forwarded to the model before `start()` so every event
    /// carries it.
    private let trigger: PaywallTrigger

    /// The detents the sign-in sheet is presented with.
    ///
    /// `.large` and nothing smaller, on purpose: a medium-detent sheet is drawn on screen but its
    /// content never reaches the accessibility tree (measured on 1.1 (18), iOS 26 simulator: after
    /// tapping the signed-out CTA the sheet is visible in a screenshot while `paywall.signin.sheet`,
    /// `paywall.signin.apple` and every other element inside it are absent from the hierarchy). The
    /// surface therefore reads as empty to VoiceOver and to any UI-automation query, which is how the
    /// signed-out purchase path came to look like a dead CTA. The email sheet already presents at
    /// `.large` and stays queryable, so the sign-in sheet matches it.
    @available(iOS 16.0, *)
    static let signInSheetDetents: Set<PresentationDetent> = [.large]

    init(
        model: @autoclosure @escaping () -> PaywallModel = PaywallModel(),
        trigger: PaywallTrigger = .shutter
    ) {
        _model = StateObject(wrappedValue: model())
        self.trigger = trigger
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        PaywallCHero(height: PaywallHeroMetrics.height(for: proxy.size.height))
                        VStack(alignment: .leading, spacing: AP.Space.space24) {
                            headline
                            stepsBlock
                            planSection
                            if let notice = model.notice, !model.isOffline {
                                // A failed purchase *is* the outcome: the card is the surface that reports
                                // it, so its headline carries the banner id (`paywall.status`) and its
                                // retry is id'd instead of only labelled. A store failure the user can
                                // neither see reported nor answer is the defect this fixes.
                                SupportNoticeCard(
                                    notice: notice,
                                    titleAccessibilityIdentifier: model.noticeIsSettledOutcome
                                        ? PaywallAccessibilityID.status
                                        : nil,
                                    actionAccessibilityIdentifier: notice.action == .retryLoad
                                        ? PaywallAccessibilityID.offerRetry
                                        : PaywallAccessibilityID.retry,
                                    action: performNoticeAction
                                )
                                .accessibilityIdentifier(PaywallAccessibilityID.notice)
                            }
                            autoRenewCaption
                            if !PaywallScreen.pinsLegalRow(at: dynamicTypeSize) {
                                legalRow
                            }
                            if let status = model.statusMessage, model.notice == nil, !model.isOffline {
                                Text(status)
                                    .font(AP.Font.caption)
                                    .foregroundStyle(AP.Color.secondaryText)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier(PaywallAccessibilityID.status)
                            }
                        }
                        .padding(.horizontal, AP.Space.space16)
                        // The headline starts over the hero's fade, exactly as the mockup draws it.
                        .padding(.top, -AP.Space.space24)
                        .padding(.bottom, AP.Space.space24)
                    }
                }
                // The hero runs under the status bar; the close control and the footer keep their insets.
                .ignoresSafeArea(edges: .top)
                footer
            }
            // Painted edge to edge: the hero runs under the status bar and the footer under the
            // home indicator, so a colour that stopped at the safe area would show through as a band.
            .background(AP.Color.background.ignoresSafeArea())
            .overlay(alignment: .topTrailing) { closeButton }
        }
        .task {
            model.trigger = trigger
            model.start()
        }
        // Email sign-in as a peer of Google (PLAN §4): same `EmailSignInModel`/`APIClient` path,
        // landing in the same isSignedIn/loadPlans() outcome via the call-site seam.
        .emailSignInSheet(
            model: emailSignIn,
            isPresented: $showsEmailSignIn,
            intentLine: "Your purchase is tied to your account. Sign in to continue."
        ) {
            Task { await model.resumeAfterEmailSignIn() }
        }
        .sheet(isPresented: $showsSignInSheet) {
            if #available(iOS 16.0, *) {
                signInSheet
                    .presentationDetents(PaywallScreen.signInSheetDetents)
                    .presentationDragIndicator(.visible)
            } else {
                signInSheet
            }
        }
    }

    // MARK: - Body

    /// The handoff's headline, drawn as the two fragments the mockup shows: the promise in ink and
    /// the action in the accent ink on its own line. Splitting it here is what guarantees no
    /// one-word orphan at 375 pt ("Shoot." can never end up alone on line two).
    private var headline: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(PaywallPlanCopy.headlineLines[0])
                .foregroundStyle(AP.Color.primaryText)
            Text(PaywallPlanCopy.headlineLines[1])
                .foregroundStyle(AP.Color.accentText)
        }
        .font(AP.Font.display)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PaywallPlanCopy.headlineLines.joined(separator: " "))
        .accessibilityAddTraits(.isHeader)
    }

    /// Steps 1–2 are free and step 3 is paid, which is exactly what the gate does: the live guide is
    /// free, only the shutter needs Premium. No copy may imply the guide itself is paid.
    private var stepsBlock: some View {
        VStack(alignment: .leading, spacing: AP.Space.space16) {
            ForEach(PaywallPlanCopy.steps) { step in
                HStack(alignment: .top, spacing: AP.Space.space12) {
                    stepBadge(step)
                    VStack(alignment: .leading, spacing: AP.Space.space4) {
                        Text(step.title)
                            .font(AP.Font.heading)
                            .foregroundStyle(AP.Color.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(step.detail)
                            .font(AP.Font.supporting)
                            .foregroundStyle(AP.Color.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(step.id). \(step.title). \(step.detail)")
                .apIdentifier(step.isPremium ? PaywallAccessibilityID.benefit : nil)
            }
        }
        .accessibilityIdentifier(PaywallAccessibilityID.steps)
    }

    private func stepBadge(_ step: PaywallPlanCopy.Step) -> some View {
        Text("\(step.id)")
            .font(AP.Font.caption.weight(.bold))
            .foregroundStyle(step.isPremium ? AP.Color.background : AP.Color.accentText)
            .frame(width: 28, height: 28)
            .background(
                Circle().fill(step.isPremium ? AP.Color.accentText : AP.Color.selectedBackground)
            )
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var planSection: some View {
        if model.isOffline {
            VStack(alignment: .leading, spacing: AP.Space.space12) {
                SupportInlineBanner(
                    tone: .offline,
                    message: "You're offline. Plans can't load."
                )
                .accessibilityIdentifier(PaywallAccessibilityID.offline)
                planRows(model.planPresentations.isEmpty ? model.placeholderPlans : model.planPresentations)
            }
        } else if model.plans.isEmpty {
            if model.phase == .loadingPlans && model.isSignedIn {
                loadingPlans
            } else if !model.isSignedIn {
                planRows(model.placeholderPlans)
            }
        } else {
            planRows(model.planPresentations)
        }
    }

    private func planRows(_ plans: [PaywallPlanCopy.Plan]) -> some View {
        VStack(spacing: AP.Space.space12) {
            ForEach(plans) { plan in
                PaywallPlanRow(
                    plan: plan,
                    isSelectable: isSelectable(plan),
                    action: { model.select(plan.id) }
                )
                .accessibilityIdentifier(identifier(for: plan))
            }
        }
    }

    private func isSelectable(_ plan: PaywallPlanCopy.Plan) -> Bool {
        !model.isOffline && model.plans.contains { $0.identifier == plan.id }
    }

    /// The plan rows keep one id per package type in every state, so a flow that waits for the annual
    /// card finds it whether the offering is loaded, still loading or unavailable.
    private func identifier(for plan: PaywallPlanCopy.Plan) -> String {
        plan.isAnnual ? PaywallAccessibilityID.planAnnual : PaywallAccessibilityID.planMonthly
    }

    /// Board 11-10: the plan cards keep their geometry while the offering loads, and the CTA says why
    /// it cannot be tapped yet instead of disappearing.
    private var loadingPlans: some View {
        VStack(alignment: .leading, spacing: AP.Space.space12) {
            HStack(spacing: AP.Space.space8) {
                ProgressView()
                Text("Loading plans…")
                    .font(AP.Font.caption)
                    .foregroundStyle(AP.Color.secondaryText)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Loading plans")
            VStack(spacing: AP.Space.space12) {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                        .fill(AP.Color.controlFill)
                        .frame(height: 76)
                }
            }
            .accessibilityHidden(true)
        }
    }

    private var autoRenewCaption: some View {
        Text(PaywallPlanCopy.autoRenewCaption)
            .font(AP.Font.caption)
            .foregroundStyle(AP.Color.secondaryText)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier(PaywallAccessibilityID.autoRenewDisclosure)
    }

    private var closeButton: some View {
        Button {
            // One dismissal is one close event, whatever happens to the cover afterwards.
            model.noteDismissed()
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AP.Color.primaryText)
                .frame(width: AP.HitTarget.minimum, height: AP.HitTarget.minimum)
                .background(
                    RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                        .fill(AP.Color.surface)
                )
                .apElevation(.e1, cornerRadius: AP.Radius.radius16)
        }
        .buttonStyle(.plain)
        .padding(.trailing, AP.Space.space16)
        .padding(.top, AP.Space.space8)
        .accessibilityLabel("Close Premium and go back")
        .accessibilityIdentifier(PaywallAccessibilityID.close)
    }

    // MARK: - Footer (pinned CTA + the 3.1.2 disclosures)

    /// Board 11-01: one primary action, one helper line above it, and the required links below it.
    /// `fixedSize` keeps the dock at its real height at the Accessibility sizes, so the ScrollView
    /// shrinks instead and nothing is painted over (the AX3 board is a scrolled state).
    private var footer: some View {
        VStack(spacing: AP.Space.space12) {
            if let line = footerLine {
                Text(line.text)
                    .font(AP.Font.caption)
                    .foregroundStyle(AP.Color.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier(line.id)
            }
            Button(action: primaryAction) {
                HStack(spacing: AP.Space.space8) {
                    if model.isBusy { ProgressView().tint(AP.Color.onAccent) }
                    Text(model.ctaTitle)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.center)
                }
            }
            .buttonStyle(APPrimaryButtonStyle(minimumHeight: 48))
            .disabled(!model.isCTAEnabled)
            .accessibilityLabel(model.ctaTitle)
            .accessibilityIdentifier(PaywallAccessibilityID.cta)
            if PaywallScreen.pinsLegalRow(at: dynamicTypeSize) {
                legalRow
            }
        }
        .padding(.horizontal, AP.Space.space16)
        .padding(.top, AP.Space.space12)
        .padding(.bottom, AP.Space.space8)
        .fixedSize(horizontal: false, vertical: true)
        .background(AP.Color.background)
    }

    /// The one line above the CTA, and the id that says what it is about: the purchase (the selected
    /// plan and today's charge, or why it cannot be bought yet) or the account. A blocker that
    /// belongs to the network wins over the price, because the price cannot be charged while offline.
    private var footerLine: (text: String, id: String)? {
        if model.isOffline, let helper = model.ctaHelper {
            return (helper, PaywallAccessibilityID.selectedPlanLine)
        }
        if let summary = model.purchaseSummary {
            return (summary, PaywallAccessibilityID.selectedPlanLine)
        }
        if let helper = model.ctaHelper {
            let id = model.phase == .signInRequired
                ? PaywallAccessibilityID.accountStatus
                : PaywallAccessibilityID.selectedPlanLine
            return (helper, id)
        }
        return model.isSignedIn ? (PaywallModel.signedInLine, PaywallAccessibilityID.accountStatus) : nil
    }

    /// The 3.1.2 links live in the pinned dock below the Accessibility sizes and move into the scroll
    /// content at them (today's behaviour, and the plan's recorded deviation): they are always
    /// reachable, and never truncated or painted over.
    static func pinsLegalRow(at size: DynamicTypeSize) -> Bool {
        !size.isAccessibilitySize
    }

    @ViewBuilder
    private var legalRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: AP.Space.space4) {
                legalLinks
            }
        } else {
            HStack(spacing: AP.Space.space16) {
                legalLinks
            }
        }
    }

    @ViewBuilder
    private var legalLinks: some View {
        paywallLegalLink(
            "Restore purchases",
            identifier: PaywallAccessibilityID.restore,
            action: { Task { await model.restore() } }
        )
        paywallLegalLink(
            "Terms of Use",
            identifier: PaywallAccessibilityID.terms,
            url: SupportDestinations.termsOfServiceURL
        )
        paywallLegalLink(
            "Privacy Policy",
            identifier: PaywallAccessibilityID.privacy,
            url: SupportDestinations.privacyPolicyURL
        )
    }

    private func paywallLegalLink(
        _ title: String,
        identifier: String,
        url: URL? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        Button {
            if let action { action() } else if let url { openURL(url) }
        } label: {
            Text(title)
                .font(AP.Font.caption.weight(.semibold))
                .foregroundStyle(AP.Color.accentText)
                .fixedSize(horizontal: false, vertical: true)
                // `Text.underline()` is iOS 16+, so the rule is drawn under the label instead.
                .padding(.bottom, 2)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(AP.Color.accentText).frame(height: 1)
                }
                .frame(minHeight: AP.HitTarget.minimum)
        }
        .buttonStyle(.plain)
        .disabled(model.isBusy)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Actions

    private func primaryAction() {
        // The outcome is decided in the model (and is therefore testable): signed out the CTA opens
        // the sign-in sheet and never starts a guest purchase, which is the build-18 regression.
        switch model.tapPrimary() {
        case .signIn: showsSignInSheet = true
        case .purchase: Task { await model.purchase() }
        case .blocked: break
        }
    }

    private func performNoticeAction(_ action: SupportNotice.Action) {
        switch action {
        case .retryLoad: Task { await model.retry() }
        case .retryRestore: Task { await model.restore() }
        case .retryGoogle: Task { await model.signIn() }
        case .retryPurchase: Task { await model.purchase() }
        }
    }

    // MARK: - Sign-in sheet (boards 11-12 … 11-15)

    /// Sign-in is required to buy, so it is its own sheet over the paywall: one method per row, Apple
    /// first, and the consent line under them.
    private var signInSheet: some View {
        PaywallSignInSheet(
            model: model,
            onApple: { await model.signInWithApple() },
            onGoogle: { await model.signIn() },
            onEmail: {
                showsSignInSheet = false
                showsEmailSignIn = true
            },
            onClose: { showsSignInSheet = false }
        )
    }
}

/// Hero metrics for the CRO layout, in one place so the view and the measurements agree
/// (`handoff-1.2.md` §1: ~210–312 pt tall on a 6.7" phone, and never the whole viewport).
enum PaywallHeroMetrics {
    /// 28 % of the container: 261 pt on a 932 pt phone, 187 pt on an SE, clamped to 180–312.
    static let heightRatio: CGFloat = 0.28
    static let minHeight: CGFloat = 180
    static let maxHeight: CGFloat = 312
    /// The status-bar scrim: the top of the hero is washed toward the `background` token, which in
    /// light mode is a cream wash under dark status glyphs and in dark mode near-black under white
    /// glyphs. The wash holds ≥0.68 alpha across the whole status-bar band (0–57 pt) and fades out by
    /// 76 pt, so the clock and battery clear 4.5:1 over the brightest pixel of the hero in both
    /// schemes (`PaywallScreenLayoutTests` measures it on the rendered frame).
    static let topScrimHeight: CGFloat = 76
    static let topScrimOpacity: Double = 0.72
    static let topScrimFloorOpacity: Double = 0.68
    /// Fraction of the scrim height where the floor opacity ends and the fade to clear begins (57 pt).
    static let topScrimFloorLocation: CGFloat = 0.75
    /// The hero fades into the page background over its bottom half, so the headline can start on it.
    static let fadeRatio: CGFloat = 0.55

    static func height(for containerHeight: CGFloat) -> CGFloat {
        min(max(containerHeight * heightRatio, minHeight), maxHeight)
    }
}

/// The C hero: the bundled pose photo, full bleed under the status bar, with the status-bar scrim on
/// top and the background fade at the bottom. No motion, so Reduce Motion changes nothing.
struct PaywallCHero: View {
    let height: CGFloat

    var body: some View {
        Image("paywallHeroC")
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipped()
            .overlay(alignment: .top) {
                LinearGradient(
                    stops: [
                        .init(
                            color: AP.Color.background.opacity(PaywallHeroMetrics.topScrimOpacity),
                            location: 0
                        ),
                        .init(
                            color: AP.Color.background.opacity(PaywallHeroMetrics.topScrimFloorOpacity),
                            location: PaywallHeroMetrics.topScrimFloorLocation
                        ),
                        .init(color: AP.Color.background.opacity(0), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: PaywallHeroMetrics.topScrimHeight)
            }
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [AP.Color.background.opacity(0), AP.Color.background],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: height * PaywallHeroMetrics.fadeRatio)
            }
            .accessibilityHidden(true)
    }
}

/// One plan card (boards 11-02/11-03): selection is a filled box, the saving badge sits beside the
/// plan name, the billing breakdown under it and the price on the trailing edge. At the Accessibility
/// sizes the card stacks (board 11-04) instead of squeezing four columns into one row.
struct PaywallPlanRow: View {
    let plan: PaywallPlanCopy.Plan
    let isSelectable: Bool
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: AP.Space.space8) {
                        HStack(spacing: AP.Space.space12) {
                            selectionBox
                            Text(plan.title).font(AP.Font.heading)
                        }
                        badge
                        Text(plan.detail)
                            .font(AP.Font.caption)
                            .apIdentifier(plan.isAnnual ? PaywallAccessibilityID.planAnnualPerMonth : nil)
                        Text(plan.price).font(AP.Font.data)
                    }
                } else {
                    HStack(alignment: .center, spacing: AP.Space.space12) {
                        selectionBox
                        VStack(alignment: .leading, spacing: AP.Space.space4) {
                            HStack(spacing: AP.Space.space8) {
                                Text(plan.title).font(AP.Font.heading)
                                badge
                            }
                            Text(plan.detail)
                                .font(AP.Font.caption)
                                .apIdentifier(plan.isAnnual ? PaywallAccessibilityID.planAnnualPerMonth : nil)
                        }
                        Spacer(minLength: AP.Space.space8)
                        Text(plan.price).font(AP.Font.data)
                    }
                }
            }
            .foregroundStyle(plan.isSelected ? AP.Color.selectedForeground : AP.Color.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AP.Space.space16)
            .background(
                RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                    .fill(plan.isSelected ? AP.Color.selectedBackground : AP.Color.controlFill)
            )
            .contentShape(RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isSelectable)
        // A container, so the per-month breakdown and the saving badge can be located on their own
        // (QA's ids) while the card keeps one tappable element with an observable selection state.
        .accessibilityElement(children: .contain)
        .accessibilityValue(plan.isSelected ? "selected" : "not selected")
        .accessibilityAddTraits(plan.isSelected ? [.isButton, .isSelected] : [.isButton])
    }

    /// Board 11-02: a filled box with a check when selected, an empty box otherwise — never a stroke
    /// on the row itself.
    private var selectionBox: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(plan.isSelected ? AP.Color.selectedForeground : AP.Color.background)
            .frame(width: 24, height: 24)
            .overlay {
                if plan.isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AP.Color.selectedBackground)
                }
            }
            .accessibilityHidden(true)
    }

    /// "Save N%" only when the two store prices make the claim computable (never a typed figure).
    @ViewBuilder
    private var badge: some View {
        if let badge = plan.badge {
            Text(badge)
                .font(AP.Font.caption.weight(.semibold))
                .foregroundStyle(AP.Color.accentText)
                .padding(.horizontal, AP.Space.space8)
                .padding(.vertical, AP.Space.space4)
                .background(AP.Color.surface, in: Capsule())
                .fixedSize()
                .apIdentifier(plan.isAnnual ? PaywallAccessibilityID.planAnnualSavings : nil)
        }
    }
}

/// Board 11-12 … 11-15: "Sign in to subscribe". One method per row, Apple first, the provider error
/// card above them, and the consent line under them.
struct PaywallSignInSheet: View {
    @ObservedObject var model: PaywallModel
    let onApple: () async -> Void
    let onGoogle: () async -> Void
    let onEmail: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AP.Space.space16) {
            HStack(alignment: .top, spacing: AP.Space.space12) {
                Text("Sign in to subscribe")
                    .font(AP.Font.title)
                    .foregroundStyle(AP.Color.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AP.Color.primaryText)
                        .frame(width: AP.HitTarget.minimum, height: AP.HitTarget.minimum)
                        .background(
                            RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                                .fill(AP.Color.controlFill)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close sign-in")
                .accessibilityIdentifier(PaywallAccessibilityID.signInClose)
            }
            Text("Create an account or sign in. Your Premium stays with your account.")
                .font(AP.Font.supporting)
                .foregroundStyle(AP.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let notice = model.notice, model.authError != nil {
                SupportNoticeCard(notice: notice) { action in
                    guard action == .retryGoogle else { return }
                    Task { await onGoogle() }
                }
            }
            ScrollView {
                VStack(spacing: AP.Space.space12) {
                    ForEach(PaywallSignInOption.allCases) { option in
                        button(for: option)
                            .accessibilityIdentifier(option.accessibilityIdentifier)
                    }
                }
                .padding(.bottom, AP.Space.space8)
            }
            consentLine
        }
        .padding(.horizontal, AP.Space.space16)
        .padding(.top, AP.Space.space24)
        .padding(.bottom, AP.Space.space16)
        .background(AP.Color.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(PaywallAccessibilityID.signInSheet)
    }

    @ViewBuilder
    private func button(for option: PaywallSignInOption) -> some View {
        switch option {
        case .apple:
            ContinueWithAppleButton(isAuthenticating: model.isAuthenticating) {
                Task { await onApple() }
            }
        case .google:
            ContinueWithGoogleButton(
                isAuthenticating: model.isAuthenticating && model.authProvider == .google,
                title: googleTitle
            ) {
                Task { await onGoogle() }
            }
            .disabled(model.isAuthenticating)
        case .email:
            Button(action: onEmail) {
                HStack(spacing: AP.Space.space12) {
                    Image(systemName: "envelope")
                        .font(AP.Font.body)
                    Text("Continue with email")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .buttonStyle(APSecondaryButtonStyle())
            .disabled(model.isAuthenticating)
            .accessibilityLabel("Continue with email")
        }
    }

    /// Board 11-15: after a failed Google attempt the same row is the retry, so the recovery is one
    /// tap and not a separate control.
    private var googleTitle: String {
        if model.isAuthenticating && model.authProvider == .google { return "Opening Google…" }
        if model.authError != nil && model.authProvider == .google { return "Try Google again" }
        return "Continue with Google"
    }

    /// "By continuing you agree to the Terms of Use and Privacy Policy." with both documents linked.
    private var consentLine: some View {
        Text(consentText)
            .font(AP.Font.caption)
            .foregroundStyle(AP.Color.secondaryText)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("By continuing you agree to the Terms of Use and Privacy Policy.")
    }

    private var consentText: AttributedString {
        var text = AttributedString("By continuing you agree to the ")
        text.append(link("Terms of Use", SupportDestinations.termsOfServiceURL))
        text.append(AttributedString(" and "))
        text.append(link("Privacy Policy", SupportDestinations.privacyPolicyURL))
        text.append(AttributedString("."))
        return text
    }

    private func link(_ title: String, _ url: URL?) -> AttributedString {
        var part = AttributedString(title)
        part.foregroundColor = AP.Color.accentText
        part.underlineStyle = .single
        if let url { part.link = url }
        return part
    }
}

extension View {
    /// Board 11-01: the paywall is a full-screen cover with a Close control, not a sheet. Call sites
    /// that present `PaywallScreen` use this instead of `.sheet`, so the presentation is decided once.
    /// `trigger` names the entry point so every funnel event carries it.
    func paywallCover(
        isPresented: Binding<Bool>,
        trigger: PaywallTrigger = .shutter
    ) -> some View {
        fullScreenCover(isPresented: isPresented) { PaywallScreen(trigger: trigger) }
    }
}
