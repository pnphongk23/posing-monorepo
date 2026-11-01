// Saved poses (artboards `06-saved-*`): the AP row list. The account/session gate stays in
// `SavedPosesScreen`; this file owns how the collection is drawn.

import Kingfisher
import Network
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

// MARK: - Board copy (artboards `06-board04` … `06-board09`)

/// Every user-visible string the Saved surface adds, in one place so the boards and the code cannot
/// drift. Pure: the views below read these instead of hardcoding copy.
enum APSavedStateCopy {
    // Removal + Undo (`06-board04`)
    static let undoActionTitle = "Undo"
    static let dismissActionTitle = "Dismiss"
    static func removedMessage(_ poseName: String) -> String {
        let trimmed = poseName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Removed pose" : "Removed \(trimmed)"
    }

    // Offline (`06-board07`)
    static let offlineBanner = "You're offline. Changes will sync when you're back online."
    static let notSavedOffline = "Not saved offline"

    // Signed out (`06-board05`): reachable without ever having signed in, so the copy never says
    // "again" (BUG-261029-03) and never implies the collection is lost — it syncs.
    static let signInTitle = "Sign in to see saved poses"
    static let signInMessage = "Your saved poses sync across your devices."
    static let signInActionTitle = "Sign in"
    static let signInGlyph = "person"

    // Empty (`06-board06`)
    static let emptyTitle = "No saved poses yet"
    static let emptyMessage = "Tap Save on any pose to keep it here."
    static let emptyActionTitle = "Browse poses"
    static let emptyGlyph = "bookmark"

    // Failed load (`06-board09`)
    static let loadFailureTitle = "Couldn't load saved poses"
    static let retryActionTitle = "Try again"
    static let loadFailureGlyph = "exclamationmark.triangle"

    /// `We couldn't reach your account (error 503). Your saved poses are safe.` The status code is
    /// printed only when the screen actually knows it; the reassurance holds either way, because a
    /// failed load never touches the saved collection.
    static func loadFailureMessage(statusCode: Int?) -> String {
        guard let statusCode else {
            return "We couldn't reach your account. Your saved poses are safe."
        }
        return "We couldn't reach your account (error \(statusCode)). Your saved poses are safe."
    }
}

// MARK: - The removal snackbar (F5 placement, `06-board04`)

/// What the bottom snackbar says after a bookmark attempt. Pure, so the state machine (offer Undo,
/// retry it, report a failure) is assertable without a screen.
struct APSavedSnackbarSpec: Equatable {
    enum Kind: Equatable {
        /// The removal can still be undone: the action sends the save again.
        case undo
        /// Nothing to undo: the action only takes the message away.
        case dismiss
    }

    let message: String
    let tone: APStateTone
    let actionTitle: String
    let kind: Kind
}

enum APSavedSnackbarRule {
    /// - Parameters:
    ///   - removedPoseName: the pose that just left the collection, if an Undo is still on offer.
    ///   - canUndo: `false` when the pose can no longer be saved (the server reported it gone), so the
    ///     bar does not offer an action that cannot work.
    ///   - failure: the model's copy for the last failed attempt — already the truth about what
    ///     happened, so it is never replaced by a generic line here.
    static func resolve(
        removedPoseName: String?,
        canUndo: Bool,
        failure: String?
    ) -> APSavedSnackbarSpec? {
        if let failure, !failure.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // A failed Undo keeps its offer: the copy tells the person to try again, so the action that
            // can try again has to stay. Only a pose that cannot be saved loses it.
            return APSavedSnackbarSpec(
                message: failure,
                tone: .error,
                actionTitle: removedPoseName != nil && canUndo
                    ? APSavedStateCopy.undoActionTitle
                    : APSavedStateCopy.dismissActionTitle,
                kind: removedPoseName != nil && canUndo ? .undo : .dismiss
            )
        }
        guard let removedPoseName else { return nil }
        return APSavedSnackbarSpec(
            message: APSavedStateCopy.removedMessage(removedPoseName),
            tone: .success,
            actionTitle: APSavedStateCopy.undoActionTitle,
            kind: canUndo ? .undo : .dismiss
        )
    }
}

