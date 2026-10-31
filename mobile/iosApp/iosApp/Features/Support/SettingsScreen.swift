import AVFoundation
import SwiftUI
import UIKit

// MARK: - Settings

struct SettingsScreen: View {
    let posesModel: PosesViewModel
    var onTryPose: (CameraPoseRequest) -> Void = { _ in }
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appearance = APAppearanceStore.shared
    @State private var showsAboutSheet = false
    @State private var showsReplayOnboarding = false
    /// FEAT-011 placement: the user-initiated upgrade entry point (no crowns, no automatic paywall
    /// on a free surface).
    @State private var showsPaywall = false
    @State private var cameraAccess: CameraAccessStatus = .unknown

    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "42"

    var body: some View {
        VStack(spacing: 0) {
            APPageHeader(title: "Settings", onBack: { dismiss() })
            settingsContent
        }
        .background(AIPoseColor.background)
        .neoHiddenNavigationBar()
    }

    @ViewBuilder private var settingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AIPoseSpacing.xl) {
                appearanceGroup
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

    /// F7: the header's theme toggle moved here. Writes the one appearance preference the app reads.
    private var appearanceGroup: some View {
        settingsGroup(title: "Appearance") {
            ForEach(APAppearance.allCases) { option in
                Button { appearance.appearance = option } label: {
                    SupportSettingsRow(
                        icon: option == .system ? "circle.lefthalf.filled" : (option == .light ? "sun.max" : "moon"),
                        iconColor: AIPoseColor.primary,
                        title: option.title,
                        description: "",
                        trailing: appearance.appearance == option ? .check : .none
                    )
                }
                .buttonStyle(.plain)
                // Selection is carried by the trait and the checkmark, not by a word.
                .accessibilityAddTraits(appearance.appearance == option ? .isSelected : [])
                .accessibilityIdentifier("settings.appearance.\(option.rawValue)")
            }
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

// MARK: - Shared support components

private enum SupportSettingsTrailing {
    case chevron, external, status(String, Color), value(String)
    /// A selection row: a checkmark on the chosen option, never a chevron.
    case check
    /// No indicator at all (the unselected options of a selection row).
    case none
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
        case .none:
            EmptyView()
        case .check:
            Image(systemName: "checkmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(AIPoseColor.primary900)
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
