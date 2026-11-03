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
    /// - Returns: the library filter the surface replaced, so leaving Saved can put it back. The filter
    ///   is the route the shared pose service reads by, and leaving it on `.saved` would route the next
    ///   Poses or camera-picker read to the saved collection.
    @discardableResult
    static func prepare(model: PosesViewModel) async -> PoseLibraryFilter {        let previous = model.filter
        model.filter = .saved
        await model.load()
        return previous
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
    /// The unsave control's value while its request is out: the second tap is ignored, so the control
    /// has to say why it is inert instead of looking enabled and doing nothing.
    static let unsaveInFlight = "In progress"

    /// The tap asked to remove a row that the server does not have saved, so the request saved it
    /// instead. Nothing left the collection and nothing failed — but silence is indistinguishable from
    /// a tap nobody received, so the bar says the removal did not happen.
    static let removeFailed = "Couldn't remove this pose."

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

extension APSavedSnackbarSpec {
    /// The bar is always `saved.snackbar`; only the reversible offer earns `saved.snackbar.undo`.
    /// A failure bar's action is a Dismiss, and a flow that tapped it through the Undo id would be
    /// asserting the wrong thing about the wrong bar.
    var identifiers: APSnackbarIdentifiers {
        APSnackbarIdentifiers(
            bar: APSnackbarIdentifiers.saved.bar,
            action: kind == .undo ? APSnackbarIdentifiers.saved.action : nil
        )
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

/// Puts the collection the Poses tab was showing back — but only when the surface is really gone.
///
/// `onDisappear` also fires when the screen is merely **covered** (a pose detail pushed from a row, the
/// sign-in sheet). Restoring then flipped the shared filter under a list that was still on screen: the Saved
/// rows stopped being filtered as saved, so a removal no longer left the list, and coming back reloaded the
/// collection and lost its paging cursor. A covered screen appears again and cancels this; a popped one does
/// not. One owner, so the timing rule is testable without a screen.
@MainActor
final class APSavedFilterRestore: ObservableObject {
    /// How long a disappearance has to last before it counts as teardown.
    let grace: TimeInterval
    private var task: Task<Void, Never>?

    init(grace: TimeInterval = 0.35) {
        self.grace = grace
    }

    deinit { task?.cancel() }

    /// Schedules the restore. `restore` runs only if nothing cancels it first.
    func schedule(_ restore: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(0, grace) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            restore()
        }
    }

    /// The surface is back: the disappearance was a cover, not teardown.
    func cancel() {
        task?.cancel()
        task = nil
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
    /// The filter this surface replaced with `.saved`, put back when it is really gone (see `APSavedEntry`).
    @State private var entryFilter: PoseLibraryFilter?
    /// The pending restore of `entryFilter`, cancelled by the next appearance.
    @StateObject private var filterRestore: APSavedFilterRestore
    /// The entry load runs once per mount, so a screen that was only *covered* (a pose detail pushed from
    /// a row, a sheet) comes back to the collection it had, with its rows and its paging cursor.
    @State private var didPrepare = false
    init(
        model: PosesViewModel,
        offline: APSavedOfflineModel? = nil,
        teardownGrace: TimeInterval = 0.35,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.model = model
        self.content = content
        _offline = StateObject(wrappedValue: offline ?? APSavedOfflineModel())
        _filterRestore = StateObject(wrappedValue: APSavedFilterRestore(grace: teardownGrace))
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
            // Once per mount. `.task` re-runs when a covered screen comes back, and reloading there would
            // throw away the rows and the paging cursor the person left behind.
            guard !didPrepare else { return }
            didPrepare = true
            // Captured before the surface forces `.saved`: this is the collection the Poses tab was
            // showing, and the one the surface puts back when it is really gone.
            if entryFilter == nil { entryFilter = model.filter }
            await APSavedEntry.prepare(model: model)
            #if DEBUG
            applyOfflineFixtureIfRequested()
            #endif
        }
        .onAppear {
            // Back (a detail popped, a sheet closed): the disappearance was a cover, not teardown.
            filterRestore.cancel()
            offline.start()
        }
        .onDisappear {
            offline.stop()
            scheduleFilterRestore()
        }
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
            },
            identifiers: snackbar?.identifiers
        )
    }

    /// Schedules the restore of the collection the Poses tab was showing (see `APSavedFilterRestore`).
    private func scheduleFilterRestore() {
        guard let entryFilter, model.filter == .saved else { return }
        filterRestore.schedule { [model] in
            guard model.filter == .saved else { return }
            model.filter = entryFilter
        }
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

    /// The row's unsave control, addressed per pose.
    ///
    /// The control's only other handle is its label ("Remove from saved"), which is identical on
    /// every row: a flow that taps it can never say *which* row it removed, so "the list lost the
    /// right row" and "the tap went to the wrong row" are the same report. The pose id is the pose's
    /// stable identity, so the id survives a reload or a reorder.
    static func unsave(poseID: String) -> String {
        "saved.unsave.\(poseID)"
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

/// What the row's unsave control is doing, as one value. The tile reads this instead of combining its
/// three flags in the body, so "the request is out" has a single definition the screen and its tests
/// can agree on.
enum APSavedUnsaveTileState: Equatable {
    /// The request can be sent from here.
    case idle
    /// A request for this pose is out: the tile shows it, and a second tap is ignored.
    case inFlight
    /// Nothing can be sent: offline for a pose the device does not hold, no bookmark service wired, or
    /// a pose the server already reported gone.
    case unavailable
}

/// One rule for the unsave tile: which state it is in, whether it takes a tap, what it announces and
/// whether it is allowed to move.
///
/// Why it exists: the tile was already disabled while the request was out, but it was painted exactly
/// like the enabled one. With a slow server that reads as "I tapped and nothing happened", and the
/// second tap the model correctly refused had no visible cause. The state is derived once, so the
/// pixels, the hit area and the accessibility value cannot drift apart.
enum APSavedUnsaveTileRule {
    /// In flight outranks the other inputs: the tap the person already made has to stay visible even if
    /// the row's own flags change under it.
    static func state(
        isUnsaving: Bool,
        isEnabled: Bool,
        isAvailableOffline: Bool
    ) -> APSavedUnsaveTileState {
        if isUnsaving { return .inFlight }
        return isEnabled && isAvailableOffline ? .idle : .unavailable
    }

    /// Only the resting tile takes a tap. The model refuses a second request for the same pose anyway;
    /// this is what turns that refusal into a state the screen shows.
    static func acceptsTap(_ state: APSavedUnsaveTileState) -> Bool {
        state == .idle
    }

    /// What assistive technology reads. The tile is also `disabled` while it works, so this is the part
    /// that says *why*; the accessible name stays "Remove from saved", which the flows tap by text.
    static func accessibilityValue(for state: APSavedUnsaveTileState) -> String {
        state == .inFlight ? APSavedStateCopy.unsaveInFlight : ""
    }

    /// A spinner is motion, so Reduce Motion gets the still tile: the muted fill, the disabled control
    /// and the accessibility value already carry the busy state.
    static func showsSpinner(_ state: APSavedUnsaveTileState, reduceMotion: Bool) -> Bool {
        state == .inFlight && !reduceMotion
    }
}

/// What one tap on a saved row's unsave control does, and what it therefore has to show.
///
/// Extracted from the row's closure so the tap can be driven in a test — a hosted SwiftUI view cannot
/// be tapped in this test host — and so the outcome table has one home. The surface's bar is built from
/// `undo.removal` and `model.bookmarkError`, so "make this outcome visible" is exactly "set one of
/// those two": a tap never ends in a state the person cannot see.
@MainActor
enum APSavedRowUnsave {
    /// The action the row's unsave tile is bound to: exactly the closure `APSavedUnsaveTile` hands to
    /// its `Button`, so a test can invoke it without a touch and prove the whole path (the tap → the
    /// model → the bookmark service) instead of only the model.
    static func action(
        _ pose: NativePose,
        at index: Int,
        in model: PosesViewModel,
        undo: APSavedUndo?
    ) -> () -> Void {
        { Task { await perform(pose, at: index, in: model, undo: undo) } }
    }

    /// - Returns: the model's answer, so a test can assert which path the tap took.
    @discardableResult
    static func perform(
        _ pose: NativePose,
        at index: Int,
        in model: PosesViewModel,
        undo: APSavedUndo?
    ) async -> PosesViewModel.BookmarkOutcome {
        let outcome = await model.toggleSaved(for: pose.withSavedValue(true))
        switch outcome {
        case .saved(false):
            // Server-confirmed removal: the row left and the bar offers to put it back
            // (`saved.snackbar` / `saved.snackbar.undo`). Whether an outcome earns that offer stays
            // `APSavedUndoRule`'s call — the one definition the tap and its tests share.
            if APSavedUndoRule.offersUndo(for: outcome) { undo?.offer(pose, at: index) }
        case .saved(true):
            // The row was not saved after all, so this request saved it instead of removing it. The
            // collection keeps the row and nothing failed, which used to be a completely silent tap.
            model.bookmarkError = APSavedStateCopy.removeFailed
        case .failed:
            // The model already published the reason in `bookmarkError`, which is the error bar.
            break
        case .inFlight:
            // Another request for this pose is out, and *that* request owns the visible outcome; a
            // second bar would describe the same attempt twice. Not reachable from one tap on a
            // resting tile: the claim puts the tile in `.inFlight`, which takes no tap.
            break
        case .discarded:
            // The session changed under the request, so this surface is being replaced (the sign-in
            // gate or a fresh load). Nothing truthful can be said about the previous Account's row.
            break
        case .unavailable:
            // No bookmark service is wired, so the tile is `.unavailable` and never sends the tap.
            break
        }
        return outcome
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
    /// `saved.unsave.<poseID>` for the row's own control.
    var unsaveIdentifier: String? = nil
    var onUnsave: () -> Void = {}

    var body: some View {
        APSavedRowLayout {
            APSavedPoseRowContent(pose: pose, isAvailableOffline: isAvailableOffline)
        } trailing: {
            APSavedUnsaveTile(
                isUnsaving: isUnsaving,
                isEnabled: isEnabled,
                isAvailableOffline: isAvailableOffline,
                identifier: unsaveIdentifier,
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
    /// `saved.unsave.<poseID>` when the row knows its pose; the label stays the accessible name.
    var identifier: String? = nil
    var onUnsave: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var state: APSavedUnsaveTileState {
        APSavedUnsaveTileRule.state(
            isUnsaving: isUnsaving,
            isEnabled: isEnabled,
            isAvailableOffline: isAvailableOffline
        )
    }

    private var unsaveTileSide: CGFloat { APSavedRowMetrics.unsaveTileSide(for: dynamicTypeSize) }

    /// The enabled tile is the accent one; every other state is the muted `controlFill`, so a tap that
    /// is waiting on the server never looks like a tap nobody received.
    private var tileFill: SwiftUI.Color {
        state == .idle ? AP.Color.selectedBackground : AP.Color.controlFill
    }

    private var markColor: SwiftUI.Color {
        switch state {
        case .idle: return AP.Color.selectedForeground
        case .inFlight: return AP.Color.disabled
        case .unavailable: return AP.Color.secondaryText
        }
    }

    var body: some View {
        Button(action: onUnsave) {
            ZStack {
                RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                    .fill(tileFill)
                mark
            }
            .frame(width: unsaveTileSide, height: unsaveTileSide)
        }
        .buttonStyle(.plain)
        .disabled(!APSavedUnsaveTileRule.acceptsTap(state))
        .accessibilityLabel("Remove from saved")
        .accessibilityValue(APSavedUnsaveTileRule.accessibilityValue(for: state))
        .accessibilityHint(isAvailableOffline ? "" : APSavedStateCopy.notSavedOffline)
        .apIdentifier(identifier)
    }

    /// The bookmark-slash while it can be tapped, the same glyph in the disabled colour while it
    /// cannot, and a spinner while the request is out (a still glyph under Reduce Motion).
    @ViewBuilder
    private var mark: some View {
        if APSavedUnsaveTileRule.showsSpinner(state, reduceMotion: reduceMotion) {
            ProgressView()
                .tint(AP.Color.secondaryText)
        } else {
            Image(systemName: "bookmark.slash")
                .font(.system(size: APSavedRowMetrics.unsaveGlyphSize(for: dynamicTypeSize), weight: .semibold))
                .foregroundStyle(markColor)
        }
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
                // `savedState` is part of "can this control act": a row the model does not hold as
                // saved cannot be removed, and offering the control would send the opposite request
                // (a save) that this surface has nothing to report.
                isUnsaving: model.isBookmarkInFlight(pose.id),
                isEnabled: model.canSave(pose)
                    && model.savedState(for: pose)
                    && model.bookmarkService != nil,
                isAvailableOffline: offlineMode.isAvailableOffline(pose),
                identifier: APSavedIdentifiers.unsave(poseID: pose.id),
                onUnsave: APSavedRowUnsave.action(pose, at: index, in: model, undo: undo)
            )
        }
        .onAppear { requestNextPage(at: index) }
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
/// The ids the Saved panels expose. Each addresses a **control**: a flow taps the id, and a tap on the panel
/// lands on its copy instead (measured on 1.1 (22): the panel's bounds were the whole screen area while the
/// button sat 60 pt below its centre). The container answers to `<id>.panel`.
enum APSavedPanelIdentifiers {
    static let browse = "saved.browseCommunity"
    static let retry = "saved.retry"

    static func panel(_ identifier: String) -> String { "\(identifier).panel" }
}

struct APSavedEmptyPanel: View {
    var onBrowse: () -> Void

    /// The ids this panel applies. One function the body and the tests read, so an id cannot quietly move
    /// back onto the container.
    var identifiers: (control: String, panel: String) {
        (APSavedPanelIdentifiers.browse, APSavedPanelIdentifiers.panel(APSavedPanelIdentifiers.browse))
    }

    var body: some View {
        APEmptyStateView(
            title: APSavedStateCopy.emptyTitle,
            message: APSavedStateCopy.emptyMessage,
            actionTitle: APSavedStateCopy.emptyActionTitle,
            action: onBrowse,
            style: .plain,
            glyph: APSavedStateCopy.emptyGlyph,
            // On the control, not on the panel (see `APSavedPanelIdentifiers`).
            actionIdentifier: identifiers.control
        )
        .accessibilityIdentifier(identifiers.panel)
    }
}

/// A failed load. `statusCode` is the real HTTP status when the screen has one, so the copy can name
/// it exactly as the board does; without one the panel still says the true thing — the saved
/// collection is untouched by a failed read.
struct APSavedLoadFailurePanel: View {
    var statusCode: Int? = nil
    var retry: () -> Void

    /// Same rule as the empty panel: `saved.retry` is the Try again control.
    var identifiers: (control: String, panel: String) {
        (APSavedPanelIdentifiers.retry, APSavedPanelIdentifiers.panel(APSavedPanelIdentifiers.retry))
    }

    var body: some View {
        APErrorStateView(
            title: APSavedStateCopy.loadFailureTitle,
            message: APSavedStateCopy.loadFailureMessage(statusCode: statusCode),
            retryTitle: APSavedStateCopy.retryActionTitle,
            retry: retry,
            style: .plain,
            glyph: APSavedStateCopy.loadFailureGlyph,
            actionIdentifier: identifiers.control
        )
        .accessibilityIdentifier(identifiers.panel)
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