/// Which outcomes earn an Undo offer. One rule, so the row's tap and its tests cannot disagree:
/// only a **server-confirmed** removal leaves a row that Undo could put back.
enum APSavedUndoRule {
    static func offersUndo(for outcome: PosesViewModel.BookmarkOutcome) -> Bool {
        outcome == .saved(false)
    }
}

/// Holds the one removal that can still be undone and performs it against the server.
///
/// The offer is **Account state**: it names a pose that left this Account's saved collection, so the
/// controller adopts the session scope and drops the offer on a sign-out or an account switch — the
/// next Account's screen must never offer to re-save the previous Account's row.
///
/// An offer is only ever made for a server-confirmed unsave: a failed attempt never left the
/// collection, so offering to put the row back would describe something that did not happen.
@MainActor
final class APSavedUndo: ObservableObject, SessionScoped {
    struct Removal: Equatable {
        let pose: NativePose
        /// The position the row had, so Undo restores the list instead of appending a duplicate.
        let index: Int
    }

    @Published private(set) var removal: Removal?
    /// One restore at a time: a second tap on Undo while the first request is out is ignored.
    @Published private(set) var isRestoring = false

    private let scope: SessionScope?

    /// - Parameter boundary: the session boundary to follow. `nil` keeps a directly constructed
    ///   controller session-agnostic (the surfaces and tests that do not own a boundary).
    init(boundary: SessionBoundary? = ServiceLocator.sessionBoundary) {
        let scope = boundary.map { SessionScope.of($0) }
        self.scope = scope
        // Held weakly by the scope, so a surface that is rebuilt does not leak its controller.
        scope?.adopt(self)
    }

    /// A session change ends the offer: nothing of the previous Account may be re-saved for the next.
    func resetForSessionChange(_ event: SessionEvent) {
        removal = nil
        isRestoring = false
    }

    func offer(_ pose: NativePose, at index: Int) {
        removal = Removal(pose: pose, index: index)
    }

    /// The snackbar timed out or was tapped away.
    func dismiss() {
        removal = nil
    }

    /// Puts the pose back through the real bookmark service.
    ///
    /// - Returns: `true` only when the server confirmed the save *and* the row is back where it was.
    ///   A failure leaves the collection exactly as the server has it (the pose is not saved), keeps
    ///   the offer so the retry the copy asks for is possible, and leaves the truthful message in
    ///   `model.bookmarkError` — the surface's snackbar is built from that.
    @discardableResult
    func undo(in model: PosesViewModel) async -> Bool {
        guard let removal, !isRestoring else { return false }
        isRestoring = true
        defer { isRestoring = false }
        // `toggleSaved` reads the shared state (false right after the confirmed unsave), so this is a
        // real save request — never a local flip.
        let outcome = await model.toggleSaved(for: removal.pose.withSavedValue(true))
        switch outcome {
        case .saved(true):
            APSavedRowRestore.restore(removal.pose, at: removal.index, in: model)
            self.removal = nil
            return true
        case .failed:
            // The truth is already in `model.bookmarkError` and the collection still matches the
            // server; the offer stays so the retry the copy asks for is possible.
            return false
        case .saved(false), .unavailable, .inFlight, .discarded:
            // No service, another request for this pose, or a session change: nothing was saved here,
            // and there is nothing truthful to add to the collection.
            self.removal = nil
            return false
        }
    }
}

/// Puts a server-confirmed row back into the saved collection.
///
/// The model records the confirmed save (`savedOverrides`), but the row was removed from the list by
/// the unsave, so the list needs it back at the position it had. Undo is a rare, user-initiated
/// action on one row: re-reading the whole first window would also drop every page behind it and
/// flash the skeleton, which is a larger change to the screen than restoring one confirmed row.
@MainActor
enum APSavedRowRestore {
    static func restore(_ pose: NativePose, at index: Int, in model: PosesViewModel) {
        let restored = pose.withSavedValue(true)
        switch model.state {
        case .loaded(var rows):
            guard !rows.contains(where: { $0.id == restored.id }) else { return }
            rows.insert(restored, at: min(max(index, 0), rows.count))
            model.state = .loaded(rows)
        case .empty:
            model.state = .loaded([restored])
        case .idle, .loading, .failed:
            // A list that is being replaced (or that never loaded) owns its own answer; adding a row
            // to it would paint a result the screen is not showing.
            return
        }
    }
}

