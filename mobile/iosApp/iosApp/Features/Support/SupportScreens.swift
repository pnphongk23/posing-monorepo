import AVFoundation
import SwiftUI
import UIKit

struct OnboardingScreen: View {
    let onComplete: () -> Void
    @State private var page = 0
    private let pages = [
        ("sparkles", "Pose with confidence", "Simple guides help you frame every shot."),
        ("camera", "Line it up", "Adjust, flip, and fade a guide over the camera."),
        ("lock.shield", "Your photos, your space", "Keep your gallery close and under your control."),
    ]

    var body: some View {
        VStack(spacing: AIPoseSpacing.xl) {
            Spacer()
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    VStack(spacing: AIPoseSpacing.lg) {
                        Image(systemName: pages[index].0)
                            .font(.system(size: 72))
                            .foregroundStyle(AIPoseColor.primary)
                        Text(pages[index].1).font(.largeTitle.bold())
                        Text(pages[index].2)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(AIPoseColor.subtext)
                    }
                    .padding()
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(height: 360)
            Button(page == pages.count - 1 ? "Get started" : "Continue") {
                if page == pages.count - 1 { onComplete() } else { withAnimation { page += 1 } }
            }
            .buttonStyle(NeoButtonStyle())
            .padding(.horizontal, AIPoseSpacing.xl)
            Button("Skip") { onComplete() }.font(.footnote).foregroundStyle(AIPoseColor.subtext)
        }
        .padding(.bottom, AIPoseSpacing.xl)
        .background(AIPoseColor.background)
    }
}

// MARK: - Account

/// `account.html` signed-out feedback (report §3.8): the shared success state. Pure and testable.
///
/// Two registers, because the prototype only ever paints this card from the sign-out handler
/// (`docs/prototype/scripts/account.js`: `copy: 'Sign in again to access your Saved poses.'`).
/// A fresh install that never signed in has nothing to sign in *again* to, so it gets neutral
/// copy; the `signedOut*` wording is reserved for a session that really ended on this install.
enum AccountStateCopy {
    static let signedOutTitle = "Signed out"
    static let signedOutMessage = "Sign in again to access your Saved poses."
    static let neverSignedInTitle = "Not signed in"
    static let neverSignedInMessage = "Sign in to save poses."
    static let deleteAccountConfirmationTitle = "Delete account?"
    static let deleteAccountConfirmationMessage = "This cannot be undone and your data cannot be recovered."
    /// The Apple sheet was closed: nothing was sent after it, so the account is still there.
    static let deleteAccountCancelledMessage = "Deletion cancelled. Your account was not deleted."
    /// Apple refused the code twice, or the sheet failed. One retry is all the handshake allows.
    static let deleteAccountAppleConfirmationFailedMessage = "Couldn't confirm with Apple. Try again."
    /// The code came from a different Apple ID than the one this account signs in with.
    static let deleteAccountAppleIdentityMismatchMessage = "That Apple ID doesn't match this account. Try again."

    /// Which register the sign-in card (and its email sheet) speaks. Pure input → output so the
    /// never-signed-in case is testable without a screen: the only input is the install's
    /// sign-in history, never the current state alone.
    static func signInCard(hasSignedInBefore: Bool) -> (title: String, message: String) {
        hasSignedInBefore
            ? (signedOutTitle, signedOutMessage)
            : (neverSignedInTitle, neverSignedInMessage)
    }
}

/// Account surface: read-only identity/provider for a valid session, sign-in when there
/// is none, and an explicit sign-out. Owned by `AccountSessionModel` so the screen never
/// invents identity values (see FEAT-014).
struct AccountScreen: View {
    let posesModel: PosesViewModel
    var onTryPose: (NativePose) -> Void = { _ in }
    @StateObject private var model: AccountSessionModel
    @Environment(\.dismiss) private var dismiss
    @State private var showsEmailSignIn = false
    /// The email attempt lives on the screen, not in the sheet content: the Account card re-renders
    /// with the session it is observing, and an attempt opened from it must not be discarded by
    /// that (S4).
    @StateObject private var emailSignIn = EmailSignInModel()
    @StateObject private var appleSignIn = AppleSignInModel()
    @State private var showsDeleteConfirmation = false

