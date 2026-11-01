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
    static let cta = "paywall.cta"
    /// New on the redesign: the single benefit line, the offline banner, the error card and the
    /// sign-in sheet's own surface and close control.
    static let benefit = "paywall.benefit"
    static let offline = "paywall.offline"
    static let notice = "paywall.notice"
    static let signInSheet = "paywall.signin.sheet"
    static let signInClose = "paywall.signin.close"

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
/// Layout follows the page-11 boards: a hero, the single shutter benefit (Premium unlocks capture
/// with the full pose camera and nothing else), two plan cards, the auto-renew disclosure, a pinned
/// CTA and the 3.1.2 links. Every state — loading, offline, purchase error, restore error, signed
/// out — keeps those disclosures on screen.
struct PaywallScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var model: PaywallModel
    /// The email attempt lives on the screen, not in the sheet content (S4).
    @StateObject private var emailSignIn = EmailSignInModel()
    @State private var showsSignInSheet = false
    @State private var showsEmailSignIn = false

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

    init(model: @autoclosure @escaping () -> PaywallModel = PaywallModel()) {
        _model = StateObject(wrappedValue: model())
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PaywallHero()
                    VStack(alignment: .leading, spacing: AP.Space.space16) {
                        titleBlock
                        benefitRow
                        planSection
                        if let notice = model.notice, !model.isOffline {
                            SupportNoticeCard(notice: notice, action: performNoticeAction)
                                .accessibilityIdentifier(PaywallAccessibilityID.notice)
                        }
                        autoRenewCaption
                        if dynamicTypeSize.isAccessibilitySize {
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
                    .padding(.top, AP.Space.space24)
                    .padding(.bottom, AP.Space.space24)
                }
            }
            // The hero runs under the status bar; the close control and the footer keep their insets.
            .ignoresSafeArea(edges: .top)
            footer
        }
        .background(AP.Color.background)
        .overlay(alignment: .topTrailing) { closeButton }
        .task { model.start() }
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

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: AP.Space.space8) {
            Text("Full pose camera")
                .font(AP.Font.display)
                .foregroundStyle(AP.Color.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Shoot with the guide on every capture.")
                .font(AP.Font.body)
                .foregroundStyle(AP.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Premium gates one thing: capturing with the full pose camera. The three-up benefit panel the
    /// old paywall drew claimed discovery and saving too, which the entitlement never granted.
    private var benefitRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: AP.Space.space8) {
            Image(systemName: "checkmark")
                .font(AP.Font.heading)
                .foregroundStyle(AP.Color.accentText)
                .accessibilityHidden(true)
            Text(PaywallPlanCopy.benefit)
                .font(AP.Font.body)
                .foregroundStyle(AP.Color.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Premium: \(PaywallPlanCopy.benefit)")
        .accessibilityIdentifier(PaywallAccessibilityID.benefit)
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
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
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
                Text(line)
                    .font(AP.Font.caption)
                    .foregroundStyle(AP.Color.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
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
            if !dynamicTypeSize.isAccessibilitySize {
                legalRow
            }
        }
        .padding(.horizontal, AP.Space.space16)
        .padding(.top, AP.Space.space12)
        .padding(.bottom, AP.Space.space8)
        .fixedSize(horizontal: false, vertical: true)
        .background(AP.Color.background)
    }

    private var footerLine: String? {
        if let helper = model.ctaHelper { return helper }
        return model.isSignedIn ? PaywallModel.signedInLine : nil
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
        paywallLegalLink("Restore purchases", action: { Task { await model.restore() } })
        paywallLegalLink("Terms of Use", url: SupportDestinations.termsOfServiceURL)
        paywallLegalLink("Privacy Policy", url: SupportDestinations.privacyPolicyURL)
    }

    private func paywallLegalLink(_ title: String, url: URL? = nil, action: (() -> Void)? = nil) -> some View {
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
    }

    // MARK: - Actions

    private func primaryAction() {
        guard model.isCTAEnabled else { return }
        guard model.isSignedIn else {
            showsSignInSheet = true
            return
        }
        Task { await model.purchase() }
    }

    private func performNoticeAction(_ action: SupportNotice.Action) {
        switch action {
        case .retryLoad: Task { await model.retry() }
        case .retryRestore: Task { await model.restore() }
        case .retryGoogle: Task { await model.signIn() }
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

/// Board 11-01: the paywall opens on imagery. The bundle ships no photo asset (the app draws every
/// pose from the remote catalog), so the hero is drawn from the design tokens — a soft accent wash
/// with the pose figure — instead of shipping a stock photo.
struct PaywallHero: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AP.Color.selectedBackground, AP.Color.secondaryBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            Image(systemName: "figure.stand")
                .font(.system(size: 96, weight: .regular))
                .foregroundStyle(AP.Color.accentText.opacity(0.9))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .clipped()
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
                        Text(plan.detail).font(AP.Font.caption)
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
                            Text(plan.detail).font(AP.Font.caption)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(plan.accessibilityLabel)
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
                .accessibilityHidden(true)
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
    func paywallCover(isPresented: Binding<Bool>) -> some View {
        fullScreenCover(isPresented: isPresented) { PaywallScreen() }
    }
}