/// The signed-in Saved surface: entering it loads the saved collection, the offline banner sits
/// above whatever panel is showing, and a removal/failure is reported in the bottom snackbar. One
/// container for every branch, so a panel that is not the row list cannot lose the entry load, the
/// offline banner or the Undo offer.
@MainActor
struct APSavedSurface<Content: View>: View {
    @ObservedObject var model: PosesViewModel
    @ViewBuilder var content: () -> Content

    @StateObject private var undo = APSavedUndo()
    @StateObject private var offline: APSavedOfflineModel

    init(
        model: PosesViewModel,
        offline: APSavedOfflineModel? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.model = model
        self.content = content
        _offline = StateObject(wrappedValue: offline ?? APSavedOfflineModel())
    }

    var body: some View {
        VStack(spacing: 0) {
            // F5-style chrome above the rows, directly under the header (`06-board07`).
            if offline.mode.isOffline {
                APOfflineBanner(message: APSavedStateCopy.offlineBanner)
                    .padding(.horizontal, AP.Space.space16)
                    .padding(.bottom, AP.Space.space12)
                    .accessibilityIdentifier("saved.offlineBanner")
            }
            content()
        }
        // Entering Saved always means the saved collection: select it and load it, whatever the
        // panel currently shows (an empty Community model must not freeze on "no saved poses"
        // without ever asking the server).
        .task {
            await APSavedEntry.prepare(model: model)
            #if DEBUG
            applyOfflineFixtureIfRequested()
            #endif
        }
        .onAppear { offline.start() }
        .onDisappear { offline.stop() }
        .environment(\.apSavedUndo, undo)
        .environment(\.apSavedOfflineMode, offline.mode)
        // F5: the snackbar is the bottom inset, above the dock and above the list's own footer.
        .apSnackbar(
            snackbar?.message,
            tone: snackbar?.tone ?? .error,
            actionTitle: snackbar?.actionTitle,
            action: { perform(snackbar) },
            onDismiss: {
                model.bookmarkError = nil
                undo.dismiss()
            }
        )
    }

    private var snackbar: APSavedSnackbarSpec? {
        APSavedSnackbarRule.resolve(
            removedPoseName: undo.removal?.pose.name,
            canUndo: undo.removal.map { model.canSave($0.pose) } ?? false,
            failure: model.bookmarkError
        )
    }

    private func perform(_ spec: APSavedSnackbarSpec?) {
        guard let spec else { return }
        switch spec.kind {
        case .undo:
            Task { await undo.undo(in: model) }
        case .dismiss:
            model.bookmarkError = nil
        }
    }

    #if DEBUG
    /// Evidence runs only (`-AIPoseSavedOfflineFixture N`): renders the offline board with its first
    /// N rows available so the banner and the "Not saved offline" rows can be captured on a device
    /// whose network cannot be switched off. Compiled out of Release, exactly like the paging fixture.
    private func applyOfflineFixtureIfRequested() {
        guard let cachedRowCount = APSavedOfflineFixture.cachedRowCount else { return }
        guard case .loaded(let rows) = model.state else { return }
        offline.applyFixture(
            isOffline: true,
            cachedPoseIDs: Set(rows.prefix(cachedRowCount).map(\.id))
        )
    }
    #endif
}

// MARK: - Offline rows (`06-board07`)

/// What this device can show without a network.
struct APSavedOfflineMode: Equatable {
    /// Reachability reports no network.
    var isOffline: Bool = false
    /// Pose ids the offline catalog actually holds on disk. A saved row outside this set cannot be
    /// opened offline, so the board labels it "Not saved offline" instead of pretending.
    var cachedPoseIDs: Set<String> = []

    static let online = APSavedOfflineMode()

    /// Online, every saved row is available. Offline, only what the cache can serve is.
    func isAvailableOffline(_ pose: NativePose) -> Bool {
        !isOffline || cachedPoseIDs.contains(pose.id)
    }
}

