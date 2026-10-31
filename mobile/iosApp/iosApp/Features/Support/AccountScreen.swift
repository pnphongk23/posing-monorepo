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

/// What the PREMIUM section may say, derived from the live entitlement and nothing else.
///
/// The rule is the same one the capture gate uses: only a *confirmed* answer becomes a claim. An
/// entitlement that is still loading, or a snapshot that failed, is `.unknown` — the section then
/// shows no plan and no "Manage subscription" row, because a plan the app cannot prove would be
/// invented.
enum AccountPremiumStatus: Equatable {
    case active
    case notSubscribed
    case unknown

    static func resolve(entitlement: PurchaseGatewayState, isSignedIn: Bool) -> AccountPremiumStatus {
        if entitlement == .entitled {
            // Access belongs to an Account: an entitled snapshot with no session is not this
            // user's subscription.
            return isSignedIn ? .active : .notSubscribed
        }
        if !isSignedIn { return .notSubscribed }
        // A build that cannot sell (`unconfigured`) cannot hold an entitlement, so "not subscribed"
        // is a fact there rather than a guess.
        if entitlement == .unconfigured { return .notSubscribed }
        guard PremiumGate.isConfirmedNotEntitled(entitlement) else { return .unknown }
        return .notSubscribed
    }

    /// Value of the Plan row. `nil` = no claim, so the row is not drawn.
    var planValue: String? {
        switch self {
        case .active: return "Premium"
        case .notSubscribed: return "Not subscribed"
        case .unknown: return nil
        }
    }

    /// Apple owns subscription management; the row only exists for a subscription the app can prove.
    var showsManageSubscription: Bool { self == .active }

    /// The Settings hub badge (`Active`), and `nil` for every state that must not claim access.
    var badge: String? { self == .active ? "Active" : nil }
}

/// Account surface: the identity a valid session projects, the plan it holds, and the two session
/// actions (sign out, and the external deletion *request*). Owned by `AccountSessionModel` so the
/// screen never invents identity values (FEAT-014).
struct AccountScreen: View {
    /// Kept for the call sites that push this screen; Saved now lives on the Settings hub
    /// (board 10-05 has no "Saved poses" row), so the screen itself no longer navigates anywhere.
    let posesModel: PosesViewModel
    var onTryPose: (CameraPoseRequest) -> Void = { _ in }
    @StateObject private var model: AccountSessionModel
    @Environment(\.dismiss) private var dismiss
    /// The same external-open mechanism the Settings/Support rows use: "Delete account" leaves the
    /// app for the deletion request form, it does not delete anything in-app, and "Manage
    /// subscription" leaves it for Apple's own page.
    @Environment(\.openURL) private var openURL
    @State private var showsEmailSignIn = false
    /// The email attempt lives on the screen, not in the sheet content: the Account card re-renders
    /// with the session it is observing, and an attempt opened from it must not be discarded by
    /// that (S4).
    @StateObject private var emailSignIn = EmailSignInModel()
    @StateObject private var appleSignIn = AppleSignInModel()
    /// Entitlement, read from the same live provider the capture gate reads, so the plan this screen
    /// shows is the plan the shutter would honour.
    @StateObject private var premium = PremiumGateModel()

    init(
        posesModel: PosesViewModel,
        onTryPose: @escaping (CameraPoseRequest) -> Void = { _ in },
        model: @autoclosure @escaping () -> AccountSessionModel = AccountSessionModel(
            connectivity: NWPathAccountConnectivity()
        ),
        premium: @autoclosure @escaping () -> PremiumGateModel = PremiumGateModel()
    ) {
        self.posesModel = posesModel
        self.onTryPose = onTryPose
        _model = StateObject(wrappedValue: model())
        _premium = StateObject(wrappedValue: premium())
    }

