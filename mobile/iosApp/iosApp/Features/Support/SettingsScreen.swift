import AVFoundation
import SwiftUI
import UIKit

// MARK: - Settings

/// The Settings hub (board 10-01 / 10-02 / 10-03 / 10-04).
///
/// Board order is the screen's order: the identity card (or the sign-in card) first, then LIBRARY,
/// then APPEARANCE, then HELP. Every row is local except the identity card, which reads the same
/// `AccountSessionModel` the Account screen uses — so a failed or slow read degrades the card into a
/// neutral, still-tappable row instead of taking the hub down (TC-SET-017).
///
/// The board has no Camera section: the grid, the guide colour and the pose strip stay camera-side
/// controls, and the app has no haptics model at all, so a hub section for them would be a control
/// that does nothing. The Privacy group is gone for the same reason it exists on no board — the
/// legal documents moved into About, and camera permission is surfaced by the camera's own state.
struct SettingsScreen: View {
    let posesModel: PosesViewModel
    var onTryPose: (CameraPoseRequest) -> Void = { _ in }
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appearance = APAppearanceStore.shared
    @State private var showsAboutSheet = false
    @State private var showsReplayOnboarding = false
    /// FEAT-011 placement: the user-initiated upgrade entry point (no crowns, no automatic paywall
    /// on a free surface).
    @State private var showsPaywall = false
    /// Session presence decides whether the hub opens with an identity or with a sign-in card.
    @StateObject private var session = SessionPresenceModel()
    /// The identity the card shows. Same model, same rules as the Account screen: it never invents a
    /// name or an address.
    @StateObject private var account = AccountSessionModel(connectivity: NWPathAccountConnectivity())
    /// The plan badge, read from the live provider the capture gate reads. Never a fake "Active".
    @StateObject private var premium = PremiumGateModel()

    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "42"
    /// The name this build ships under (`CFBundleDisplayName`), so the hub's copy and About cannot
    /// disagree with the app the user installed.
    private let appName = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? "posing"

    var body: some View {
        VStack(spacing: 0) {
            APPageHeader(
                title: "Settings",
                backIdentifier: "settings.back",
                titleIdentifier: "settings.title",
                onBack: { dismiss() }
            )
            ScrollView {
                VStack(alignment: .leading, spacing: AP.Space.space24) {
                    identityEntry
                    librarySection
                    appearanceSection
                    helpSection
                }
                .padding(.horizontal, AP.Space.space16)
                .padding(.top, AP.Space.space8)
                .padding(.bottom, AP.Space.space32)
            }
        }
        .background(AP.Color.background)
        .neoHiddenNavigationBar()
        .sheet(isPresented: $showsAboutSheet) {
            AboutSheet(appName: appName, appVersion: appVersion, buildNumber: buildNumber)
        }
        .fullScreenCover(isPresented: $showsReplayOnboarding) {
            OnboardingScreen { showsReplayOnboarding = false }
        }
        // Its own host: two sheets on one view is where SwiftUI's presentation gets flaky, and About
        // already owns the outer one.
        .sheet(isPresented: $showsPaywall) { PaywallScreen() }
        .task {
            session.start()
            account.start()
            premium.start()
        }
        .onDisappear { account.stop() }
    }

    // MARK: - Identity entry (profile card / sign-in card / neutral row)

    @ViewBuilder private var identityEntry: some View {
        // Accounts switched off: nothing advertises an identity the build cannot show (TC-ACC-020).
        if AppConfig.shared.isAccountFeatureEnabled {
            if case .signedIn(let summary) = account.state {
                profileCard(summary)
            } else if session.isSignedIn {
                // Signed in, but the read is still running or failed: the very same row, neutral and
                // still a way into Account, rather than a stale name or a second error panel.
                neutralAccountRow
            } else if session.isResolved {
                signInCard
            }
        }
    }