/// Which saved poses the device holds for offline use. One call, answered by the catalog on disk.
protocol APSavedOfflineIndex: Sendable {
    func cachedPoseIDs() async -> Set<String>
}

/// The real index: the rows the pose catalog (`Pose` table, catalog buckets only) holds, which is
/// what an offline read of the saved route is built from. No row here means the pose's data is not
/// on this device, so there is nothing to show behind the label.
struct APCachedPoseIndex: APSavedOfflineIndex {
    static let catalog = APCachedPoseIndex()

    func cachedPoseIDs() async -> Set<String> {
        guard let repository = PoseCatalogDatabase.repository else { return [] }
        guard let rows = try? await repository.cached() else { return [] }
        return Set(rows.map(\.poseId))
    }
}

/// Reachability + the offline catalog, as the Saved surface needs them.
///
/// Mirrors the camera picker's monitor lifecycle: `NWPathMonitor.cancel()` is terminal, so a fresh
/// monitor is created for each presentation and a stale "offline" cannot outlive the screen.
@MainActor
final class APSavedOfflineModel: ObservableObject {
    @Published private(set) var mode: APSavedOfflineMode

    private let index: any APSavedOfflineIndex
    private let monitorsConnectivity: Bool
    private var pathMonitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "aipose.saved.path")
    /// The last value the monitor itself reported, kept apart from `mode` so a fixture (DEBUG) cannot
    /// be cleared by a repeated path update, and a repeated reading is a no-op.
    private var lastReportedOffline = false

    init(
        index: any APSavedOfflineIndex = APCachedPoseIndex.catalog,
        mode: APSavedOfflineMode = .online,
        monitorsConnectivity: Bool = true
    ) {
        self.index = index
        self.mode = mode
        self.monitorsConnectivity = monitorsConnectivity
    }

    deinit {
        pathMonitor?.cancel()
    }

    func start() {
        guard monitorsConnectivity, pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let isOffline = path.status != .satisfied
            Task { @MainActor [weak self] in
                self?.setOffline(isOffline)
            }
        }
        pathMonitor = monitor
        monitor.start(queue: monitorQueue)
    }

    /// Stop monitoring and forget the last reading, so a stale banner cannot outlive the screen.
    func stop() {
        pathMonitor?.cancel()
        pathMonitor = nil
        lastReportedOffline = false
        mode = .online
    }

    /// Reads the catalog when connectivity drops: what the cache holds *at that moment* is the only
    /// fact that decides whether a row can be opened without a network.
    private func setOffline(_ isOffline: Bool) {
        guard lastReportedOffline != isOffline else { return }
        lastReportedOffline = isOffline
        mode.isOffline = isOffline
        mode.cachedPoseIDs = []
        guard isOffline else { return }
        Task { [weak self] in
            guard let self else { return }
            let ids = await self.index.cachedPoseIDs()
            guard self.mode.isOffline else { return }
            self.mode.cachedPoseIDs = ids
        }
    }

    #if DEBUG
    func applyFixture(isOffline: Bool, cachedPoseIDs: Set<String>) {
        mode = APSavedOfflineMode(isOffline: isOffline, cachedPoseIDs: cachedPoseIDs)
    }
    #endif
}

private struct APSavedUndoKey: EnvironmentKey {
    static let defaultValue: APSavedUndo? = nil
}

private struct APSavedOfflineModeKey: EnvironmentKey {
    static let defaultValue = APSavedOfflineMode.online
}

extension EnvironmentValues {
    /// The removal offer of the enclosing `APSavedSurface`, or `nil` outside one (previews, tests that
    /// mount the rows alone).
    var apSavedUndo: APSavedUndo? {
        get { self[APSavedUndoKey.self] }
        set { self[APSavedUndoKey.self] = newValue }
    }

    /// The device's offline reading for the enclosing Saved surface.
    var apSavedOfflineMode: APSavedOfflineMode {
        get { self[APSavedOfflineModeKey.self] }
        set { self[APSavedOfflineModeKey.self] = newValue }
    }
}