    init(
        posesModel: PosesViewModel,
        onTryPose: @escaping (NativePose) -> Void = { _ in },
        model: @autoclosure @escaping () -> AccountSessionModel = AccountSessionModel()
    ) {
        self.posesModel = posesModel
        self.onTryPose = onTryPose
        _model = StateObject(wrappedValue: model())
    }

    var body: some View {
        VStack(spacing: 0) {
            // Own header instead of the system navigation bar: the prototype `.nb-nav-bar` puts a
            // 32pt bordered surface inside a 44pt transparent target, and a `ToolbarItem` renders
            // its content with the platform's own button chrome, which turns that surface into a
            // heavy black box. `NeoSubscreenHeader` is what every other sub-screen already uses.
            NeoSubscreenHeader(title: "Account", onBack: { dismiss() }) {
                // No sign-out while a deletion is in flight: switching accounts mid-deletion would let a
                // reply land on the next session. See `AccountSessionModel.isSignOutAvailable`.
                if model.isSignOutAvailable {
                    NeoCompactActionButton(
                        systemImage: "rectangle.portrait.and.arrow.right",
                        accessibilityLabel: "Sign out",
                        action: { model.signOut() }
                    )
                }
            }
            ScrollView {
                VStack(spacing: AIPoseSpacing.lg) {
                    switch model.state {
                    case .loading:
                        loadingCard
                    case .signedOut:
                        signedOutCard
                    case .signedIn(let account):
                        accountProfileCard(account)
                        savedPosesRow
                        deleteAccountRow
                        if let error = model.deleteAccountError {
                            FeatureStateView(tone: .error, title: "Account deletion failed", message: error)
                                .accessibilityIdentifier("account.delete.error")
                        }
                      case .failed(let message):
                        failedCard(message)
                    }
                }
                .padding(.horizontal, AIPoseSpacing.lg)
                .padding(.top, AIPoseSpacing.sm)
                .padding(.bottom, AIPoseSpacing.xl)
            }
        }
        .background(AIPoseColor.background)
        .neoHiddenNavigationBar()
        // Email sign-in (PLAN §4): presented from the signed-out card; success arrives through the
        // existing `SessionBoundary` `.signedIn` event — no new navigation state (DESIGN §3.2).
        .emailSignInSheet(model: emailSignIn, isPresented: $showsEmailSignIn, intentLine: signInCard.message)
        .alert(AccountStateCopy.deleteAccountConfirmationTitle, isPresented: $showsDeleteConfirmation) {
            Button("Delete account", role: .destructive) { model.deleteAccount() }
                .disabled(model.isDeletingAccount)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(AccountStateCopy.deleteAccountConfirmationMessage)
        }
        .task { model.start() }
    }

