// Pose detail (artboards `04-pose-detail-*`): the AP-styled pieces of the pushed detail screen. The
// behaviour (bookmark semantics, camera route, confirmation) stays in `PoseDetailScreen`.

import SwiftUI

/// Copy the detail screen renders. Kept here so the screen, the unavailable panel and the tests read
/// the same strings.
enum PoseDetailCopy {
    static let howToPose = "How to pose"
    static let save = "Save pose"
    static let saved = "Saved"
    static let savedBanner = "Saved to your list"
    static let tryPose = "Try this pose"
    static let unavailableTitle = "This pose isn't available"
    static let unavailableMessage = "We couldn't load it right now. It may also have been removed."
    static let retry = "Retry"
    static let backToPoses = "Back to poses"
    static let back = "Back"
    static let heroLoading = "Loading pose photo"
    static let heroUnavailable = "Pose photo unavailable"
}

/// The tags shown under the title. The catalogue carries one category per pose, so the chip row is
/// that category (trimmed, never blank) — the artboard's three chips are sample data, not three
/// different fields.
enum PoseDetailTags {
    static func chips(for pose: NativePose) -> [String] {
        let category = pose.category.trimmingCharacters(in: .whitespacesAndNewlines)
        return category.isEmpty ? [] : [category]
    }

    /// Step text: the artboard numbers the steps with a badge, so the row itself carries no "1.".
    static func stepText(_ instruction: String) -> String {
        instruction.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// One tag chip: `controlFill`, radius 16, 44 pt tall so it is a real target.
struct APTagChip: View {
    let title: String

    var body: some View {
        Text(title)
            .font(AP.Font.supporting)
            .foregroundStyle(AP.Color.primaryText)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, AP.Space.space12)
            .frame(minHeight: AP.HitTarget.minimum)
            .background(
                RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                    .fill(AP.Color.controlFill)
            )
    }
}

/// A numbered instruction: the pink badge carries the number, the text is body copy.
struct APNumberedStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: AP.Space.space12) {
            Text("\(number)")
                .font(AP.Font.caption.weight(.semibold))
                .foregroundStyle(AP.Color.selectedForeground)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: AP.Radius.radius8, style: .continuous)
                        .fill(AP.Color.selectedBackground)
                )
                .accessibilityHidden(true)
            Text(text)
                .font(AP.Font.body)
                .foregroundStyle(AP.Color.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number). \(text)")
    }
}

/// Detail loading skeleton (artboard `04-pose-detail-loading`): flat `controlFill` blocks where the
/// title, tags, controls and steps will be. Static under Reduce Motion, like every AP skeleton.
struct APPoseDetailSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AP.Space.space16) {
            APSkeletonBar(width: 200, height: 28)
            HStack(spacing: AP.Space.space8) {
                APSkeletonBar(width: 84, height: 36)
                APSkeletonBar(width: 84, height: 36)
                APSkeletonBar(width: 64, height: 36)
            }
            APSkeletonBar(height: 44)
            APSkeletonBar(height: 12)
            APSkeletonBar(width: 260, height: 12)
        }
        .padding(.horizontal, AP.Space.space16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PoseDetailCopy.heroLoading)
    }
}