#if DEBUG
/// Evidence-run seam for the offline board (`06-board07`), which otherwise needs a device whose
/// network can be switched off mid-list. Release builds contain neither the flag nor the lookup.
enum APSavedOfflineFixture {
    static let flag = "-AIPoseSavedOfflineFixture"

    /// How many of the loaded rows the fixture treats as available offline.
    static var cachedRowCount: Int? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: flag),
              arguments.indices.contains(flagIndex + 1),
              let count = Int(arguments[flagIndex + 1]) else { return nil }
        return max(0, count)
    }
}
#endif

/// When the Saved rows ask for the next page (F6).
///
/// The rows are the trigger, but `LazyVStack` recycles them: every one of the last four rows
/// appears — and re-appears each time it scrolls back into view — so a raw `onAppear` asked four
/// times for the same page and only the model's in-flight guard kept that to one request. This gate
/// keys an *opportunity* on the paging state instead: one page is one ask, and a page that settles
/// (landed, failed or discarded) re-arms for the next one.
///
/// A failed page is not an opportunity: F6 gives that decision to the footer's compact retry, so a
/// row must never re-ask on its own and turn one failure into a retry loop.
@MainActor
enum APNearEndRule {
    /// Rows from the end of the list that ask for the next page.
    static let lookahead = 4

    static func isNearEnd(index: Int, count: Int) -> Bool {
        guard count > 0, index >= 0 else { return false }
        return index >= count - lookahead
    }

    /// Identity of one paging opportunity: the cursor the next window starts at, plus how many
    /// attempts have settled. Both move when a page lands or is dropped, so the same rows
    /// re-appearing inside one page cannot ask twice.
    static func opportunity(nextOffset: Int, completedAttempts: Int) -> String {
        "\(nextOffset)#\(completedAttempts)"
    }

    /// - Parameter canPage: `false` while the last attempt failed (`paging.error != nil`). The list
    ///   keeps its rows and the footer offers Retry; nothing asks again behind the user's back.
    static func shouldTrigger(
        index: Int,
        count: Int,
        opportunity: String,
        lastOpportunity: String?,
        canPage: Bool
    ) -> Bool {
        guard canPage, isNearEnd(index: index, count: count) else { return false }
        return opportunity != lastOpportunity
    }
}

/// Identifiers the saved rows keep from the shared grid they replaced, so the E2E lane's existing
/// selectors still find a row.
enum APSavedIdentifiers {
    static func row(index: Int, poseID: String) -> String {
        index == 0 ? "poses.first-card" : "poses.card.\(poseID)"
    }
}

/// Copy for one saved row. Pure: the row, its accessibility text and the tests read the same rule.
enum APSavedRowCopy {
    /// The category line normally; the board's label when the device cannot show this pose offline.
    static func subtitle(for pose: NativePose, isAvailableOffline: Bool) -> String? {
        guard isAvailableOffline else { return APSavedStateCopy.notSavedOffline }
        let category = pose.category.trimmingCharacters(in: .whitespacesAndNewlines)
        return category.isEmpty ? nil : pose.category
    }
}

/// The row's one control scales with Dynamic Type (`06-board03`): 44 pt at the default sizes, the
/// board's ~64 pt tile at the Accessibility sizes.
enum APSavedRowMetrics {
    static func unsaveTileSide(for size: DynamicTypeSize) -> CGFloat {
        size.isAccessibilitySize ? 64 : AP.HitTarget.minimum
    }

    static func unsaveGlyphSize(for size: DynamicTypeSize) -> CGFloat {
        size.isAccessibilitySize ? 26 : 16
    }
}

/// One saved pose row: 64 pt thumbnail, name + category, trailing unsave control.
///
/// The row is a link to the pose detail; the unsave control is its own button next to that link (see
/// `APSavedRowLayout`), so a tap on the bookmark never opens the pose.
struct APSavedPoseRow: View {
    let pose: NativePose
    var isUnsaving: Bool = false
    var isEnabled: Bool = true
    /// `false` while offline for a pose whose data is not on the device (`06-board07`): the row is
    /// dimmed, its category line becomes "Not saved offline", and it offers no unsave request —
    /// nothing can be sent to a server the device cannot reach.
    var isAvailableOffline: Bool = true
    var onUnsave: () -> Void = {}

