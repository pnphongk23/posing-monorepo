// The labelled "More" menu from `01-nav-map`: Add pose, Jobs and Saved behind one 44 pt header
// control, so the Poses header keeps three actions instead of five.

import SwiftUI

struct APMoreMenu: View {
    @State private var isSpinning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Jobs actively processing, shown as the pink badge on the Jobs row.
    var jobsActiveCount: Int = 0
    var isSignedIn: Bool = false
    var isJobsEnabled: Bool = true
    /// The account feature flag gates the Saved entry, exactly as it gated the header link.
    var savedDestination: AnyView?
    /// Settings opens the existing Account/Settings screen (F8: the gear row).
    var settingsDestination: AnyView?
    /// `nil` lets the card take the full available width (the AX sizes, where 296 pt would clip).
    var maxWidth: CGFloat? = 296
    var onJobs: () -> Void = {}
    var onSavedTapped: () -> Void = {}
    var onSettingsTapped: () -> Void = {}

    private var rows: [APMoreMenuRowSpec] {
        APMoreMenuSpec.rows(
            showsSaved: savedDestination != nil,
            showsSettings: settingsDestination != nil
        )
    }

    private var shouldSpinJobsIcon: Bool {
        !reduceMotion && jobsActiveCount > 0 && isSpinning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            jobsRow
            if rows.contains(where: { $0.title == "Saved" }), let savedDestination {
                separator
                savedRow(destination: savedDestination)
            }
            if rows.contains(where: { $0.title == "Settings" }), let settingsDestination {
                separator
                settingsRow(destination: settingsDestination)
            }
        }
        // 296 pt on a 390 pt screen, and it shrinks instead of overflowing on a 320 pt one; at the AX
        // sizes the caller passes `nil` so the card uses the whole width and its rows can wrap.
        .frame(
            minWidth: maxWidth == nil ? 0 : 280,
            idealWidth: maxWidth ?? 0,
            maxWidth: maxWidth ?? .infinity,
            alignment: .leading
        )
        .background(
            RoundedRectangle(cornerRadius: AP.Radius.radius24, style: .continuous)
                .fill(AP.Color.surface)
        )
        .apElevation(.e1, cornerRadius: AP.Radius.radius24)
        .accessibilityElement(children: .contain)
        .onAppear { isSpinning = true }
    }

    private var jobsRow: some View {
        let badge = isSignedIn ? jobsActiveCount : 0
        return Button(action: onJobs) {
            row(
                systemImage: "arrow.triangle.2.circlepath",
                title: "Jobs",
                subtitle: "",
                isEnabled: isJobsEnabled,
                trailing: {
                    HStack(spacing: AP.Space.space8) {
                        jobsBadge(count: badge)
                        chevronIcon
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .disabled(!isJobsEnabled)
        .accessibilityLabel("Jobs\(badge > 0 ? ", \(badge) active" : "")")
        .accessibilityIdentifier("poses.jobs")
    }

    private func settingsRow(destination: AnyView) -> some View {
        NavigationLink(destination: destination) {
            row(
                systemImage: "gearshape",
                title: "Settings",
                subtitle: "",
                isEnabled: true,
                trailing: { chevronIcon }
            )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded(onSettingsTapped))
        .accessibilityLabel("Open Settings")
        .accessibilityIdentifier("poses.menu.settings")
    }

    private func savedRow(destination: AnyView) -> some View {
        NavigationLink(destination: destination) {
            row(
                systemImage: "bookmark",
                title: "Saved",
                subtitle: "",
                isEnabled: true,
                trailing: { chevronIcon }
            )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded(onSavedTapped))
        .accessibilityLabel("Open Saved poses")
        .accessibilityIdentifier("poses.header.saved")
    }

    private func row<Trailing: View>(
        systemImage: String,
        title: String,
        subtitle: String,
        isEnabled: Bool,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: AP.Space.space12) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isEnabled ? AP.Color.primaryText : AP.Color.disabled)
                .frame(width: 24)
                .rotationEffect(.degrees(title == "Jobs" && shouldSpinJobsIcon ? 360 : 0))
                .animation(
                    title == "Jobs" && shouldSpinJobsIcon
                        ? .linear(duration: 1).repeatForever(autoreverses: false)
                        : nil,
                    value: shouldSpinJobsIcon
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AP.Space.space4) {
                Text(title)
                    .font(AP.Font.heading)
                    .foregroundStyle(isEnabled ? AP.Color.primaryText : AP.Color.disabled)
                    .fixedSize(horizontal: false, vertical: true)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(AP.Font.caption)
                        .foregroundStyle(AP.Color.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: AP.Space.space8)
            trailing()
        }
        .padding(AP.Space.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var separator: some View {
        Rectangle()
            .fill(AP.Color.separator)
            .frame(height: 1)
            .padding(.horizontal, AP.Space.space16)
    }

    private func lockIcon(isVisible: Bool) -> some View {
        Image(systemName: "lock")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(AP.Color.secondaryText)
            .opacity(isVisible ? 1 : 0)
            .accessibilityHidden(true)
    }

    private func jobsBadge(count: Int) -> some View {
        Text("\(count)")
            .font(AP.Font.caption.weight(.semibold))
            .foregroundStyle(AP.Color.onAccent)
            .padding(.horizontal, AP.Space.space8)
            .padding(.vertical, 2)
            .background(Capsule().fill(AP.Color.accent))
            .opacity(count > 0 ? 1 : 0)
            .accessibilityHidden(true)
    }

    private var chevronIcon: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(AP.Color.secondaryText)
            .accessibilityHidden(true)
    }
}
