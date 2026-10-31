// The labelled "More" menu from `01-nav-map`: Add pose, Jobs and Saved behind one 44 pt header
// control, so the Poses header keeps three actions instead of five.

import SwiftUI

struct APMoreMenu: View {
    /// Jobs actively processing, shown as the pink badge on the Jobs row.
    var jobsActiveCount: Int = 0
    var isSignedIn: Bool = false
    /// Add pose is off until the extract feature is enabled; the row says so and disables itself.
    var isAddPoseEnabled: Bool = true
    var isJobsEnabled: Bool = true
    /// The account feature flag gates the Saved entry, exactly as it gated the header link.
    var savedDestination: AnyView?
    /// `nil` lets the card take the full available width (the AX sizes, where 296 pt would clip).
    var maxWidth: CGFloat? = 296
    var onAddPose: () -> Void = {}
    var onJobs: () -> Void = {}
    var onSavedTapped: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("MORE")
                .font(AP.Font.caption.weight(.semibold))
                .kerning(0.7)
                .foregroundStyle(AP.Color.secondaryText)
                .padding(.horizontal, AP.Space.space16)
                .padding(.top, AP.Space.space12)
                .padding(.bottom, AP.Space.space8)

            addPoseRow
            separator
            jobsRow
            if let savedDestination {
                separator
                savedRow(destination: savedDestination)
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
    }

    private var addPoseRow: some View {
        Button(action: onAddPose) {
            row(
                systemImage: "plus.circle",
                title: "Add pose",
                subtitle: isAddPoseEnabled ? "Publish a new pose" : "Turned off while we review",
                isEnabled: isAddPoseEnabled,
                trailing: { lockIcon(isVisible: !isAddPoseEnabled) }
            )
        }
        .buttonStyle(.plain)
        .disabled(!isAddPoseEnabled)
        .accessibilityLabel("Add pose")
        .accessibilityHint(isAddPoseEnabled ? "" : "Turned off while we review")
        .accessibilityIdentifier("poses.add-pose")
    }

    private var jobsRow: some View {
        let badge = isSignedIn ? jobsActiveCount : 0
        return Button(action: onJobs) {
            row(
                systemImage: "hourglass",
                title: "Jobs",
                subtitle: badge > 0 ? "\(badge) running" : "Processing and finished poses",
                isEnabled: isJobsEnabled,
                trailing: { jobsBadge(count: badge) }
            )
        }
        .buttonStyle(.plain)
        .disabled(!isJobsEnabled)
        .accessibilityLabel("Jobs\(badge > 0 ? ", \(badge) active" : "")")
        .accessibilityIdentifier("poses.jobs")
    }

    private func savedRow(destination: AnyView) -> some View {
        NavigationLink(destination: destination) {
            row(
                systemImage: "bookmark",
                title: "Saved",
                subtitle: "Your saved poses",
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
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AP.Space.space4) {
                Text(title)
                    .font(AP.Font.heading)
                    .foregroundStyle(isEnabled ? AP.Color.primaryText : AP.Color.disabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(AP.Font.caption)
                    .foregroundStyle(AP.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
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
            .padding(.leading, AP.Space.space48)
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