    var body: some View {
        APSavedRowLayout {
            APSavedPoseRowContent(pose: pose, isAvailableOffline: isAvailableOffline)
        } trailing: {
            APSavedUnsaveTile(
                isUnsaving: isUnsaving,
                isEnabled: isEnabled,
                isAvailableOffline: isAvailableOffline,
                onUnsave: onUnsave
            )
        }
    }
}

/// The chrome of a saved row: one row of two deliberately **separate hit areas** — the content that
/// opens the pose, and the unsave control.
///
/// They are siblings, never nested: a `Button` inside a `NavigationLink` label never receives the tap,
/// because the link owns the whole label's hit area. That is why the Saved tile rendered its enabled
/// style and did nothing at all: the open-the-pose link swallowed every tap on it.
struct APSavedRowLayout<Content: View, Trailing: View>: View {
    @ViewBuilder var content: () -> Content
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: AP.Space.space12) {
            content()
            trailing()
        }
        .padding(.horizontal, AP.Space.space12)
        .padding(.vertical, AP.Space.space12)
    }
}

/// What a row says about its pose: artwork, name and category line, as one area that can be wrapped in
/// the link that opens the pose.
struct APSavedPoseRowContent: View {
    let pose: NativePose
    /// `false` while offline for a pose the device does not hold: the artwork and the name dim.
    var isAvailableOffline: Bool = true