    private var loadingCard: some View {
        VStack(spacing: AIPoseSpacing.md) {
            ProgressView()
            Text("Loading account…")
                .font(.subheadline)
                .foregroundStyle(AIPoseColor.subtext)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading account")
    }

    /// `account.html` signed-out feedback renders through the shared `.success` tone (report §3.8).
    /// Named and pure so the tone is assertable: this is the only `.success` producer in the app.
    static let signedOutTone: FeatureStateTone = .success

    /// The card's copy for the current install: neutral until a session really ended here.
    private var signInCard: (title: String, message: String) {
        AccountStateCopy.signInCard(hasSignedInBefore: model.hasSignedInBefore)
    }

    /// `account.html` signed-out feedback (report §3.8): the shared success card. The sign-in
    /// control stays below it so the screen still offers the way back in; an in-flight auth error
    /// keeps its own truthful text (not a state listed by the report).
    private var signedOutCard: some View {
        VStack(alignment: .leading, spacing: AIPoseSpacing.md) {
            FeatureStateView(
                tone: Self.signedOutTone,
                title: signInCard.title,
                message: signInCard.message
            )
            if let authError = model.authError {
                Text(authError)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AIPoseColor.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Sign-in failed. \(authError)")
            }
            ContinueWithGoogleButton(isAuthenticating: model.isAuthenticating) { model.signIn() }
            ContinueWithAppleButton(isAuthenticating: appleSignIn.isAuthenticating) {
                Task { _ = await appleSignIn.signIn() }
            }
            .accessibilityIdentifier(AppleSignInCopy.identifier)
            if let error = appleSignIn.error {
                Text(error)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AIPoseColor.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Sign-in failed. \(error)")
            }
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
            .accessibilityIdentifier("signin.emailEntry")
            .accessibilityLabel("Sign in with email")
        }
        .accessibilityElement(children: .contain)
    }

    private func failedCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: AIPoseSpacing.md) {
            Text("Account unavailable").font(.title3.bold())
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AIPoseColor.error)
                .fixedSize(horizontal: false, vertical: true)
            Button("Retry") { model.retry() }
                .buttonStyle(NeoButtonStyle(fill: AIPoseColor.surface))
                .accessibilityLabel("Retry loading account")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .neoCard()
    }

    private func accountProfileCard(_ account: AccountSummary) -> some View {
        let name = account.displayName.isEmpty ? "Signed-in account" : account.displayName
        return HStack(spacing: AIPoseSpacing.md) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(AIPoseColor.accentBlue)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline.bold())
                // S1 made email/password a second real provider, and the account payload carries no
                // provider field, so naming Google here would be a fabricated claim for every
                // email-signed-in account (the FEAT-013 "Google is the only provider" premise is gone).
                Text("Signed in")
                    .font(.subheadline)
                    .foregroundStyle(AIPoseColor.subtext)
            }
            Spacer(minLength: 0)
        }
        .neoCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name)
    }

    private var savedPosesRow: some View {
        NavigationLink(destination: SavedPosesScreen(model: posesModel, onTryPose: onTryPose)) {
            HStack(spacing: AIPoseSpacing.md) {
                Image(systemName: "bookmark.fill")
                    .font(.body.weight(.bold))
                    .accessibilityHidden(true)
                Text("Saved poses").font(.headline.bold())
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AIPoseColor.subtext)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(AIPoseColor.foreground)
            .frame(minHeight: 44)
            .neoCard()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Saved poses")
    }

    private var deleteAccountRow: some View {
        Button { showsDeleteConfirmation = true } label: {
            HStack(spacing: AIPoseSpacing.md) {
                if model.isDeletingAccount {
                    ProgressView().tint(AIPoseColor.error)
                } else {
                    Image(systemName: "trash").accessibilityHidden(true)
                }
                Text(model.isDeletingAccount ? "Deleting account…" : "Delete account")
                    .font(.headline.bold())
                Spacer(minLength: 0)
            }
            .foregroundStyle(AIPoseColor.error)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .neoCard(background: AIPoseColor.surface)
        }
        .buttonStyle(.plain)
        .disabled(model.isDeletingAccount)
        .accessibilityLabel("Delete account")
    }

}

// MARK: - Settings