    private func profileCard(_ summary: AccountSummary) -> some View {
        let name = summary.displayName.isEmpty ? "Account" : summary.displayName
        // An email-provider account can carry its address as the display name (the server falls back
        // to it), so the line is not repeated under itself.
        let email = account.identity.email.flatMap { $0 == name ? nil : $0 }
        return SettingsCard {
            NavigationLink(destination: AccountScreen(posesModel: posesModel, onTryPose: onTryPose)) {
                HStack(spacing: AP.Space.space12) {
                    avatar(initials: AccountAvatar.initials(for: summary.displayName), diameter: 56)
                    VStack(alignment: .leading, spacing: AP.Space.space4) {
                        Text(name)
                            .font(AP.Font.heading)
                            .foregroundStyle(AP.Color.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        if let email {
                            Text(email)
                                .font(AP.Font.supporting)
                                .foregroundStyle(AP.Color.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: AP.Space.space8)
                    SettingsChevron()
                }
                .padding(AP.Space.space16)
                .frame(maxWidth: .infinity, minHeight: AP.HitTarget.minimum, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "Account, \(name)\(email.map { ", \($0)" } ?? ""). Opens account details"
            )
            .accessibilityIdentifier("settings.account.row")
        }
        // The card itself carries the element QA reads; the link inside it keeps the long-standing
        // tap target (`settings.account.row`), so both names are addressable on one control tree.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.accountCard")
    }

    /// The card's F4 degradation: no stale identity, still one tap from Account.
    private var neutralAccountRow: some View {
        SettingsCard {
            NavigationLink(destination: AccountScreen(posesModel: posesModel, onTryPose: onTryPose)) {
                HStack(spacing: AP.Space.space12) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(AP.Color.secondaryText)
                        .frame(width: 56, height: 56)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: AP.Space.space4) {
                        Text("Account")
                            .font(AP.Font.heading)
                            .foregroundStyle(AP.Color.primaryText)
                        Text("Account details unavailable right now.")
                            .font(AP.Font.supporting)
                            .foregroundStyle(AP.Color.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("settings.accountCard.state")
                    }
                    Spacer(minLength: AP.Space.space8)
                    SettingsChevron()
                }
                .padding(AP.Space.space16)
                .frame(maxWidth: .infinity, minHeight: AP.HitTarget.minimum, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Account. Details unavailable right now. Opens account details")
            .accessibilityIdentifier("settings.account.row")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.accountCard")
    }

    /// Signed out: one card that says what signing in is for, and the way in.
    private var signInCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: AP.Space.space12) {
                Text(SettingsHub.signInTitle(appName: appName))
                    .font(AP.Font.heading)
                    .foregroundStyle(AP.Color.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(SettingsHub.signInMessage)
                    .font(AP.Font.supporting)
                    .foregroundStyle(AP.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                NavigationLink(destination: AccountScreen(posesModel: posesModel, onTryPose: onTryPose)) {
                    Text("Sign in")
                }
                .buttonStyle(APPrimaryButtonStyle())
                .accessibilityLabel("Sign in")
                // The hub's Account entry keeps its long-standing id: every sign-in flow reaches the
                // Account screen through this control.
                .accessibilityIdentifier("settings.account.row")
            }
            .padding(AP.Space.space16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("settings.signIn.card")
        }
    }

    // MARK: - Library

    private var librarySection: some View {
        SettingsSection(title: "Library") {
            SettingsCard {
                NavigationLink(destination: SavedPosesScreen(model: posesModel, onTryPose: onTryPose)) {
                    SettingsRow(
                        systemImage: "bookmark",
                        title: "Saved",
                        // Signed out the row promises nothing: it says where Saved lives.
                        value: SettingsHub.savedValue(isSignedIn: session.isSignedIn)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(session.isSignedIn ? "Open Saved poses" : "Saved poses. Sign in to view")
                .accessibilityIdentifier("settings.saved.row")

                // The paywall kill switch stays a real rollback: no row, no surface.
                if AppConfig.shared.isPaywallEnabled {
                    SettingsCardSeparator()
                    premiumRow
                }
            }
        }
    }

    private var premiumRow: some View {
        let status = AccountPremiumStatus.resolve(
            entitlement: premium.entitlement,
            isSignedIn: session.isSignedIn
        )
        return Button { showsPaywall = true } label: {
            SettingsRow(
                systemImage: "sparkles",
                title: "Premium",
                value: status.badge == nil ? status.planValue : nil,
                badge: status.badge
            )
            .accessibilityElement(children: .contain)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(SettingsHub.premiumLabel(status))
        .accessibilityIdentifier("settings.premium.row")
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        SettingsSection(title: "Appearance") {
            VStack(alignment: .leading, spacing: AP.Space.space8) {
                SettingsSegmentedControl(
                    options: APAppearance.allCases,
                    selection: appearance.appearance,
                    title: { $0.title },
                    identifier: { "settings.appearance.\($0.rawValue)" },
                    select: { appearance.appearance = $0 }
                )
                // The caption explains System, so it is only true while System is the choice
                // (TC-SET-008: it must not claim to follow the phone under Light or Dark).
                if let caption = SettingsHub.appearanceCaption(for: appearance.appearance) {
                    Text(caption)
                        .font(AP.Font.caption)
                        .foregroundStyle(AP.Color.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, AP.Space.space4)
                }
            }
        }
    }

    // MARK: - Help

    private var helpSection: some View {
        SettingsSection(title: "Help") {
            SettingsCard {
                Button { showsReplayOnboarding = true } label: {
                    SettingsRow(systemImage: "arrow.counterclockwise", title: "Replay onboarding")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Replay onboarding guide")
                .accessibilityIdentifier("settings.replayOnboarding")

                SettingsCardSeparator()

                Button { showsAboutSheet = true } label: {
                    SettingsRow(
                        systemImage: "info.circle",
                        title: "About",
                        value: "Version \(appVersion) (\(buildNumber))"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("About \(appName), version \(appVersion) build \(buildNumber)")
                .accessibilityIdentifier("settings.about")
            }
        }
    }

    // MARK: - Helpers

    private func avatar(initials: String, diameter: CGFloat) -> some View {
        ZStack {
            Circle().fill(AP.Color.accent)
            if initials.isEmpty {
                Image(systemName: "person.fill")
                    .font(.system(size: diameter * 0.32, weight: .semibold))
                    .foregroundStyle(AP.Color.onAccent)
            } else {
                Text(initials)
                    .font(AP.Font.title)
                    .foregroundStyle(AP.Color.onAccent)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

/// The hub's pure rules: the copy it may say and the rows it may show. Kept out of the view so each
/// rule is a table-driven test instead of something only reachable by looking at a screenshot.
enum SettingsHub {
    /// What signing in actually buys (board 10-02). Premium unlocks the shutter only, so the card
    /// promises Saved poses and Premium — no claim about anything else.
    static let signInMessage = "Keep your Saved poses with you and use Premium on every device."

    static func signInTitle(appName: String) -> String { "Sign in to \(appName)" }

    /// The System caption explains an option that is only *true* while System is the choice.
    static func appearanceCaption(for appearance: APAppearance) -> String? {
        appearance == .system ? "System follows your iPhone setting." : nil
    }

    /// Signed out, the Saved row says where Saved lives instead of promising something it cannot show.
    static func savedValue(isSignedIn: Bool) -> String? { isSignedIn ? nil : "Sign in to view" }

    /// VoiceOver's reading of the Premium row, which has to carry the same status the badge shows.
    static func premiumLabel(_ status: AccountPremiumStatus) -> String {
        switch status {
        case .active: return "Premium, active. Opens premium"
        case .notSubscribed: return "Premium, not subscribed. Opens premium"
        case .unknown: return "Premium. Opens premium"
        }
    }
}

/// Camera permission projection (`PA-015-06`).
///
/// The hub's "Camera access" status row is gone (it is on no board; camera permission is surfaced by
/// the camera's own blocked state), but the projection stays: it is the app's only
/// `AVCaptureDevice` status mapping and its copy/colour rules are covered by
/// `SupportDestinationsTests`.
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

// MARK: - Shared settings chrome

/// Upper-case section label ("LIBRARY", "APPEARANCE", "HELP"), secondary and small — no badge, no
/// count, no border.
private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

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

/// One grouped card: `surface` fill, E1 elevation, radius 24, rows separated by inset hairlines.
private struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) { content() }
            .background(
                RoundedRectangle(cornerRadius: AP.Radius.radius24, style: .continuous)
                    .fill(AP.Color.surface)
            )
            .apElevation(.e1, cornerRadius: AP.Radius.radius24)
    }
}

private struct SettingsCardSeparator: View {
    var body: some View {
        Rectangle()
            .fill(AP.Color.separator)
            .frame(height: 1)
            .padding(.horizontal, AP.Space.space16)
            .accessibilityHidden(true)
    }
}

private struct SettingsChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(AP.Color.secondaryText)
            .accessibilityHidden(true)
    }
}

/// A hub row: 40 pt neutral icon tile, title, and at most one trailing reading (a value, an `Active`
/// badge, or the chevron).
private struct SettingsRow: View {
    let systemImage: String
    let title: String
    var value: String? = nil
    var badge: String? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: AP.Space.space12) {
            icon
            VStack(alignment: .leading, spacing: AP.Space.space4) {
                titleText
                // At the Accessibility sizes the reading (value or badge) drops under the title instead
                // of squeezing it into a truncated column; the chevron always stays on the trailing
                // edge, which is how board 10-04 draws the rows.
                if dynamicTypeSize.isAccessibilitySize, hasReading {
                    reading
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, AP.Space.space4)
                }
            }
            Spacer(minLength: AP.Space.space8)
            if !dynamicTypeSize.isAccessibilitySize, hasReading {
                reading
            }
            SettingsChevron()
        }
        .padding(.horizontal, AP.Space.space16)
        .padding(.vertical, AP.Space.space16)
        .frame(maxWidth: .infinity, minHeight: AP.HitTarget.minimum, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var icon: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(AP.Color.primaryText)
            .frame(width: 40, height: 40)
            .background(
                RoundedRectangle(cornerRadius: AP.Radius.radius8, style: .continuous)
                    .fill(AP.Color.controlFill)
            )
            .accessibilityHidden(true)
    }

    private var titleText: some View {
        Text(title)
            .font(AP.Font.heading)
            .foregroundStyle(AP.Color.primaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var hasReading: Bool { badge != nil || value != nil }

    /// The one reading a row may carry: the `Active` badge, or a supporting value ("Sign in to view").
    @ViewBuilder private var reading: some View {
        if let badge {
            HStack(spacing: AP.Space.space4) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                Text(badge)
                    .font(AP.Font.caption.weight(.semibold))
            }
            .foregroundStyle(AP.Color.primaryText)
            .padding(.horizontal, AP.Space.space8)
            .padding(.vertical, AP.Space.space4)
            .background(
                Capsule().fill(AP.Color.successSurface)
            )
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("settings.premium.status")
        } else if let value {
            Text(value)
                .font(AP.Font.supporting)
                .foregroundStyle(AP.Color.secondaryText)
                // Inline it reads on the trailing edge; under the title (AX sizes) it reads from the
                // leading edge like the title above it.
                .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                .frame(
                    maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil,
                    alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing
                )
                .fixedSize(horizontal: false, vertical: true)
                .apIdentifier(title == "Premium" ? "settings.premium.status" : nil)
        }
    }
}

/// System / Light / Dark as one control, the way board 10-01 draws it: a `controlFill` track, the
/// chosen option in `selectedBackground` with its ink colour and a check.
///
/// The selection is carried by three signals — the fill, the checkmark and an `accessibilityValue`
/// ("Selected" / "Not selected") — because Maestro cannot read the `.isSelected` trait (TC-SET-007).
private struct SettingsSegmentedControl<Option: Hashable>: View {
    let options: [Option]
    let selection: Option
    let title: (Option) -> String
    let identifier: (Option) -> String
    let select: (Option) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: AP.Space.space4) { segments }
            } else {
                HStack(spacing: AP.Space.space4) { segments }
            }
        }
        .padding(AP.Space.space4)
        .background(
            RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                .fill(AP.Color.controlFill)
        )
    }

    private var segments: some View {
        ForEach(Array(options.enumerated()), id: \.offset) { _, option in
            let isSelected = option == selection
            Button { select(option) } label: {
                HStack(spacing: AP.Space.space4) {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                    }
                    Text(title(option))
                        .font(isSelected ? AP.Font.heading : AP.Font.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(isSelected ? AP.Color.selectedForeground : AP.Color.secondaryText)
                .frame(maxWidth: .infinity, minHeight: AP.HitTarget.minimum)
                .background(
                    RoundedRectangle(cornerRadius: AP.Radius.radius8 * 1.5, style: .continuous)
                        .fill(isSelected ? AP.Color.selectedBackground : Color.clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
            .accessibilityIdentifier(identifier(option))
        }
    }
}

// MARK: - About

/// About as a sheet with a header and an X (board 10-12 / 10-13).
///
/// The board's fourth row, "Contact support", is deliberately not built: the product has no Support
/// row anywhere, and this sheet is not the place to reintroduce one. The legal documents that used to
/// live in a Privacy group on the hub live here instead.
struct AboutSheet: View {
    let appName: String
    let appVersion: String
    let buildNumber: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showsLicences = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The header stays put; the body scrolls, because at the Accessibility sizes the rows are
            // taller than a medium-detent sheet and used to overlap each other.
            header
                .padding(.horizontal, AP.Space.space16)
                .padding(.top, AP.Space.space24)
                .padding(.bottom, AP.Space.space16)
            ScrollView {
                VStack(alignment: .leading, spacing: AP.Space.space24) {
                    appSummary
                    SettingsCard {
                        externalRow("Terms of Use", systemImage: "doc.text", identifier: "about.terms",
                                    url: SupportDestinations.termsOfServiceURL)
                        SettingsCardSeparator()
                        externalRow("Privacy Policy", systemImage: "shield", identifier: "about.privacy",
                                    url: SupportDestinations.privacyPolicyURL)
                        SettingsCardSeparator()
                        Button { showsLicences = true } label: {
                            SettingsRow(systemImage: "doc.on.doc", title: "Open-source licences")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open-source licences")
                        .accessibilityIdentifier("about.licences")
                    }
                    Text("© 2026 \(appName)")
                        .font(AP.Font.caption)
                        .foregroundStyle(AP.Color.secondaryText)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, AP.Space.space16)
                .padding(.bottom, AP.Space.space24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AP.Color.background)
        .sheet(isPresented: $showsLicences) {
            OpenSourceLicencesSheet(openURL: { openURL($0) })
        }
        // The sheet body used to reach the accessibility tree as nothing at all (QA flow could only see
        // the Close control). `.contain` publishes the title/version/rows as their own elements inside
        // a modal container.
        .accessibilityElement(children: .contain)
        .supportSheetPresentation()
        .accessibilityAddTraits(.isModal)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: AP.Space.space12) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AP.Color.primaryText)
                    .frame(width: AP.HitTarget.minimum, height: AP.HitTarget.minimum)
                    .background(
                        RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                            .fill(AP.Color.controlFill)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close About \(appName)")
            .accessibilityIdentifier("about.close")
            Text("About")
                .font(AP.Font.title)
                .foregroundStyle(AP.Color.primaryText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("about.title")
            Spacer(minLength: 0)
        }
    }

    private var appSummary: some View {
        HStack(spacing: AP.Space.space16) {
            ZStack {
                RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                    .fill(AP.Color.accent)
                Image(systemName: "camera.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(AP.Color.onAccent)
            }
            .frame(width: 64, height: 64)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AP.Space.space4) {
                Text(appName)
                    .font(AP.Font.heading)
                    .foregroundStyle(AP.Color.primaryText)
                Text("Version \(appVersion) (\(buildNumber))")
                    .font(AP.Font.supporting)
                    .foregroundStyle(AP.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("about.version")
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
    }

    private func externalRow(
        _ title: String,
        systemImage: String,
        identifier: String,
        url: URL?
    ) -> some View {
        Button { if let url { openURL(url) } } label: {
            HStack(spacing: AP.Space.space12) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AP.Color.primaryText)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: AP.Radius.radius8, style: .continuous)
                            .fill(AP.Color.controlFill)
                    )
                    .accessibilityHidden(true)
                Text(title)
                    .font(AP.Font.heading)
                    .foregroundStyle(AP.Color.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: AP.Space.space8)
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AP.Color.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, AP.Space.space16)
            .padding(.vertical, AP.Space.space12)
            .frame(maxWidth: .infinity, minHeight: AP.HitTarget.minimum, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), opens in browser")
        .accessibilityIdentifier(identifier)
    }
}

/// One licence entry: the dependency, the licence it publishes, and where that licence is published.
struct OpenSourceLicence: Identifiable, Equatable {
    let name: String
    let licence: String
    let urlString: String

    var id: String { name }
    var url: URL? { URL(string: urlString) }

    /// The SwiftPM dependencies `project.yml` links, each with the licence its own repository
    /// publishes. Hand-kept on purpose: reading a generated manifest would need a build step, and a
    /// wrong entry here is visible and testable, while a missing one is not.
    static let all: [OpenSourceLicence] = [
        OpenSourceLicence(
            name: "Firebase iOS SDK",
            licence: "Apache License 2.0",
            urlString: "https://github.com/firebase/firebase-ios-sdk/blob/master/LICENSE"
        ),
        OpenSourceLicence(
            name: "RevenueCat purchases-ios",
            licence: "MIT License",
            urlString: "https://github.com/RevenueCat/purchases-ios/blob/main/LICENSE"
        ),
        OpenSourceLicence(
            name: "GRDB.swift",
            licence: "MIT License",
            urlString: "https://github.com/groue/GRDB.swift/blob/master/LICENSE"
        ),
        OpenSourceLicence(
            name: "Kingfisher",
            licence: "MIT License",
            urlString: "https://github.com/onevcat/Kingfisher/blob/master/LICENSE"
        )
    ]
}

/// The in-app licence list the About sheet opens (board 10-12 draws the row; the content is the real
/// dependency set rather than a placeholder page).
struct OpenSourceLicencesSheet: View {
    var licences: [OpenSourceLicence] = OpenSourceLicence.all
    let openURL: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: AP.Space.space16) {
            HStack(alignment: .center, spacing: AP.Space.space12) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AP.Color.primaryText)
                        .frame(width: AP.HitTarget.minimum, height: AP.HitTarget.minimum)
                        .background(
                            RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                                .fill(AP.Color.controlFill)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close open-source licences")
                .accessibilityIdentifier("licences.close")
                Text("Open-source licences")
                    .font(AP.Font.title)
                    .foregroundStyle(AP.Color.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
            }
            ScrollView {
                VStack(spacing: AP.Space.space8) {
                    ForEach(licences) { licence in
                        SettingsCard {
                            Button { if let url = licence.url { openURL(url) } } label: {
                                HStack(spacing: AP.Space.space12) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(AP.Color.primaryText)
                                        .frame(width: 40, height: 40)
                                        .background(
                                            RoundedRectangle(cornerRadius: AP.Radius.radius8, style: .continuous)
                                                .fill(AP.Color.controlFill)
                                        )
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: AP.Space.space4) {
                                        Text(licence.name)
                                            .font(AP.Font.heading)
                                            .foregroundStyle(AP.Color.primaryText)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text(licence.licence)
                                            .font(AP.Font.supporting)
                                            .foregroundStyle(AP.Color.secondaryText)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: AP.Space.space8)
                                    Image(systemName: "arrow.up.forward.square")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(AP.Color.secondaryText)
                                        .accessibilityHidden(true)
                                }
                                .padding(.horizontal, AP.Space.space16)
                                .padding(.vertical, AP.Space.space12)
                                .frame(maxWidth: .infinity, minHeight: AP.HitTarget.minimum, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(licence.name), \(licence.licence), opens in browser")
                        }
                    }
                }
            }
        }
        .padding(.horizontal, AP.Space.space16)
        .padding(.top, AP.Space.space24)
        .background(AP.Color.background)
        .accessibilityElement(children: .contain)
        .supportSheetPresentation()
        .accessibilityAddTraits(.isModal)
    }
}

private extension View {
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