    var body: some View {
        HStack(spacing: AP.Space.space12) {
            thumbnail
            VStack(alignment: .leading, spacing: AP.Space.space4) {
                Text(pose.name)
                    .font(AP.Font.heading)
                    .foregroundStyle(isAvailableOffline ? AP.Color.primaryText : AP.Color.secondaryText)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle = APSavedRowCopy.subtitle(for: pose, isAvailableOffline: isAvailableOffline) {
                    Text(subtitle)
                        .font(AP.Font.supporting)
                        .foregroundStyle(AP.Color.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
            // The board fades the artwork of a pose that is not on the device.
            .opacity(isAvailableOffline ? 1 : 0.4)
            .accessibilityHidden(true)
    }
}

/// The row's trailing unsave control.
///
/// Its own view, so the Saved list can lay it out *beside* the link that opens the pose instead of
/// inside it: as a sibling the tile keeps its own hit area and the tap reaches it.
struct APSavedUnsaveTile: View {
    var isUnsaving: Bool = false
    var isEnabled: Bool = true
    var isAvailableOffline: Bool = true
    var onUnsave: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var offersUnsave: Bool { isEnabled && isAvailableOffline }

    private var unsaveTileSide: CGFloat { APSavedRowMetrics.unsaveTileSide(for: dynamicTypeSize) }

    var body: some View {
        Button(action: onUnsave) {
            Image(systemName: "bookmark.slash")
                .font(.system(size: APSavedRowMetrics.unsaveGlyphSize(for: dynamicTypeSize), weight: .semibold))
                .foregroundStyle(offersUnsave ? AP.Color.selectedForeground : AP.Color.secondaryText)
                .frame(width: unsaveTileSide, height: unsaveTileSide)
                .background(
                    RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                        .fill(offersUnsave ? AP.Color.selectedBackground : AP.Color.controlFill)
                )
        }
        .buttonStyle(.plain)
        .disabled(!offersUnsave || isUnsaving)
        .accessibilityLabel("Remove from saved")
        .accessibilityHint(isAvailableOffline ? "" : APSavedStateCopy.notSavedOffline)
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

    /// The last paging opportunity these rows asked for. Held by the list, not the row: the four
    /// near-end rows share one page, so they have to share one answer.
    @State private var lastNearEndOpportunity: String?
    @Environment(\.apSavedUndo) private var undo
    @Environment(\.apSavedOfflineMode) private var offlineMode

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
        // The link and the unsave tile are siblings, not a link wrapped around the whole row: a control
        // nested in a link's label never gets the tap, which left the tile dead on an enabled-looking
        // button and Undo without a producer on this surface.
        APSavedRowLayout {
            NavigationLink(
                destination: PoseDetailScreen(pose: pose, model: model, onTryPose: onTryPose)
            ) {
                APSavedPoseRowContent(
                    pose: pose,
                    isAvailableOffline: offlineMode.isAvailableOffline(pose)
                )
            }
            .buttonStyle(.plain)
            // The label's own shape is not filled, so the link needs the whole rect as its hit area
            // for the empty space beside the text to open the pose, as it did when it wrapped the row.
            .contentShape(Rectangle())
            // The list used to be the shared grid, so its identifiers stay for the E2E lane.
            .accessibilityIdentifier(APSavedIdentifiers.row(index: index, poseID: pose.id))
        } trailing: {
            APSavedUnsaveTile(
                isUnsaving: model.isBookmarkInFlight(pose.id),
                isEnabled: model.canSave(pose) && model.bookmarkService != nil,
                isAvailableOffline: offlineMode.isAvailableOffline(pose),
                onUnsave: { Task { await unsave(pose, at: index) } }
            )
        }
        .onAppear { requestNextPage(at: index) }
    }

    /// One unsave. The model owns the request; the surface only offers Undo for a removal the server
    /// actually confirmed.
    private func unsave(_ pose: NativePose, at index: Int) async {
        let outcome = await model.toggleSaved(for: pose.withSavedValue(true))
        guard APSavedUndoRule.offersUndo(for: outcome) else { return }
        undo?.offer(pose, at: index)
    }

    /// Ask for the next page at most once per page. `canPage` is deliberately only "the last
    /// attempt did not fail": the model's own guard owns `hasMore` and the auto-fetch budget, and a
    /// list with nothing owed answers the call with a no-op.
    private func requestNextPage(at index: Int) {
        guard onNearEnd != nil else { return }
        let opportunity = APNearEndRule.opportunity(
            nextOffset: model.paging.nextOffset,
            completedAttempts: model.paging.completedAttempts
        )
        guard APNearEndRule.shouldTrigger(
            index: index,
            count: poses.count,
            opportunity: opportunity,
            lastOpportunity: lastNearEndOpportunity,
            canPage: model.paging.error == nil
        ) else { return }
        lastNearEndOpportunity = opportunity
        onNearEnd?()
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

// MARK: - State panels (`06-board05` … `06-board09`)

/// The signed-out Saved gate: the person glyph and the sync promise, not a loss of data. The tap
/// opens the same sign-in prompt it always has (`SignInIntent.openSaved`).
struct APSavedSignInPanel: View {
    var onSignIn: () -> Void

    var body: some View {
        APEmptyStateView(
            title: APSavedStateCopy.signInTitle,
            message: APSavedStateCopy.signInMessage,
            actionTitle: APSavedStateCopy.signInActionTitle,
            action: onSignIn,
            style: .plain,
            glyph: APSavedStateCopy.signInGlyph
        )
        .accessibilityIdentifier("saved.signIn")
    }
}

/// An empty collection: the bookmark glyph and the one instruction that fills it.
struct APSavedEmptyPanel: View {
    var onBrowse: () -> Void

    var body: some View {
        APEmptyStateView(
            title: APSavedStateCopy.emptyTitle,
            message: APSavedStateCopy.emptyMessage,
            actionTitle: APSavedStateCopy.emptyActionTitle,
            action: onBrowse,
            style: .plain,
            glyph: APSavedStateCopy.emptyGlyph
        )
        .accessibilityIdentifier("saved.browseCommunity")
    }
}

/// A failed load. `statusCode` is the real HTTP status when the screen has one, so the copy can name
/// it exactly as the board does; without one the panel still says the true thing — the saved
/// collection is untouched by a failed read.
struct APSavedLoadFailurePanel: View {
    var statusCode: Int? = nil
    var retry: () -> Void

    var body: some View {
        APErrorStateView(
            title: APSavedStateCopy.loadFailureTitle,
            message: APSavedStateCopy.loadFailureMessage(statusCode: statusCode),
            retryTitle: APSavedStateCopy.retryActionTitle,
            retry: retry,
            style: .plain,
            glyph: APSavedStateCopy.loadFailureGlyph
        )
        .accessibilityIdentifier("saved.retry")
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
