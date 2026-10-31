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

    /// A plan card's id follows the package type the catalog sells, never the store product id.
    static func plan(_ product: PurchaseProduct) -> String {
        PaywallPlanCatalog.isAnnual(product) ? planAnnual : planMonthly
    }
}

/// The paywall's sign-in options, in presentation order.
///
/// Apple comes first: App Review guideline 4.8 requires Sign in with Apple wherever another
/// third-party sign-in (Google) is offered, and it must not be the subordinate option. The order
/// lives in `allCases` because the paywall builds its buttons from it, so the rendered order and
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
/// offering through `PurchaseGateway`; the prototype's hardcoded prices are gone because StoreKit
/// metadata is authoritative. An unconfigured SDK or missing offering is shown truthfully as a
/// retryable state rather than fabricated as purchasable plans.
struct PaywallScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var model: PaywallModel
    @State private var showsEmailSignIn = false
    /// The email attempt lives on the screen, not in the sheet content (S4).
    @StateObject private var emailSignIn = EmailSignInModel()

    init(model: @autoclosure @escaping () -> PaywallModel = PaywallModel()) {
        _model = StateObject(wrappedValue: model())
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: AIPoseSpacing.xl) {
                    paywallHeader
                    paywallStory
                    paywallBenefitsPanel
                    paywallOffer
                }
                .padding(.horizontal, AIPoseSpacing.lg)
                .padding(.top, AIPoseSpacing.sm)
                .padding(.bottom, AIPoseSpacing.lg)
            }
            paywallDock
        }
        .background(AIPoseColor.background)
        .navigationBarHidden(true)
        // Email sign-in as a peer of Google (PLAN §4): same `EmailSignInModel`/`APIClient` path,
        // landing in the same isSignedIn/loadPlans() outcome via the call-site seam.
        .emailSignInSheet(
            model: emailSignIn,
            isPresented: $showsEmailSignIn,
            intentLine: "Your purchase is tied to your account. Sign in to continue."
        ) {
            Task { await model.resumeAfterEmailSignIn() }
        }
        .task { model.start() }
    }

    private var paywallHeader: some View {
        HStack {
            HStack(spacing: AIPoseSpacing.sm) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(AIPoseColor.accentYellow)
                    .frame(width: 4, height: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                      Text("posing").font(.caption.weight(.semibold)).foregroundStyle(AIPoseColor.subtext)
                    Text("Premium studio").font(.headline.bold())
                }
            }
            .accessibilityElement(children: .combine)
              .accessibilityLabel("posing Premium")
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(AIPoseColor.foreground)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Close Premium and go back")
            .accessibilityIdentifier(PaywallAccessibilityID.close)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(AIPoseColor.foreground).frame(height: 2).offset(y: AIPoseSpacing.md)
        }
        .padding(.bottom, AIPoseSpacing.lg)
    }

    private var paywallStory: some View {
        VStack(alignment: .leading, spacing: AIPoseSpacing.sm) {
            Text("Pose with confidence.").font(.largeTitle.bold())
            Text("Explore poses, frame the shot, and keep every favorite.")
                .foregroundStyle(AIPoseColor.subtext)
        }
    }

    private var paywallBenefitsPanel: some View {
        HStack(spacing: 0) {
            paywallBenefit(icon: "square.grid.2x2", title: "Discover", subtitle: "Community poses")
            Divider().background(Color.white.opacity(0.3)).frame(height: 56)
            paywallBenefit(icon: "camera.fill", title: "Frame", subtitle: "Full pose camera")
            Divider().background(Color.white.opacity(0.3)).frame(height: 56)
            paywallBenefit(icon: "square.and.arrow.up", title: "Keep", subtitle: "Save and share")
        }
        .padding(.vertical, AIPoseSpacing.md)
        .background(AIPoseColor.foreground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Premium benefits: Discover community poses, Frame with full pose camera, Keep by saving and sharing")
    }

    private func paywallBenefit(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: AIPoseSpacing.xs) {
            Image(systemName: icon).foregroundStyle(.white)
            Text(title).font(.caption.weight(.bold)).foregroundStyle(.white)
            Text(subtitle).font(.caption2).foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var paywallOffer: some View {
        Text("Choose your plan").font(.title3.bold())
        switch model.phase {
        case .signInRequired:
            paywallNotice(
                model.authError ?? "Your purchase is tied to your account. Sign in to continue.",
                isError: model.authError != nil,
                accessibilityLabel: "Sign in to continue with Premium"
            )
            ForEach(PaywallSignInOption.allCases) { option in
                paywallSignInButton(option)
            }
        case .loadingPlans:
            HStack(spacing: AIPoseSpacing.sm) {
                ProgressView()
                Text("Loading plans…").foregroundStyle(AIPoseColor.subtext)
            }
            .frame(maxWidth: .infinity, minHeight: 60)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Loading Premium plans")
        case .unavailable(let message):
            paywallNotice(message, isError: true, accessibilityLabel: "Premium unavailable")
            Button("Retry") { Task { await model.retry() } }
                .buttonStyle(NeoButtonStyle(fill: AIPoseColor.surface))
                .accessibilityLabel("Retry loading Premium plans")
        case .ready, .processing, .purchaseCancelled, .purchaseFailed, .entitled:
            paywallPlanCards
            if let message = model.statusMessage {
                paywallNotice(
                    message,
                    isError: model.phase != .entitled,
                    accessibilityLabel: model.phase == .entitled ? "Premium access confirmed" : "Purchase result"
                )
                .accessibilityIdentifier(PaywallAccessibilityID.status)
            }
        }
    }

    /// One sign-in option, rendered straight from `PaywallSignInOption.allCases`. Apple and Google
    /// share `NeoButtonStyle`'s geometry (full width, one padded height, one border), so neither is
    /// the lesser control; only the fill differs, which HIG requires for Apple.
    @ViewBuilder
    private func paywallSignInButton(_ option: PaywallSignInOption) -> some View {
        switch option {
        case .apple:
            ContinueWithAppleButton(isAuthenticating: model.isAuthenticating) {
                Task { await model.signInWithApple() }
            }
            .accessibilityIdentifier(option.accessibilityIdentifier)
        case .google:
            ContinueWithGoogleButton(isAuthenticating: model.isAuthenticating) {
                Task { await model.signIn() }
            }
            .accessibilityIdentifier(option.accessibilityIdentifier)
        case .email:
            Button { showsEmailSignIn = true } label: {
                Text("Sign in with email")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AIPoseColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.isAuthenticating)
            .accessibilityIdentifier(option.accessibilityIdentifier)
            .accessibilityLabel("Sign in with email")
        }
    }

    private var paywallPlanCards: some View {
        VStack(spacing: AIPoseSpacing.md) {
            ForEach(model.plans, id: \.identifier) { product in
                PaywallPlanCard(
                    product: product,
                    isSelected: product.identifier == model.selectedProductID,
                    onSelect: { model.select(product.identifier) }
                )
                .accessibilityIdentifier(PaywallAccessibilityID.plan(product))
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func paywallNotice(_ text: String, isError: Bool, accessibilityLabel: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(isError ? AIPoseColor.error : AIPoseColor.primary900)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("\(accessibilityLabel). \(text)")
    }

    private var paywallDock: some View {
        VStack(spacing: AIPoseSpacing.md) {
            // The purchase CTA only exists when there is a purchasable plan: the sign-in-required
            // and unavailable states own their own action, so a dead disabled button is never shown.
            if let plan = model.selectedPlan {
                Button { Task { await model.purchase() } } label: {
                    Text(model.ctaTitle)
                }
                .buttonStyle(NeoButtonStyle())
                .frame(minHeight: 44)
                .disabled(model.isBusy)
                .accessibilityLabel(model.ctaTitle)
                .accessibilityIdentifier(PaywallAccessibilityID.cta)

                Text(PaywallPlanCatalog.summaryLine(for: plan))
                    .font(.footnote)
                    .foregroundStyle(AIPoseColor.subtext)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel(PaywallPlanCatalog.summaryLine(for: plan))
            }
            HStack(spacing: AIPoseSpacing.lg) {
                paywallLegalLink("Restore purchases", action: { Task { await model.restore() } })
                paywallLegalLink("Terms", url: SupportDestinations.termsOfServiceURL)
                paywallLegalLink("Privacy", url: SupportDestinations.privacyPolicyURL)
            }
            Text("Cancel anytime in App Store settings. No free trial.")
                .font(.caption)
                .foregroundStyle(AIPoseColor.subtext)
                .multilineTextAlignment(.center)
        }
        .padding(AIPoseSpacing.lg)
        .background(AIPoseColor.background)
        .overlay(alignment: .top) { Rectangle().fill(AIPoseColor.foreground.opacity(0.15)).frame(height: 1) }
    }

    private func paywallLegalLink(_ title: String, url: URL? = nil, action: (() -> Void)? = nil) -> some View {
        Button {
            if let action { action() } else if let url { openURL(url) }
        } label: {
            Text(title)
                .font(.footnote.weight(.bold))
                .supportUnderlinedLink()
        }
        .frame(minHeight: 44)
        .accessibilityLabel(title == "Terms" ? "Terms of Use" : title == "Privacy" ? "Privacy Policy" : title)
    }
}

private struct PaywallPlanCard: View {
    let product: PurchaseProduct
    let isSelected: Bool
    let onSelect: () -> Void

    private var isAnnual: Bool { PaywallPlanCatalog.isAnnual(product) }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: AIPoseSpacing.sm) {
                HStack(spacing: AIPoseSpacing.sm) {
                    Circle()
                        .strokeBorder(AIPoseColor.foreground, lineWidth: 2)
                        .background(Circle().fill(isSelected ? AIPoseColor.foreground : .clear).padding(5))
                        .frame(width: 22, height: 22)
                        .accessibilityHidden(true)
                    Text(PaywallPlanCatalog.label(for: product).uppercased())
                        .font(.caption.weight(.bold))
                    if isAnnual {
                        Text("Recommended")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, AIPoseSpacing.sm)
                            .padding(.vertical, 2)
                            .background(AIPoseColor.accentYellow)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(AIPoseColor.foreground, lineWidth: 1.5))
                    }
                    Spacer(minLength: 0)
                }
                HStack(alignment: .firstTextBaseline, spacing: AIPoseSpacing.xs) {
                    Text(product.localizedPrice).font(.title3.bold())
                    Text("/ \(PaywallPlanCatalog.periodLabel(for: product))")
                        .font(.subheadline.weight(.bold))
                }
                Text(PaywallPlanCatalog.termsLine(for: product))
                    .font(.footnote)
                    .foregroundStyle(AIPoseColor.subtext)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AIPoseSpacing.lg)
            .background(AIPoseColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(AIPoseColor.foreground, lineWidth: isSelected ? 3 : 2)
            )
            .shadow(color: AIPoseColor.foreground, radius: 0, x: isSelected ? 4 : 2, y: isSelected ? 4 : 2)
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityLabel: String {
        let selection = isSelected ? "selected" : "not selected"
        let recommendation = isAnnual ? ", recommended" : ""
        return "\(PaywallPlanCatalog.label(for: product)) plan, \(selection), \(product.localizedPrice) per \(PaywallPlanCatalog.periodLabel(for: product))\(recommendation)"
    }
}

private extension View {
    func supportUnderlinedLink() -> some View {
        overlay(alignment: .bottom) {
            Rectangle()
                .fill(AIPoseColor.foreground)
                .frame(height: 1)
                .offset(y: 1)
        }
    }
}