struct SettingsScreen: View {
    let posesModel: PosesViewModel
    var onTryPose: (NativePose) -> Void = { _ in }
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsAboutSheet = false
    @State private var showsReplayOnboarding = false
    /// FEAT-011 placement: the user-initiated upgrade entry point (no crowns, no automatic paywall
    /// on a free surface).
    @State private var showsPaywall = false
    @State private var cameraAccess: CameraAccessStatus = .unknown

    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "42"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AIPoseSpacing.xl) {
                if AppConfig.shared.isAccountFeatureEnabled {
                    settingsGroup(title: "Account") {
                        NavigationLink(destination: AccountScreen(posesModel: posesModel, onTryPose: onTryPose)) {
                            SupportSettingsRow(
                                icon: "person.crop.circle",
                                iconColor: AIPoseColor.accentBlue,
                                title: "Account",
                                description: "Manage your account and sign-in options."
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open Account")
                        .accessibilityIdentifier("settings.account.row")
                          NavigationLink(destination: SavedPosesScreen(model: posesModel, onTryPose: onTryPose)) {
                              SupportSettingsRow(
                                icon: "bookmark.fill",
                                iconColor: AIPoseColor.accentGreen,
                                title: "Saved poses",
                                description: "Review the poses you've saved."
                              )
                          }
                          .buttonStyle(.plain)
                          .accessibilityLabel("Open Saved poses")
                      }
                  }

                // FEAT-011 placement: one user-initiated upgrade row, hidden while the paywall
                // kill switch is off so the row can never open a surface the build does not sell.
                if AppConfig.shared.isPaywallEnabled {
                    settingsGroup(title: "Premium") {
                        Button { showsPaywall = true } label: {
                            SupportSettingsRow(
                                icon: "star.fill",
                                iconColor: AIPoseColor.accentYellow,
                                title: "Premium",
                                description: "Unlock photo capture with the pose guide."
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open Premium")
                        .accessibilityIdentifier("settings.premium.row")
                    }
                }

                  settingsGroup(title: "Privacy") {
                    Button { openSystemSettings() } label: {
                        SupportSettingsRow(
                            icon: "info.circle.fill",
                            iconColor: AIPoseColor.accentBlue,
                            title: "Camera access",
                            description: "Check permission status or open iOS Settings.",
                            trailing: .status(cameraAccess.label, cameraAccess.badgeColor)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Camera access, \(cameraAccess.label). Open iOS Settings")
                    Button { openWeb(SupportDestinations.termsOfServiceURL) } label: {
                        SupportSettingsRow(
                            icon: "info.circle.fill",
                            iconColor: AIPoseColor.primary,
                            title: "Terms of Service",
                            description: "Read the Terms of Service in your browser.",
                            trailing: .external
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Terms of Service, opens in browser")
                    Button { openWeb(SupportDestinations.privacyPolicyURL) } label: {
                        SupportSettingsRow(
                            icon: "info.circle.fill",
                            iconColor: AIPoseColor.primary,
                            title: "Privacy Policy",
                            description: "Read the Privacy Policy in your browser.",
                            trailing: .external
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Privacy Policy, opens in browser")
                }

                settingsGroup(title: "Help & support") {
                    Button { showsReplayOnboarding = true } label: {
                        SupportSettingsRow(
                            icon: "sparkles",
                            iconColor: AIPoseColor.primary,
                            title: "Replay onboarding",
                            description: "Review the introduction, pose matching demo, and vibe picker."
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Replay onboarding guide")
                    Button { showsAboutSheet = true } label: {
                        SupportSettingsRow(
                            icon: "info.circle.fill",
                            iconColor: AIPoseColor.accentGreen,
                            title: "About",
                              description: "posing app information and credits.",
                            trailing: .value("v\(appVersion) (Build \(buildNumber))")
                        )
                    }
                    .buttonStyle(.plain)
                  .accessibilityLabel("About posing, version \(appVersion) Build \(buildNumber)")
                }
            }
            .padding(.horizontal, AIPoseSpacing.lg)
            .padding(.vertical, AIPoseSpacing.sm)
            // Its own host: two sheets on one view is where SwiftUI's presentation gets flaky, and
            // About already owns the outer one.
            .sheet(isPresented: $showsPaywall) { PaywallScreen() }
        }
        .background(AIPoseColor.background)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
          .sheet(isPresented: $showsAboutSheet) { AboutPosingSheet(appVersion: appVersion, buildNumber: buildNumber) }
        .fullScreenCover(isPresented: $showsReplayOnboarding) {
            OnboardingScreen { showsReplayOnboarding = false }
        }
        .onAppear { cameraAccess = CameraAccessStatus.current() }
        // The user can flip the permission in iOS Settings and come back; re-read on foreground.
        .onChange(of: scenePhase) { phase in
            if phase == .active { cameraAccess = CameraAccessStatus.current() }
        }
    }

    @ViewBuilder
    private func settingsGroup(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: AIPoseSpacing.sm) {
            Text(title).font(.headline.bold())
            VStack(spacing: AIPoseSpacing.sm) { content() }
        }
    }

    private func openWeb(_ url: URL?) {
        guard let url else { return }
        openURL(url)
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

/// Camera permission projection for the Settings privacy row (`PA-015-06`).
enum CameraAccessStatus: String {
    case allowed, denied, restricted, notDetermined, unknown

    var label: String {
        switch self {
        case .allowed: return "Allowed"
        case .denied, .restricted: return "Blocked"
        case .notDetermined: return "Not set"
        case .unknown: return "Unknown"
        }
    }

    var badgeColor: Color {
        switch self {
        case .allowed: return AIPoseColor.accentGreen
        case .denied, .restricted: return AIPoseColor.error
        case .notDetermined, .unknown: return AIPoseColor.accentYellow
        }
    }

    static func current() -> CameraAccessStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .allowed
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .unknown
        }
    }
}

// MARK: - Paywall

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
            .accessibilityIdentifier("paywall.close")
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
            ContinueWithGoogleButton(isAuthenticating: model.isAuthenticating) {
                Task { await model.signIn() }
            }
            .accessibilityIdentifier("paywall.signin")
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
            .accessibilityIdentifier("signin.emailEntry")
            .accessibilityLabel("Sign in with email")
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
            }
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
                .accessibilityIdentifier("paywall.cta")

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

// MARK: - Shared support components

private enum SupportSettingsTrailing {
    case chevron, external, status(String, Color), value(String)
}

private struct SupportSettingsRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    var trailing: SupportSettingsTrailing = .chevron

    var body: some View {
        HStack(alignment: .top, spacing: AIPoseSpacing.md) {
            Image(systemName: icon)
                .font(.body.weight(.bold))
                .frame(width: 40, height: 40)
                .background(iconColor)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(AIPoseColor.foreground, lineWidth: 2))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline.bold())
                Text(description).font(.subheadline).foregroundStyle(AIPoseColor.subtext)
            }
            Spacer(minLength: 0)
            trailingView
        }
        .foregroundStyle(AIPoseColor.foreground)
        .frame(minHeight: 44, alignment: .top)
        .neoCard()
    }

    @ViewBuilder
    private var trailingView: some View {
        switch trailing {
        case .chevron:
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(AIPoseColor.subtext)
                .accessibilityHidden(true)
        case .external:
            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(AIPoseColor.subtext)
                .accessibilityHidden(true)
        case .status(let label, let color):
            Text(label)
                .font(.caption.weight(.bold))
                .padding(.horizontal, AIPoseSpacing.sm)
                .padding(.vertical, AIPoseSpacing.xs)
                .background(color)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(AIPoseColor.foreground, lineWidth: 1.5))
        case .value(let label):
            HStack(spacing: AIPoseSpacing.xs) {
                Text(label).font(.caption.weight(.semibold)).foregroundStyle(AIPoseColor.subtext)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AIPoseColor.subtext)
                    .accessibilityHidden(true)
            }
        }
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

private struct AboutPosingSheet: View {
    let appVersion: String
    let buildNumber: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: AIPoseSpacing.lg) {
            Capsule().fill(AIPoseColor.subtext.opacity(0.3)).frame(width: 36, height: 4).padding(.top, AIPoseSpacing.sm)
              Text("posing")
                .font(.headline.bold())
                .padding(.horizontal, AIPoseSpacing.lg)
                .padding(.vertical, AIPoseSpacing.md)
                .background(AIPoseColor.accentYellow)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AIPoseColor.foreground, lineWidth: 2))
                .shadow(color: AIPoseColor.foreground, radius: 0, x: 3, y: 3)
              Text("About posing").font(.title2.bold())
            Text("Strike the pose. Snap the moment.")
              Text("posing v\(appVersion) (Build \(buildNumber))")
                .font(.subheadline.weight(.semibold))
              Text("© 2026 posing. All rights reserved.")
                .font(.footnote)
                .foregroundStyle(AIPoseColor.subtext)
            Text("Credits and open-source licenses are available in the production app bundle.")
                .font(.footnote)
                .foregroundStyle(AIPoseColor.subtext)
                .multilineTextAlignment(.center)
            Button("Close") { dismiss() }
                .buttonStyle(NeoButtonStyle(fill: AIPoseColor.surface))
                .frame(minHeight: 44)
                  .accessibilityLabel("Close About posing")
                  .accessibilityIdentifier("about.close")
            Spacer(minLength: 0)
        }
        .padding(AIPoseSpacing.lg)
        // The sheet body used to reach the accessibility tree as nothing at all (QA flow could only see
        // the Close control). `.contain` publishes the title/version/credits lines as their own elements
        // inside a modal container.
        .accessibilityElement(children: .contain)
        .supportSheetPresentation()
        .accessibilityAddTraits(.isModal)
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

    @ViewBuilder
    func supportSheetPresentation() -> some View {
        if #available(iOS 16.0, *) {
            self
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
        } else {
            self
        }
    }
}
