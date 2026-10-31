import SwiftUI

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
    var onTryPose: (CameraPoseRequest) -> Void = { _ in }
    @StateObject private var model: AccountSessionModel
    @Environment(\.dismiss) private var dismiss
    /// The same external-open mechanism the Settings/Support rows use: "Delete account" leaves the
    /// app for the deletion request form, it does not delete anything in-app.
    @Environment(\.openURL) private var openURL
    @State private var showsEmailSignIn = false
    /// The email attempt lives on the screen, not in the sheet content: the Account card re-renders
    /// with the session it is observing, and an attempt opened from it must not be discarded by
    /// that (S4).
    @StateObject private var emailSignIn = EmailSignInModel()
    @StateObject private var appleSignIn = AppleSignInModel()

    init(
        posesModel: PosesViewModel,
        onTryPose: @escaping (CameraPoseRequest) -> Void = { _ in },
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
            // F1: the shared page header; the sign-out control rides in its trailing slot.
            HStack(alignment: .center, spacing: AP.Space.space12) {
                APPageHeader(title: "Account", onBack: { dismiss() })
                if model.isSignOutAvailable {
                    NeoCompactActionButton(
                        systemImage: "rectangle.portrait.and.arrow.right",
                        accessibilityLabel: "Sign out",
                        action: { model.signOut() }
                    )
                    .padding(.trailing, AP.Space.space16)
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
                      case .failed(let message):
                        failedCard(message)
                    }
                    // Only an account has something to ask about: a signed-out or failed surface
                    // offers no deletion row at all.
                    if model.isAccountDeletionRequestAvailable {
                        deleteAccountRow
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
            .accessibilityIdentifier(PaywallAccessibilityID.signInEmail)
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

    /// Opens the deletion **request** form in the browser. The row, its label ("Delete account") and
    /// its placement under Saved poses are unchanged; only the destination is: an admin deletes the
    /// account, the app never sends a delete of its own.
    private var deleteAccountRow: some View {
        Button { model.openAccountDeletionRequest { openURL($0) } } label: {
            HStack(spacing: AIPoseSpacing.md) {
                Image(systemName: "trash").accessibilityHidden(true)
                Text("Delete account")
                    .font(.headline.bold())
                Spacer(minLength: 0)
            }
            .foregroundStyle(AIPoseColor.error)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .neoCard(background: AIPoseColor.surface)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete account")
    }

}