    var body: some View {
        VStack(spacing: 0) {
            APPageHeader(
                title: "Account",
                backIdentifier: "account.back",
                titleIdentifier: "account.title",
                onBack: { dismiss() }
            )
            ScrollView {
                VStack(alignment: .leading, spacing: AP.Space.space24) {
                    if model.isOffline {
                        APOfflineBanner(
                            message: "You're offline. Showing your saved account details.",
                            retryTitle: nil,
                            retry: nil
                        )
                        .accessibilityIdentifier("account.offline.banner")
                    }
                    content
                }
                .padding(.horizontal, AP.Space.space16)
                .padding(.top, AP.Space.space8)
                .padding(.bottom, AP.Space.space32)
            }
        }
        .background(AP.Color.background)
        .neoHiddenNavigationBar()
        // Email sign-in (PLAN §4): presented from the signed-out card; success arrives through the
        // existing `SessionBoundary` `.signedIn` event — no new navigation state (DESIGN §3.2).
        .emailSignInSheet(model: emailSignIn, isPresented: $showsEmailSignIn, intentLine: signInCard.message)
        .task {
            model.start()
            premium.start()
        }
        .onDisappear { model.stop() }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .loading:
            loadingSkeleton
        case .signedOut:
            signedOutCard
        case .signedIn(let account):
            signedInContent(account)
        case .failed(let message):
            errorState(message)
        }
    }

    // MARK: - Signed in (board 10-05 / 10-06 / 10-09)

    private func signedInContent(_ account: AccountSummary) -> some View {
        VStack(alignment: .leading, spacing: AP.Space.space24) {
            identityBlock(account)
            if !model.identity.isEmpty {
                profileSection
            }
            premiumSection
            accountActions
        }
    }

    /// Initials avatar, display name, and the address the session proves. Centred, and at the
    /// Accessibility sizes the copy wraps under the avatar instead of being squeezed beside it.
    private func identityBlock(_ account: AccountSummary) -> some View {
        let name = account.displayName.isEmpty ? "Signed-in account" : account.displayName
        return VStack(spacing: AP.Space.space12) {
            avatar(initials: AccountAvatar.initials(for: account.displayName))
            Text(name)
                .font(AP.Font.title)
                .foregroundStyle(AP.Color.primaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("account.name")
            if let email = model.identity.email {
                Text(email)
                    .font(AP.Font.body)
                    .foregroundStyle(AP.Color.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("account.email")
            }
            if model.isShowingCachedDetails {
                Text("Saved details")
                    .font(AP.Font.caption)
                    .foregroundStyle(AP.Color.secondaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AP.Space.space8)
        .accessibilityElement(children: .contain)
    }

    private func avatar(initials: String) -> some View {
        // A circle is a shape, not a token (AP.Radius is for rectangles), and it is the one place
        // the accent fill carries text — `onAccent` keeps that label at the documented contrast.
        ZStack {
            Circle().fill(AP.Color.accent)
            if initials.isEmpty {
                Image(systemName: "person.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(AP.Color.onAccent)
            } else {
                Text(initials)
                    .font(AP.Font.title)
                    .foregroundStyle(AP.Color.onAccent)
            }
        }
        .frame(width: 88, height: 88)
        .accessibilityIdentifier("account.avatar")
        .accessibilityHidden(true)
    }

    private var profileSection: some View {
        AccountSection(title: "Profile") {
            AccountCard {
                if let email = model.identity.email {
                    AccountValueRow(title: "Email", value: email)
                        .accessibilityIdentifier("account.profile.email")
                }
                if let method = model.identity.signInMethod {
                    if model.identity.email != nil {
                        AccountCardSeparator()
                    }
                    AccountValueRow(title: "Sign-in method", value: method)
                        .accessibilityIdentifier("account.profile.method")
                }
            }
        }
    }

    @ViewBuilder private var premiumSection: some View {
        let status = AccountPremiumStatus.resolve(
            entitlement: premium.entitlement,
            isSignedIn: model.isSignOutAvailable
        )
        if let planValue = status.planValue {
            AccountSection(title: "Premium") {
                AccountCard {
                    AccountValueRow(title: "Plan", value: planValue)
                        .accessibilityIdentifier("account.plan")
                    if status.showsManageSubscription {
                        AccountCardSeparator()
                        Button { openSubscriptionManagement() } label: {
                            AccountActionRow(
                                systemImage: "arrow.up.forward.square",
                                title: "Manage subscription",
                                subtitle: "Opens Apple ID settings",
                                tint: AP.Color.primaryText,
                                trailing: .external
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Manage subscription, opens Apple ID settings")
                        .accessibilityIdentifier("account.manageSubscription")
                    }
                }
            }
        }
    }

    private var accountActions: some View {
        VStack(alignment: .leading, spacing: AP.Space.space12) {
            if model.isSignOutAvailable {
                Button { model.signOut() } label: {
                    AccountActionRow(
                        systemImage: "rectangle.portrait.and.arrow.right",
                        title: "Sign out",
                        tint: AP.Color.accentText
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Sign out")
                .accessibilityIdentifier("account.signout")
            }
            if model.isAccountDeletionRequestAvailable || model.accountDeletionUnavailableReason != nil {
                deleteRow
            }
            if AccountPremiumStatus.resolve(
                entitlement: premium.entitlement,
                isSignedIn: model.isSignOutAvailable
            ) == .active {
                Text("Deleting your account doesn't cancel your Apple subscription.")
                    .font(AP.Font.caption)
                    .foregroundStyle(AP.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AP.Space.space4)
            }
        }
    }

    /// Opens the deletion **request** form in the browser; an admin deletes the account, the app never
    /// sends a delete of its own. Offline the row is drawn disabled with its reason, because the form
    /// cannot be filled in without a connection.
    private var deleteRow: some View {
        let disabledReason = model.accountDeletionUnavailableReason
        return Button {
            model.openAccountDeletionRequest { openURL($0) }
        } label: {
            AccountActionRow(
                systemImage: "trash",
                title: "Delete account",
                subtitle: disabledReason,
                subtitleIdentifier: disabledReason == nil ? nil : "account.delete.reason",
                tint: disabledReason == nil ? AP.Color.error : AP.Color.disabled,
                isEnabled: disabledReason == nil,
                trailing: .none
            )
        }
        .buttonStyle(.plain)
        .disabled(disabledReason != nil)
        .accessibilityLabel(disabledReason.map { "Delete account. \($0)" } ?? "Delete account")
        .accessibilityIdentifier("account.delete")
    }

    // MARK: - Loading (board 10-07)

    /// The board's loading state is the signed-in geometry with flat bars in place of text: an avatar
    /// circle, the two identity bars, then the two grouped cards. Same shape as the content, so the
    /// screen does not jump when the read lands.
    private var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: AP.Space.space24) {
            VStack(spacing: AP.Space.space12) {
                Circle()
                    .fill(AP.Color.controlFill)
                    .frame(width: 88, height: 88)
                APSkeletonBar(width: 140, height: 20)
                APSkeletonBar(width: 180)
            }
            .frame(maxWidth: .infinity)
            AccountSection(title: "Profile") {
                AccountSkeletonCard(rows: 2)
            }
            AccountSection(title: "Premium") {
                AccountSkeletonCard(rows: 2)
            }
            Text("Loading account…")
                .font(AP.Font.supporting)
                .foregroundStyle(AP.Color.secondaryText)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("account.loading")
        .accessibilityLabel("Loading account")
    }

    // MARK: - Error (board 10-08)

    private func errorState(_ message: String) -> some View {
        APErrorStateView(
            title: "Couldn't load your account",
            message: message,
            retryTitle: "Try again",
            retry: { model.retry() },
            style: .plain,
            actionIdentifier: "account.error.retry"
        )
        .accessibilityIdentifier("account.error")
    }

    // MARK: - Signed out

    /// `account.html` signed-out feedback renders through the shared `.success` tone (report §3.8).
    /// Named and pure so the tone is assertable: this is the only `.success` producer in the app.
    static let signedOutTone: FeatureStateTone = .success

    /// The card's copy for the current install: neutral until a session really ended here.
    private var signInCard: (title: String, message: String) {
        AccountStateCopy.signInCard(hasSignedInBefore: model.hasSignedInBefore)
    }

    /// The sign-in control stays below the state card so the screen still offers the way back in; an
    /// in-flight auth error keeps its own truthful text.
    private var signedOutCard: some View {
        VStack(alignment: .leading, spacing: AP.Space.space16) {
            FeatureStateView(
                tone: Self.signedOutTone,
                title: signInCard.title,
                message: signInCard.message
            )
            if let authError = model.authError {
                Text(authError)
                    .font(AP.Font.caption.weight(.semibold))
                    .foregroundStyle(AP.Color.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Sign-in failed. \(authError)")
            }
            AppleSignInButton()
            if let error = appleSignIn.error {
                Text(error)
                    .font(AP.Font.caption.weight(.semibold))
                    .foregroundStyle(AP.Color.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Sign-in failed. \(error)")
            }
            GoogleSignInButton()
            Button { showsEmailSignIn = true } label: {
                Text("Sign in with email")
                    .frame(maxWidth: .infinity, minHeight: AP.HitTarget.minimum)
                    .contentShape(Rectangle())
            }
            .buttonStyle(APSecondaryButtonStyle())
            .disabled(model.isAuthenticating)
            .accessibilityIdentifier(PaywallAccessibilityID.signInEmail)
            .accessibilityLabel("Sign in with email")
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Actions

    private func openSubscriptionManagement() {
        guard let url = SubscriptionManagement.appStoreSubscriptionsURL else { return }
        openURL(url)
    }

    /// Sign in with Apple, on the shared secondary control so the three providers line up.
    private func AppleSignInButton() -> some View {
        ContinueWithAppleButton(isAuthenticating: appleSignIn.isAuthenticating) {
            Task { _ = await appleSignIn.signIn() }
        }
        .accessibilityIdentifier(AppleSignInCopy.identifier)
    }

    private func GoogleSignInButton() -> some View {
        ContinueWithGoogleButton(isAuthenticating: model.isAuthenticating) { model.signIn() }
    }
}

// MARK: - Shared account chrome

/// Section header ("Profile", "Premium"): small, upper-case, secondary — never a bordered badge.
private struct AccountSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: AP.Space.space8) {
            Text(title.uppercased())
                .font(AP.Font.caption.weight(.semibold))
                .foregroundStyle(AP.Color.secondaryText)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }
}

/// One grouped, raised card. Rows are separated by insets, so the group reads as a single object —
/// exactly what boards 10-05/10-09 draw.
private struct AccountCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) { content() }
            .background(
                RoundedRectangle(cornerRadius: AP.Radius.radius24, style: .continuous)
                    .fill(AP.Color.surface)
            )
            .apElevation(.e1, cornerRadius: AP.Radius.radius24)
            .accessibilityElement(children: .contain)
    }
}

private struct AccountCardSeparator: View {
    var body: some View {
        Rectangle()
            .fill(AP.Color.separator)
            .frame(height: 1)
            .padding(.horizontal, AP.Space.space16)
            .accessibilityHidden(true)
    }
}

/// Label on the left, value on the right; at the Accessibility sizes the value wraps onto its own
/// line instead of truncating (TC-ACC-018).
private struct AccountValueRow: View {
    let title: String
    let value: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AP.Space.space4) {
                    label
                    valueText(.leading)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: AP.Space.space12) {
                    label
                    valueText(.trailing)
                }
            }
        }
        .padding(.horizontal, AP.Space.space16)
        .padding(.vertical, AP.Space.space16)
        .frame(maxWidth: .infinity, minHeight: AP.HitTarget.minimum, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
    }

    private var label: some View {
        Text(title)
            .font(AP.Font.heading)
            .foregroundStyle(AP.Color.primaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func valueText(_ alignment: TextAlignment) -> some View {
        Text(value)
            .font(AP.Font.body)
            .foregroundStyle(AP.Color.secondaryText)
            .multilineTextAlignment(alignment)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }
}

private enum AccountRowTrailing {
    case none
    case chevron
    case external
}

/// A tappable row: 40 pt icon tile, title, an optional second line, and one trailing affordance.
private struct AccountActionRow: View {
    let systemImage: String
    let title: String
    var subtitle: String? = nil
    /// Identifier for the second line, when QA has to read it (`account.delete.reason`).
    var subtitleIdentifier: String? = nil
    let tint: Color
    var isEnabled: Bool = true
    var trailing: AccountRowTrailing = .chevron

    var body: some View {
        HStack(alignment: .center, spacing: AP.Space.space12) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isEnabled ? AP.Color.primaryText : AP.Color.disabled)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: AP.Radius.radius8, style: .continuous)
                        .fill(AP.Color.controlFill)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AP.Space.space4) {
                Text(title)
                    .font(AP.Font.heading)
                    .foregroundStyle(tint)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(AP.Font.caption)
                        .foregroundStyle(AP.Color.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .apIdentifier(subtitleIdentifier)
                }
            }
            Spacer(minLength: AP.Space.space8)
            trailingView
        }
        .padding(.horizontal, AP.Space.space16)
        .padding(.vertical, AP.Space.space12)
        .frame(maxWidth: .infinity, minHeight: AP.HitTarget.minimum, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var trailingView: some View {
        switch trailing {
        case .none:
            EmptyView()
        case .chevron:
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AP.Color.secondaryText)
                .accessibilityHidden(true)
        case .external:
            Image(systemName: "arrow.up.forward.square")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AP.Color.secondaryText)
                .accessibilityHidden(true)
        }
    }
}

/// A grouped card of flat placeholder rows, matching `AccountSkeletonRow`'s geometry.
private struct AccountSkeletonCard: View {
    let rows: Int

    var body: some View {
        AccountCard {
            ForEach(0..<max(rows, 1), id: \.self) { index in
                if index > 0 { AccountCardSeparator() }
                HStack(spacing: AP.Space.space12) {
                    APSkeletonBar(width: 96)
                    Spacer(minLength: AP.Space.space8)
                    APSkeletonBar(width: 120)
                }
                .padding(.horizontal, AP.Space.space16)
                .padding(.vertical, AP.Space.space16)
            }
        }
        .accessibilityHidden(true)
    }
}
