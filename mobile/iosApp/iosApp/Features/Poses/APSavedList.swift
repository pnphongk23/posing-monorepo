// Saved poses (artboards `06-saved-*`): the AP row list. The account/session gate stays in
// `SavedPosesScreen`; this file owns how the collection is drawn.

import Kingfisher
import SwiftUI

/// Entering Saved means the saved collection: select it and load it, whatever panel is showing.
/// A signed-in screen that only switched the filter for a *loaded* list left an empty Community model
/// on "no saved poses" without ever asking the server.
@MainActor
enum APSavedEntry {
    static func prepare(model: PosesViewModel) async {
        model.filter = .saved
        await model.load()
    }
}

/// Copy for the unsave failure banner. The model owns the attempt; this only turns its error into a
/// banner a person can read and dismiss.
enum APSavedChrome {
    struct Banner: Equatable {
        let title: String
        let message: String
        let actionTitle: String
    }

    static func unsaveFailure(_ error: String?) -> Banner? {
        guard let error, !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return Banner(
            title: "Couldn't update this pose",
            message: error,
            actionTitle: "Dismiss"
        )
    }
}

/// The signed-in Saved surface: entering it loads the saved collection, and an unsave failure is
/// reported above whatever panel is showing. One container for every branch, so a panel that is not
/// the row list cannot lose the entry load or the error banner.
@MainActor
struct APSavedSurface<Content: View>: View {
    @ObservedObject var model: PosesViewModel
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            // Entering Saved always means the saved collection: select it and load it, whatever the
            // panel currently shows (an empty Community model must not freeze on "no saved poses"
            // without ever asking the server).
            .task { await APSavedEntry.prepare(model: model) }
            // F5: a failed unsave is a bottom snackbar, above the list's own footer.
            .apSnackbar(
                APSavedChrome.unsaveFailure(model.bookmarkError)?.message,
                tone: .error,
                actionTitle: APSavedChrome.unsaveFailure(model.bookmarkError)?.actionTitle,
                action: { model.bookmarkError = nil },
                onDismiss: { model.bookmarkError = nil }
            )
    }
}

/// The count under the Saved title ("5 poses" in the artboard), singular and plural.
enum SavedCountCopy {
    static func label(_ count: Int) -> String {
        count == 1 ? "1 pose" : "\(count) poses"
    }
}

/// Identifiers the saved rows keep from the shared grid they replaced, so the E2E lane's existing
/// selectors still find a row.
enum APSavedIdentifiers {
    static func row(index: Int, poseID: String) -> String {
        index == 0 ? "poses.first-card" : "poses.card.\(poseID)"
    }
}

/// One saved pose row: 64 pt thumbnail, name + category, trailing unsave control.
///
/// The row is a link to the pose detail; the unsave control is its own button so a tap on the
/// bookmark never opens the pose.
struct APSavedPoseRow: View {
    let pose: NativePose
    var isUnsaving: Bool = false
    var isEnabled: Bool = true
    var onUnsave: () -> Void = {}

    var body: some View {
        HStack(spacing: AP.Space.space12) {
            thumbnail
            VStack(alignment: .leading, spacing: AP.Space.space4) {
                Text(pose.name)
                    .font(AP.Font.heading)
                    .foregroundStyle(AP.Color.primaryText)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if !pose.category.isEmpty {
                    Text(pose.category)
                        .font(AP.Font.supporting)
                        .foregroundStyle(AP.Color.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            unsaveButton
        }
        .padding(.horizontal, AP.Space.space12)
        .padding(.vertical, AP.Space.space12)
        .contentShape(Rectangle())
    }

    private var thumbnail: some View {
        KFImage(pose.imageURL)
            .placeholder {
                RoundedRectangle(cornerRadius: AP.Radius.radius8, style: .continuous)
                    .fill(AP.Color.controlFill)
            }
            .resizable()
            .scaledToFill()
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: AP.Radius.radius8, style: .continuous))
            .accessibilityHidden(true)
    }

    private var unsaveButton: some View {
        Button(action: onUnsave) {
            Image(systemName: "bookmark.slash")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isEnabled ? AP.Color.selectedForeground : AP.Color.secondaryText)
                .frame(width: AP.HitTarget.minimum, height: AP.HitTarget.minimum)
                .background(
                    RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                        .fill(isEnabled ? AP.Color.selectedBackground : AP.Color.controlFill)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isUnsaving)
        .accessibilityLabel("Remove from saved")
    }
}

/// The saved collection: one raised `surface` card of rows separated by hairlines, then the paged
/// footer (`06-saved-populated`).
@MainActor
struct APSavedList: View {
    let poses: [NativePose]
    @ObservedObject var model: PosesViewModel
    var onTryPose: (CameraPoseRequest) -> Void = { _ in }
    var onNearEnd: (() -> Void)?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(poses.enumerated()), id: \.element.id) { index, pose in
                    row(for: pose, index: index)
                    if index < poses.count - 1 {
                        Rectangle()
                            .fill(AP.Color.separator)
                            .frame(height: 1)
                            .padding(.leading, 88)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .background(AP.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous))
            .apElevation(.e1, cornerRadius: AP.Radius.radius16)
            .padding(.horizontal, AP.Space.space16)
            APPagingFooter(model: model, bottomInset: APGridLayout.dockClearance)
        }
    }

    private func row(for pose: NativePose, index: Int) -> some View {
        NavigationLink(
            destination: PoseDetailScreen(pose: pose, model: model, onTryPose: onTryPose)
        ) {
            APSavedPoseRow(
                pose: pose,
                isUnsaving: model.isBookmarkInFlight(pose.id),
                isEnabled: model.canSave(pose) && model.bookmarkService != nil,
                onUnsave: { Task { await model.toggleSaved(for: pose.withSavedValue(true)) } }
            )
        }
        .buttonStyle(.plain)
        // The list used to be the shared grid, so its identifiers stay for the E2E lane.
        .accessibilityIdentifier(APSavedIdentifiers.row(index: index, poseID: pose.id))
        .onAppear {
            guard index >= poses.count - 4 else { return }
            onNearEnd?()
        }
    }
}

/// Saved loading skeleton (artboard `06-saved-loading`): flat rows where the card will be.
struct APSavedListSkeleton: View {
    var rows: Int = 5

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { index in
                HStack(spacing: AP.Space.space12) {
                    APSkeletonBar(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: AP.Space.space8) {
                        APSkeletonBar(width: 160)
                        APSkeletonBar(width: 96, height: 10)
                    }
                    Spacer(minLength: 0)
                    APSkeletonBar(width: 44, height: 44)
                }
                .padding(AP.Space.space12)
                if index < rows - 1 {
                    Rectangle()
                        .fill(AP.Color.separator)
                        .frame(height: 1)
                        .padding(.leading, 88)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(AP.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous))
        .apElevation(.e1, cornerRadius: AP.Radius.radius16)
        .padding(.horizontal, AP.Space.space16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading saved poses")
    }
}

extension NativePose {
    /// A copy with the saved flag set: the bookmark toggle sends the target state, not the delta.
    func withSavedValue(_ saved: Bool) -> NativePose {
        var copy = self
        copy.isSaved = saved
        return copy
    }
}
