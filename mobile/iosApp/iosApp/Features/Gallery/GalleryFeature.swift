import Foundation
import Kingfisher
import Network
import SwiftUI
import UIKit

enum GalleryMediaPath {
    /// One shared resolver. `CaptureImageStorage.init` resolves the Application Support directory and
    /// `createDirectory`s it, so building a fresh instance per gallery item was a filesystem call per
    /// photo for no benefit.
    private static let sharedCaptureStorage = CaptureImageStorage()

    static func fileURL(
        for imagePath: String,
        captureStorage: CaptureImageStorage = GalleryMediaPath.sharedCaptureStorage
    ) -> URL {
        if imagePath.hasPrefix("/") {
            return URL(fileURLWithPath: imagePath)
        }
        if let full = captureStorage.fullPath(for: imagePath) {
            return URL(fileURLWithPath: full)
        }
        return URL(fileURLWithPath: imagePath)
    }
}

/// Prepares the file handed to the system share sheet.
///
/// Captures live in `Library/Application Support/aipose/`. Handing that URL straight to
/// `ShareLink`/`UIActivityViewController` makes LaunchServices try to resolve a file provider for a
/// container path it cannot map, fail, and retry (the `NSOSStatusErrorDomain Code=-10814`,
/// "Only support loading options for CKShare and SWY types", "error fetching file provider domain",
/// "could not find answer for domain ... canmaplsdatabase" spam Code Vuong saw), which is what made
/// the sheet take seconds to appear. A plain copy in the app's temporary directory is handed over
/// immediately and produces none of those warnings.
enum GallerySharePreparation {
    enum Failure: LocalizedError {
        case sourceMissing(String)

        var errorDescription: String? {
            switch self {
            case .sourceMissing(let name):
                return "Couldn't prepare \(name) for sharing."
            }
        }
    }

    /// Copies `source` into `FileManager.default.temporaryDirectory` under a readable name
    /// (`aipose-share-<capture>.jpg`). Blocking file I/O — call it off the main thread.
    static func prepare(source: URL, fileManager: FileManager = .default) throws -> URL {
        guard fileManager.fileExists(atPath: source.path) else {
            throw Failure.sourceMissing(source.lastPathComponent)
        }
        let fileExtension = source.pathExtension.isEmpty ? "jpg" : source.pathExtension
        let destination = fileManager.temporaryDirectory.appendingPathComponent(
            "aipose-share-\(source.deletingPathExtension().lastPathComponent).\(fileExtension)"
        )
        if fileManager.fileExists(atPath: destination.path) {
            try? fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
        return destination
    }

    /// Removes a prepared copy once the share sheet is gone.
    static func discard(_ url: URL, fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: url)
    }
}

/// Drives the share sheet by identity, so the sheet can only be presented once the temporary copy
/// actually exists. `tappedAt` lets the tap-to-sheet latency be logged instead of guessed.
struct GallerySharePayload: Identifiable, Equatable {
    let url: URL
    let tappedAt: Date
    var id: String { url.path }
}

struct GalleryItem: Identifiable, Hashable, Sendable {
    let id: Int64
    let fileURL: URL
    let createdAt: Date
    let title: String

    init(id: Int64, fileURL: URL, createdAt: Date, title: String = "Photo") {
        self.id = id
        self.fileURL = fileURL
        self.createdAt = createdAt
        self.title = title
    }
}

enum GalleryDateParser {
    static func date(from value: String) -> Date? {
        if let milliseconds = Int64(value) {
            return Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
        }

        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: value) { return date }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return formatter.date(from: value)
    }
}

protocol GalleryStoring: Sendable {
    func photos() async throws -> [GalleryItem]
    func delete(id: Int64) async throws
}

struct EmptyGalleryStore: GalleryStoring {
    func photos() async throws -> [GalleryItem] { [] }
    func delete(id: Int64) async throws {}
}

enum GalleryTimeFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case today = "Today"
    case week = "7 days"
    case month = "30 days"
    var id: String { rawValue }

    /// Stable Maestro/VoiceOver handle (AC6 drivability). The raw values contain spaces
    /// ("7 days"), so the identifiers use the case names instead.
    var filterIdentifier: String {
        switch self {
        case .all: return "gallery.filter.all"
        case .today: return "gallery.filter.today"
        case .week: return "gallery.filter.week"
        case .month: return "gallery.filter.month"
        }
    }
}

/// User-visible copy for the Gallery state surfaces (report §3.7, `gallery.html`).
/// Pure and testable: views call these instead of hardcoding strings.
enum GalleryStateCopy {
    static let emptyAllTitle = "No photos yet"
    static let emptyAllMessage = "Capture a pose to start your gallery."
    static let openCameraActionTitle = "Open Camera"
    static let emptyFilterTitle = "No photos in this filter"
    static let emptyFilterMessage = "Try another filter."
    static let errorTitle = "Couldn't load gallery"
    static let retryActionTitle = "Try again"
    static let loadingLabel = "Loading gallery…"

    /// QA (TC-GAL-001) taps the empty-state action by id; the panel is the other handle.
    static let openCameraButtonIdentifier = "gallery.empty.openCameraButton"
    static let retryButtonIdentifier = "gallery.error.retry"
}

/// Photo-detail copy. F3 removed the "3 of 12" line, so nothing here counts anything.
enum GalleryDetailCopy {
    /// The page header is the screen's name (`07-board12` draws "Photo"); **when** the photo was
    /// taken moved into the caption block under the frame, so the date is not printed twice.
    static let title = "Photo"
    /// The name `DatabaseGalleryStore` falls back to when a capture has no pose name. It matches the
    /// header, so the caption drops the title line for it instead of repeating "Photo".
    static let untitledName = "Photo"
    static let failedTitle = "Couldn't load this photo"
    static let failedMessage = "The photo is missing from this device."
    static let retryTitle = "Retry"
    static let shareTitle = "Share"
    static let sharePreparingTitle = "Preparing…"
    static let saveTitle = "Save"
    static let saveSavingTitle = "Saving…"
    static let deleteTitle = "Delete"
    static let addPoseTitle = "Add pose"
    static let optionsTitle = "Photo options"
}

/// The caption block under the framed photo (`07-board12`): the photo's name, then one meta line
/// (when · what size). The board's star sits in this block but has no model behind it, so it is not
/// drawn; nothing here is invented — the date, the time and the byte count are all real values.
enum GalleryDetailCaption {
    static let separator = " · "

    /// The name line, or `nil` for an unnamed capture (the header already says "Photo").
    static func title(for item: GalleryItem) -> String? {
        item.title == GalleryDetailCopy.untitledName ? nil : item.title
    }

    /// "Today · 11:08 · 1.2 MB". The size is dropped when the file cannot be read, so a missing file
    /// reports the time it was taken instead of a made-up number.
    static func line(
        for date: Date,
        bytes: Int64?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        var parts = [
            GalleryDayLabel.label(for: date, relativeTo: now, calendar: calendar),
            timeLabel(for: date),
        ]
        if let bytes, let size = byteSizeLabel(bytes) { parts.append(size) }
        return parts.joined(separator: separator)
    }

    /// The device's own short time format (`11:08` or `11:08 AM`): the board's 24-hour sample is the
    /// designer's locale, not a rule worth overriding the user's clock setting for.
    static func timeLabel(for date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// One decimal from the megabyte up, whole kilobytes below it (1000-based, like Finder).
    static func byteSizeLabel(_ bytes: Int64) -> String? {
        guard bytes >= 0 else { return nil }
        let value = Double(bytes)
        if value < 1_000 { return "\(bytes) B" }
        if value < 1_000_000 { return String(format: "%.0f KB", (value / 1_000).rounded()) }
        if value < 1_000_000_000 { return String(format: "%.1f MB", value / 1_000_000) }
        return String(format: "%.1f GB", value / 1_000_000_000)
    }

    /// Blocking file metadata read — call it off the main thread.
    static func fileSize(at url: URL, fileManager: FileManager = .default) -> Int64? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else { return nil }
        return size.int64Value
    }
}

/// The delete confirmation from the export board `07-photo-delete-confirm`: a centred dialog card,
/// not the system action sheet, with the destructive action first.
enum GalleryDeleteConfirmSpec {
    static let title = "Delete this photo?"
    static let message = "It will be removed from this device. This can't be undone."
    static let confirmTitle = "Delete photo"
    static let cancelTitle = "Cancel"

    static let dialogIdentifier = "gallery.detail.deleteConfirm"
    static let confirmIdentifier = "gallery.detail.deleteConfirm.delete"
    static let cancelIdentifier = "gallery.detail.deleteConfirm.cancel"
}

/// Machine handles on the photo-detail screen. The identifiers are additive (the screen used to
/// carry labels only); the VoiceOver page label is now count-free (F3).
enum GalleryDetailAccessibility {
    static let mediaLabel = "Photo"
    static let backIdentifier = "gallery.detail.back"
    static let titleIdentifier = "gallery.detail.title"
    static let optionsIdentifier = "gallery.detail.options"
    static let shareIdentifier = "gallery.detail.share"
    static let saveIdentifier = "gallery.detail.save"
    static let addPoseIdentifier = "gallery.detail.addPose"
    static let deleteIdentifier = "gallery.detail.delete"
    static let captionIdentifier = "gallery.detail.caption"
    static let failedIdentifier = "gallery.detail.failed"
    static let failedRetryIdentifier = "gallery.detail.failedRetry"
}

/// Single source of truth for the gallery grid geometry consumed by `GalleryPhotoGrid`.
///
/// F10 keeps exactly one layout: the 3-column grid from `07-gallery-grid`. The list mode, the dense
/// grid and the list/grid toggle are gone, so there is no second geometry to describe. Values come
/// from the design tokens (12 pt gap, 8 pt thumbnail radius, 16 pt screen inset) instead of the
/// legacy 3 pt / 6 pt dense-grid numbers. `dockInset` keeps the last row clear of the floating dock.
enum GalleryGridContract {
    static let columnCount = 3
    static let spacing: CGFloat = AP.Space.space12
    static let cornerRadius: CGFloat = AP.Radius.radius8
    static let dockInset: CGFloat = 100

    /// Columns for a type size. `07-gallery-grid-ax3` keeps the grid 3-up: a cell is a photo with no
    /// text inside it, so nothing needs to reflow for Dynamic Type — the date headers scale instead.
    static func columnCount(for dynamicTypeSize: DynamicTypeSize) -> Int {
        columnCount
    }

    /// The point size one cell is drawn at: the screen width minus the grid's horizontal padding
    /// (`AP.Space.space16` on each side) split across the three flexible columns. Feeds the image
    /// decode bound — a cell is ~110pt on a 390pt screen, not 4032px.
    @MainActor static var cellDrawSize: CGSize {
        let count = CGFloat(columnCount)
        let side = (
            UIScreen.main.bounds.width
                - AP.Space.space16 * 2
                - spacing * (count - 1)
        ) / count
        let bounded = max(side, 1)
        return CGSize(width: bounded, height: bounded)
    }
}

/// Which state panel the screen shows (`gallery.html` §3.7). Pure so the mapping is testable without
/// rendering, and so the view only picks copy and actions.
enum GalleryStateKind: String, CaseIterable {
    case loading
    case emptyAll
    case emptyFilter
    case error
    case grid
    /// `07-board11`'s offline state, kept in the vocabulary so the decision is explicit: the gallery
    /// reads photos off this device, so a lost connection cannot make one fail to load, and
    /// `GalleryStatePresentation` therefore **never** returns this case. What is offline-bound — Add pose
    /// — reports through `GalleryOfflinePolicy` above the grid instead. If this case ever does arrive,
    /// the screen still draws the local photos (see `GalleryScreen.content`).
    case offline
}

extension GalleryStateKind {
    /// The identifier the state panel's own control must carry, or `nil` when the state has no action.
    /// The screen reads this, so a test asserting it exercises the production mapping instead of
    /// rebuilding a panel with the expected string.
    var actionIdentifier: String? {
        switch self {
        case .emptyAll: return GalleryStateCopy.openCameraButtonIdentifier
        case .error: return GalleryStateCopy.retryButtonIdentifier
        case .loading, .emptyFilter, .grid, .offline: return nil
        }
    }
}

enum GalleryStatePresentation {
    static func kind(for state: Loadable<[GalleryItem]>, timeFilter: GalleryTimeFilter) -> GalleryStateKind {
        switch state {
        case .idle, .loading:
            return .loading
        case .empty:
            // Only the all-gallery-empty state offers `Open camera`; the filter-empty state stays
            // actionless and keeps its own copy. The chips above stay interactive, so the filter
            // remains the way out.
            return timeFilter == .all ? .emptyAll : .emptyFilter
        case .failed:
            return .error
        case .loaded:
            return .grid
        }
    }
}

/// F10 header contract: the tab root keeps its large title and offers **only** Add pose, hidden when
/// the remote `extractPoseEnabled` flag is off — the same rule the Poses header follows (F7).
enum GalleryHeaderAction: String, CaseIterable {
    case addPose

    var systemImage: String {
        switch self {
        case .addPose: return "plus"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .addPose: return "Add pose"
        }
    }

    var identifier: String {
        switch self {
        case .addPose: return "gallery.add-pose"
        }
    }
}

enum GalleryHeaderActions {
    /// The complete set. A list/grid toggle, a list mode or a dense grid must never come back.
    static let actions: [GalleryHeaderAction] = [.addPose]

    /// Add pose is a remote-flag action *and* a destination action: it is hidden when the flag is off
    /// and while the app has not supplied the Add pose route, so it never ships as a dead control.
    static func showsAddPose(extractPoseEnabled: Bool, hasDestination: Bool) -> Bool {
        APHomeHeader.showsAddPose(isExtractPoseEnabled: extractPoseEnabled) && hasDestination
    }
}

/// A cell's interaction, so "tap opens the photo" and "tap retries a failed photo" are one testable
/// rule instead of logic buried in a button closure.
enum GalleryCellPhase: String, CaseIterable {
    case loading
    case loaded
    case failed
}

enum GalleryCellAction: String, CaseIterable {
    case open
    case retry
}

enum GalleryCellBehaviour {
    static func action(for phase: GalleryCellPhase) -> GalleryCellAction {
        phase == .failed ? .retry : .open
    }

    /// Count-free (F3) and state-aware: a failed cell is a retry control, not "Photo, 31 Oct".
    static func voiceOverLabel(title: String, date: Date, phase: GalleryCellPhase) -> String {
        let formatted = date.formatted(date: .abbreviated, time: .shortened)
        switch phase {
        case .failed:
            return "\(GalleryDetailCopy.failedTitle), \(formatted), \(GalleryDetailCopy.retryTitle)"
        case .loading, .loaded:
            return "\(title), \(formatted)"
        }
    }
}

/// The glyph a failed photo cell draws. The board uses a photo-with-slash; the SF Symbol only exists
/// on newer runtimes, so the fallback keeps the state readable on iOS 15.
enum GalleryMediaGlyph {
    static let failed: String = UIImage(systemName: "photo.badge.exclamationmark") != nil
        ? "photo.badge.exclamationmark"
        : "exclamationmark.triangle.fill"
}

/// One toast, shown at the bottom above the chrome (F5). Save and delete failures use it instead of
/// parked text.
struct GalleryToast: Identifiable, Equatable {
    let id: UUID
    let message: String
    let tone: APStateTone

    init(message: String, tone: APStateTone = .error) {
        self.id = UUID()
        self.message = message
        self.tone = tone
    }
}

/// Offline, as the Gallery can honestly report it.
///
/// Everything the grid, the viewer, Share, Save and Delete touch is a jpeg the app already wrote to
/// `Library/Application Support/aipose/`, so losing the connection cannot make a photo fail to load and
/// there is no offline *grid* state to draw. `07-board11`'s per-cell "Offline" tiles and its "Some
/// photos can't load" banner describe a model this app does not have.
///
/// The one thing the screen owns that leaves the device is **Add pose** (extraction is a server job), so
/// that is the only place the board's banner is truthful — and it appears only while that action is
/// actually on screen. A banner over a screen whose every other action works offline would teach users
/// the wrong thing about their own photos.
enum GalleryOfflineCopy {
    static let bannerTitle = "You're offline. Add pose needs a connection."
    static let bannerMessage = "Your photos are on this device and still open normally."
    static let bannerIdentifier = "gallery.offline.banner"
}

enum GalleryOfflinePolicy {
    /// Only shown when the screen really offers a network-bound action.
    static func showsBanner(isOffline: Bool, hasAddPoseAction: Bool) -> Bool {
        isOffline && hasAddPoseAction
    }
}

/// Reachability for the Gallery's single network-bound action: created when the screen appears and torn
/// down when it goes away (`NWPathMonitor.cancel()` is terminal, so a departed screen never keeps a
/// monitor alive) — the same rule `APSavedOfflineModel` and the camera's pose picker follow.
///
/// `@MainActor` on purpose: a globally isolated class is implicitly `Sendable`, which is what makes
/// passing `self` into `NWPathMonitor`'s `@Sendable` handler safe — the handler only ever hops back to
/// the main actor to publish, and no state is touched from the monitor's queue.
@MainActor final class GalleryReachability: ObservableObject {
    @Published private(set) var isOffline: Bool
    private let monitorsConnectivity: Bool
    private var pathMonitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "aipose.gallery.path")

    /// `isOffline` is injectable so a test (or a preview) can pin the offline branch without a network;
    /// tests also switch the monitor off so no queue outlives the case.
    init(isOffline: Bool = false, monitorsConnectivity: Bool = true) {
        self.isOffline = isOffline
        self.monitorsConnectivity = monitorsConnectivity
    }
    deinit { pathMonitor?.cancel() }

    func start() {
        guard monitorsConnectivity, pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let offline = path.status != .satisfied
            Task { @MainActor [weak self] in
                self?.setOffline(offline)
            }
        }
        pathMonitor = monitor
        monitor.start(queue: monitorQueue)
    }

    /// Stops monitoring and forgets the last reading, so a stale "offline" cannot outlive the screen.
    func stop() {
        pathMonitor?.cancel()
        pathMonitor = nil
        isOffline = false
    }

    private func setOffline(_ offline: Bool) {
        guard isOffline != offline else { return }
        isOffline = offline
    }
}

@MainActor final class GalleryViewModel: ObservableObject {
    @Published var state: Loadable<[GalleryItem]> = .idle
    @Published var selectedIndex: Int?
    @Published var timeFilter: GalleryTimeFilter = .all
    /// A recoverable failure (delete, mostly). The grid stays on screen; the message rides above the
    /// dock in a snackbar (F5).
    @Published var toast: GalleryToast?
    private let store: any GalleryStoring
    private var allItems: [GalleryItem] = []

    init(store: any GalleryStoring) { self.store = store }

    var visibleItems: [GalleryItem] {
        let sorted = allItems.sorted { $0.createdAt > $1.createdAt }
        let calendar = Calendar.current
        let now = Date()
        switch timeFilter {
        case .all: return sorted
        case .today: return sorted.filter { calendar.isDate($0.createdAt, inSameDayAs: now) }
        case .week:
            guard let start = calendar.date(byAdding: .day, value: -7, to: now) else { return sorted }
            return sorted.filter { $0.createdAt >= start }
        case .month:
            guard let start = calendar.date(byAdding: .day, value: -30, to: now) else { return sorted }
            return sorted.filter { $0.createdAt >= start }
        }
    }

    /// Groups the already-filtered `visibleItems` by calendar day, newest day first.
    /// The View renders straight from this helper so no date bucketing lives in the view body.
    var dateSections: [GalleryDateSection] {
        let calendar = Calendar.current
        let now = Date()
        let grouped = Dictionary(grouping: visibleItems) { calendar.startOfDay(for: $0.createdAt) }
        return grouped.keys
            .sorted(by: >)
            .map { day in
                GalleryDateSection(
                    day: day,
                    label: Self.sectionLabel(for: day, relativeTo: now, calendar: calendar),
                    items: (grouped[day] ?? []).sorted { $0.createdAt > $1.createdAt }
                )
            }
    }

    static func sectionLabel(for day: Date, relativeTo now: Date, calendar: Calendar) -> String {
        GalleryDayLabel.label(for: day, relativeTo: now, calendar: calendar)
    }

    var stateKind: GalleryStateKind {
        GalleryStatePresentation.kind(for: state, timeFilter: timeFilter)
    }

    /// The message an error panel shows: the store's own reason when it has one.
    var errorMessage: String {
        if case .failed(let message) = state { return message }
        return GalleryStateCopy.errorTitle
    }

    func load() async {
        state = .loading
        let startedAt = Date()
        do {
            allItems = try await store.photos()
            applyFilter()
        } catch {
            state = .failed(error.localizedDescription)
        }
        #if DEBUG
        // How long the gallery's loading state lasts. The store resolves the database + fixture
        // baseline off the main thread, so this is the load's own latency, not a main-thread stall.
        NSLog(
            "%@",
            "AIPOSE_PERF gallery_load_ms=\(Int(Date().timeIntervalSince(startedAt) * 1000)) items=\(allItems.count)"
        )
        #endif
    }

    func applyFilter() {
        let items = visibleItems
        state = items.isEmpty ? .empty : .loaded(items)
    }

    func select(_ item: GalleryItem) {
        selectedIndex = visibleItems.firstIndex(of: item)
    }

    func delete(_ item: GalleryItem) async {
        do {
            try await store.delete(id: item.id)
            allItems.removeAll { $0.id == item.id }
            selectedIndex = nil
            applyFilter()
        } catch {
            // A failed delete must not throw away the photos that are still there: the grid stays and
            // the failure rides a snackbar above the dock.
            showToast(error.localizedDescription)
        }
    }

    func showToast(_ message: String, tone: APStateTone = .error) {
        toast = GalleryToast(message: message, tone: tone)
    }

    func dismissToast() {
        toast = nil
    }
}

/// `@MainActor` because it owns a main-actor reachability model created in its own default initializer
/// (the same shape `APSavedSurface` uses for `APSavedUndo`).
@MainActor
struct GalleryScreen: View {
    @StateObject var model: GalleryViewModel
    /// All-gallery-empty recovery (`gallery.html` `Open Camera`). The owning root wires this to the
    /// camera entry point; the default keeps every existing call site compiling untouched.
    var onOpenCamera: () -> Void = {}
    /// F10 `Add pose (+)`. The owning root supplies the Add pose route; while it is `nil` the control
    /// is hidden rather than shipped as a dead button.
    var onAddPose: (() -> Void)? = nil
    /// Reachability for the screen's one network-bound action (`07-board11`'s banner). Injectable so a
    /// test can pin the offline branch without a network.
    @StateObject private var reachability = GalleryReachability()
    @Namespace private var zoomNamespace
    var body: some View {
        VStack(spacing: 0) {
            galleryHeader
            content
        }
        // R1: the shared state card no longer carries `maxHeight: .infinity` (the prototype has no
        // full-height rule), so the root must top-anchor itself — otherwise a short `.empty` /
        // `.failed` card lets the stack collapse and centres the header and filter chips.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .neoHiddenNavigationBar()
        .background(AP.Color.background)
        .task { if case .idle = model.state { await model.load() } }
        // `NWPathMonitor.cancel()` is terminal, so the monitor lives exactly as long as the screen.
        .onAppear { reachability.start() }
        .onDisappear { reachability.stop() }
        .onChange(of: model.timeFilter) { _ in model.applyFilter() }
        // F5: the failure snackbar sits directly above the floating dock, never mid-screen.
        .modifier(GalleryToastInset(toast: model.toast, bottomInset: GalleryGridContract.dockInset) {
            model.dismissToast()
        })
        .fullScreenCover(isPresented: Binding(
            get: { model.selectedIndex != nil },
            set: { if !$0 { model.selectedIndex = nil } }
        )) {
            if let index = model.selectedIndex {
                GalleryDetailPager(
                    items: model.visibleItems,
                    startIndex: index,
                    zoomNamespace: zoomNamespace,
                    onDelete: { item in
                        Task { await model.delete(item) }
                    },
                    onDismiss: {
                        model.selectedIndex = nil
                    },
                    onAddPose: onAddPose
                )
            }
        }
    }

    /// Tab root (F1 exception): large title plus the screen's actions. F10 leaves exactly one action,
    /// Add pose, and drops the list/grid toggle along with the two layouts it switched between.
    private var galleryHeader: some View {
        VStack(spacing: 0) {
            GalleryHeaderBar(showsAddPose: showsAddPose) { onAddPose?() }
            if showsOfflineBanner {
                // `07-board11`'s banner, scoped to the action that really needs a connection.
                APStatusBanner(
                    tone: .offline,
                    title: GalleryOfflineCopy.bannerTitle,
                    message: GalleryOfflineCopy.bannerMessage
                )
                .padding(.horizontal, AP.Space.space16)
                .padding(.top, AP.Space.space8)
                .accessibilityIdentifier(GalleryOfflineCopy.bannerIdentifier)
            }
            GalleryFilterBar(filter: model.timeFilter) { model.timeFilter = $0 }
        }
    }

    private var showsOfflineBanner: Bool {
        GalleryOfflinePolicy.showsBanner(isOffline: reachability.isOffline, hasAddPoseAction: showsAddPose)
    }

    private var showsAddPose: Bool {
        GalleryHeaderActions.showsAddPose(
            extractPoseEnabled: AppConfig.canExtractPose(isEnabled: AppConfig.shared.isExtractPoseEnabled),
            hasDestination: onAddPose != nil
        )
    }

    @ViewBuilder private var content: some View {
        switch model.stateKind {
        case .grid, .offline:
            ScrollView {
                GalleryPhotoGrid(sections: model.dateSections, zoomNamespace: zoomNamespace) { item in
                    model.select(item)
                }
                .padding(.horizontal, AP.Space.space16)
                .padding(.bottom, GalleryGridContract.dockInset)
            }
        case .loading, .emptyAll, .emptyFilter, .error:
            GalleryStateContent(
                kind: model.stateKind,
                errorMessage: model.errorMessage,
                onOpenCamera: onOpenCamera,
                onRetry: { Task { await model.load() } }
            )
        }
    }
}

/// The tab-root title row: the large title on the left and Add pose on the right, and nothing else.
struct GalleryHeaderBar: View {
    var showsAddPose: Bool
    var onAddPose: () -> Void = {}

    var body: some View {
        HStack(alignment: .center, spacing: AP.Space.space8) {
            Text("Gallery")
                .font(AP.Font.display)
                .foregroundStyle(AP.Color.primaryText)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("gallery.title")
            Spacer(minLength: 0)
            if showsAddPose {
                APHeaderActionButton(
                    systemImage: GalleryHeaderAction.addPose.systemImage,
                    accessibilityLabel: GalleryHeaderAction.addPose.accessibilityLabel,
                    action: onAddPose
                )
                .accessibilityIdentifier(GalleryHeaderAction.addPose.identifier)
            }
        }
        .padding(.horizontal, AP.Space.space16)
        .padding(.top, AP.Space.space8)
    }
}

/// The four non-grid states, all through the shared components (F4): one 72 pt accent-tint circle,
/// then title, copy and at most one action.
struct GalleryStateContent: View {
    let kind: GalleryStateKind
    var errorMessage: String = GalleryStateCopy.errorTitle
    var onOpenCamera: () -> Void = {}
    var onRetry: () -> Void = {}

    @ViewBuilder var body: some View {
        switch kind {
        case .loading:
            APLoadingStateView(label: GalleryStateCopy.loadingLabel)
                .padding(.horizontal, AP.Space.space32)
                .padding(.top, AP.Space.space24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .accessibilityIdentifier("gallery.loading")
        case .emptyAll:
            APEmptyStateView(
                title: GalleryStateCopy.emptyAllTitle,
                message: GalleryStateCopy.emptyAllMessage,
                actionTitle: GalleryStateCopy.openCameraActionTitle,
                action: onOpenCamera,
                style: .plain,
                actionIdentifier: kind.actionIdentifier
            )
            // The panel keeps its own id (the flows assert on it); the button inside carries
            // `gallery.empty.openCameraButton`.
            .accessibilityIdentifier("gallery.empty.openCamera")
        case .emptyFilter:
            APEmptyStateView(
                title: GalleryStateCopy.emptyFilterTitle,
                message: GalleryStateCopy.emptyFilterMessage,
                style: .plain
            )
            .accessibilityIdentifier("gallery.empty.filter")
        case .error:
            APErrorStateView(
                title: GalleryStateCopy.errorTitle,
                message: errorMessage,
                retryTitle: GalleryStateCopy.retryActionTitle,
                retry: onRetry,
                style: .plain,
                actionIdentifier: kind.actionIdentifier
            )
            .accessibilityIdentifier("gallery.error")
        case .grid, .offline:
            // `kind` never describes the grid or the offline case; the screen draws `GalleryPhotoGrid`
            // instead. A photo is local, so an "offline" panel would hide photos that are right there.
            EmptyView()
        }
    }
}

/// Filter chips in the AP chip style: one scrolling row by default, stacked full-width rows at the
/// Accessibility sizes (tokens.md "chips wrap: one chip per row at AX3").
struct GalleryFilterBar: View {
    let filter: GalleryTimeFilter
    let onSelect: (GalleryTimeFilter) -> Void
    /// Layout seam: production follows Dynamic Type; a test can pin either branch so the two layouts are
    /// asserted on pixels instead of on the runner's own text-size setting.
    var stackedLayoutOverride: Bool?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// tokens.md: at the Accessibility sizes every chip gets its own full-width row.
    static func stacksChips(dynamicTypeSize: DynamicTypeSize) -> Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private var stacksChips: Bool {
        stackedLayoutOverride ?? Self.stacksChips(dynamicTypeSize: dynamicTypeSize)
    }

    var body: some View {
        Group {
            if stacksChips {
                VStack(alignment: .leading, spacing: AP.Space.space8) {
                    chips(fillsWidth: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AP.Space.space8) {
                        chips(fillsWidth: false)
                    }
                    .padding(.vertical, AP.Space.space4)
                }
            }
        }
        .padding(.horizontal, AP.Space.space16)
        .padding(.top, AP.Space.space8)
        .padding(.bottom, AP.Space.space4)
    }

    private func chips(fillsWidth: Bool) -> some View {
        ForEach(GalleryTimeFilter.allCases) { option in
            APCategoryChip(
                title: option.rawValue,
                isSelected: filter == option,
                fillsWidth: fillsWidth,
                action: { onSelect(option) }
            )
            .accessibilityIdentifier(option.filterIdentifier)
            .accessibilityLabel(option.rawValue)
        }
    }
}

/// Bottom snackbar placement (F5). `bottomInset` clears whatever bottom chrome the surface owns — the
/// Gallery tab root rides above the floating dock; the photo detail uses the shared `.apSnackbar`.
struct GalleryToastInset: ViewModifier {
    let toast: GalleryToast?
    var bottomInset: CGFloat = 0
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let toast {
                    APSnackbar(tone: toast.tone, message: toast.message, onDismiss: onDismiss)
                        .padding(.horizontal, AP.Space.space16)
                        .padding(.bottom, bottomInset > 0 ? bottomInset : AP.Space.space12)
                }
            }
            .task(id: toast?.id) {
                guard toast != nil else { return }
                try? await Task.sleep(nanoseconds: UInt64(APSnackbar.autoDismissDelay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                onDismiss()
            }
    }
}

/// Loads a gallery file through Kingfisher: off-main decode, memory + disk cache, request
/// coalescing, and — through `AppImage.downsample` — a decoded bitmap bounded by the size the
/// image is actually drawn at.
///
/// The previous implementation called `UIImage(contentsOfFile:)` straight from `body`. That call is
/// lazy, so the real cost landed on the main thread at first draw: measured 19-37ms for one 12MP
/// capture, x12 cells for a single three-column screenful (~440ms of blocked main thread), and it
/// repeated on every re-render because nothing was cached.
struct GalleryLocalImage<Placeholder: View>: View {
    let url: URL
    // Spelled out because Kingfisher exports its own `ContentMode`.
    let contentMode: SwiftUI.ContentMode
    /// Point size the image is drawn at on screen. The decode is bounded by this, never by the file.
    let targetSize: CGSize
    /// Fired when the file cannot be read or decoded, so the caller can switch to the failed state
    /// (`07-gallery-media-states` "Failed, tap to retry").
    var onFailure: (() -> Void)?
    /// Fired once the bitmap is on screen, so the caller can leave its loading phase.
    var onSuccess: (() -> Void)?
    private let placeholder: Placeholder

    init(
        url: URL,
        contentMode: SwiftUI.ContentMode,
        targetSize: CGSize,
        onFailure: (() -> Void)? = nil,
        onSuccess: (() -> Void)? = nil,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.url = url
        self.contentMode = contentMode
        self.targetSize = targetSize
        self.onFailure = onFailure
        self.onSuccess = onSuccess
        self.placeholder = placeholder()
    }

    var body: some View {
        KFImage(url)
            .setProcessor(AppImage.downsample(points: targetSize, contentMode: contentMode))
            // A missing file must keep the FEAT-002 E1 placeholder behaviour.
            .placeholder { placeholder }
            .onSuccess { _ in onSuccess?() }
            .onFailure { _ in onFailure?() }
            .onFailureView { placeholder }
            // `.loadDiskFileSynchronously(false)`: Kingfisher's SwiftUI default reads (and decodes) a
            // disk-cache hit inline, i.e. on the main thread during the view update. Memory hits stay
            // synchronous either way, so this only moves the cold path off the main thread.
            .loadDiskFileSynchronously(false)
            .contentConfigure { image, _ in
                // Exactly the modifiers the old `Image(uiImage:)` path applied, so the layout is
                // unchanged.
                image.resizable().aspectRatio(contentMode: contentMode)
            }
    }
}

/// Bounds the decode of an image the app draws across (nearly) the whole screen — the gallery
/// detail viewer and the captured-photo preview. A 12MP capture is 4032px wide; the device screen
/// is ~2532px, so the full file never has to be decoded.
enum FullScreenImageTarget {
    @MainActor static var drawSize: CGSize {
        let bounds = UIScreen.main.bounds
        let edge = max(max(bounds.width, bounds.height), 1)
        return CGSize(width: edge, height: edge)
    }
}

/// "Today" / "Yesterday" / "Oct 31" — the single day-label rule shared by the grid's day headers
/// (F3: the date only, never a count) and the photo-detail caption's meta line.
enum GalleryDayLabel {
    static func label(for day: Date, relativeTo now: Date, calendar: Calendar) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return dateFormatter.string(from: day)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return formatter
    }()
}

/// One calendar-day bucket of gallery items, newest day first (SCR-002-01-GRD-001).
struct GalleryDateSection: Identifiable, Equatable {
    let day: Date
    let label: String
    let items: [GalleryItem]

    var id: Date { day }
}

/// Day header. Carries the date only — F3 removed the "3 photos" count, and nothing re-adds it.
struct GalleryDateSectionHeader: View {
    let label: String

    var body: some View {
        Text(label)
            .font(AP.Font.heading)
            .foregroundStyle(AP.Color.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, AP.Space.space24)
            .padding(.bottom, AP.Space.space8)
            .accessibilityAddTraits(.isHeader)
    }
}

/// SCR-002-01-GRD-002 / GRD-003: the 3-column grid, one header per date group.
struct GalleryPhotoGrid: View {
    let sections: [GalleryDateSection]
    var zoomNamespace: Namespace.ID?
    let onSelect: (GalleryItem) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: GalleryGridContract.spacing),
            count: GalleryGridContract.columnCount(for: dynamicTypeSize)
        )
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: GalleryGridContract.spacing) {
            ForEach(sections) { section in
                Section {
                    ForEach(section.items) { item in
                        GalleryPhotoCell(item: item) { onSelect($0) }
                            .zoomTransitionSource(id: item.id, in: zoomNamespace, cornerRadius: GalleryGridContract.cornerRadius)
                    }
                } header: {
                    GalleryDateSectionHeader(label: section.label)
                }
            }
        }
    }
}

/// Square photo cell: photo when it loads, `controlFill` placeholder while it loads and a glyph +
/// word retry when it fails. No resting border and no shadow (grid cells are E0).
struct GalleryPhotoCell: View {
    let item: GalleryItem
    var onSelect: (GalleryItem) -> Void

    @State private var phase: GalleryCellPhase = .loading
    @State private var retryToken = 0

    var body: some View {
        Button {
            switch GalleryCellBehaviour.action(for: phase) {
            case .open:
                onSelect(item)
            case .retry:
                retry()
            }
        } label: {
            media
        }
        .buttonStyle(GalleryCellButtonStyle())
        .accessibilityLabel(
            GalleryCellBehaviour.voiceOverLabel(title: item.title, date: item.createdAt, phase: phase)
        )
    }

    private var media: some View {
        // The tile is sized by the square `Rectangle`, and the photo is an overlay: an image drawn with
        // `.fill` reports the size it covers, so letting it size the tile made cells (and the detail
        // frame) outgrow the inset the grid gives them.
        Rectangle()
            .fill(AP.Color.controlFill)
            .aspectRatio(1, contentMode: .fit)
            .overlay { mediaContent }
            .clipShape(RoundedRectangle(cornerRadius: GalleryGridContract.cornerRadius, style: .continuous))
    }

    @ViewBuilder private var mediaContent: some View {
        if phase == .failed {
            VStack(spacing: AP.Space.space4) {
                Image(systemName: GalleryMediaGlyph.failed)
                    .font(.system(size: 20, weight: .semibold))
                Text(GalleryDetailCopy.retryTitle)
                    .font(AP.Font.caption)
            }
            .foregroundStyle(AP.Color.secondaryText)
            .accessibilityHidden(true)
        } else {
            GalleryLocalImage(
                url: item.fileURL,
                contentMode: .fill,
                targetSize: GalleryGridContract.cellDrawSize,
                onFailure: markFailed,
                onSuccess: markLoaded
            ) {
                Color.clear
            }
            // Reloading is a new identity: Kingfisher keeps the failed cache entry otherwise.
            .id(retryToken)
        }
    }

    private func markFailed() {
        // The callback can land during a view update; defer the state change by one run-loop turn.
        DispatchQueue.main.async {
            if phase != .failed, phase != .loaded {
                phase = .failed
            }
        }
    }

    private func markLoaded() {
        DispatchQueue.main.async {
            if phase == .loading {
                phase = .loaded
            }
        }
    }

    private func retry() {
        phase = .loading
        retryToken += 1
    }
}

/// Pressed response for a grid cell: one fill step plus `scale 0.97`; Reduce Motion keeps the fill.
struct GalleryCellButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GalleryCellButtonBody(configuration: configuration)
    }
}

private struct GalleryCellButtonBody: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: GalleryGridContract.cornerRadius, style: .continuous)
                    .fill(AP.Color.controlFillPressed)
                    .opacity(configuration.isPressed ? 0.55 : 0)
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? AP.Press.scale : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: AP.Press.duration),
                value: configuration.isPressed
            )
    }
}

/// The photo-detail action tray (`07-board12`). The board's Star action is deliberately absent: there
/// is no star model, no column and no service call behind it, so shipping the control would be a dead
/// button. Add pose is present only while the app supplies its destination.
enum GalleryDetailTrayAction: String, CaseIterable {
    case share
    case save
    case addPose
    case delete

    var title: String {
        switch self {
        case .share: return GalleryDetailCopy.shareTitle
        case .save: return GalleryDetailCopy.saveTitle
        case .addPose: return GalleryDetailCopy.addPoseTitle
        case .delete: return GalleryDetailCopy.deleteTitle
        }
    }

    var systemImage: String {
        switch self {
        case .share: return "square.and.arrow.up"
        case .save: return "arrow.down.to.line"
        case .addPose: return "plus.circle"
        case .delete: return "trash"
        }
    }

    var identifier: String {
        switch self {
        case .share: return GalleryDetailAccessibility.shareIdentifier
        case .save: return GalleryDetailAccessibility.saveIdentifier
        case .addPose: return GalleryDetailAccessibility.addPoseIdentifier
        case .delete: return GalleryDetailAccessibility.deleteIdentifier
        }
    }
}

enum GalleryDetailTrayActions {
    /// Share, Save, Add pose, Delete — destructive last. Never Star.
    static func actions(hasAddPoseDestination: Bool) -> [GalleryDetailTrayAction] {
        [.share, .save] + (hasAddPoseDestination ? [.addPose] : []) + [.delete]
    }

    /// tokens.md wraps the tray at the Accessibility sizes: four glyph + word actions on one row broke
    /// mid-word ("Sha / re", "Del / ete" at AX3), so the row splits to two per line. `07-board12` is
    /// boarded at the default size only, which keeps the single row.
    static func stacksRows(dynamicTypeSize: DynamicTypeSize) -> Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    /// The tray's rows, in board order.
    static func rows(hasAddPoseDestination: Bool, stacks: Bool) -> [[GalleryDetailTrayAction]] {
        let all = actions(hasAddPoseDestination: hasAddPoseDestination)
        guard stacks else { return [all] }
        return stride(from: 0, to: all.count, by: 2).map { start in
            Array(all[start..<min(start + 2, all.count)])
        }
    }

    /// Widest row, so a short last row is padded with empty cells of the same width instead of
    /// stretching its one label across the bar.
    static func columnsPerRow(_ rows: [[GalleryDetailTrayAction]]) -> Int {
        rows.map(\.count).max() ?? 0
    }
}

enum GalleryDetailPresentation {
    /// Bumped for the F1 header, the count-free pager, the board's tray / dialog, and (v4) the caption
    /// block under the frame plus the tray's Add pose action.
    static let styleVersion = 4
}

/// The caption block under the framed photo (`07-board12`): the photo's name, then one meta line —
/// "Today · 11:08 · 1.2 MB". The byte count is read from the file itself, off the main thread, and is
/// simply omitted when the file is gone: this block has no placeholder numbers.
struct GalleryDetailCaptionView: View {
    let item: GalleryItem
    /// Test seam: production reads the file; a render test can hand in a known size.
    var byteSizeOverride: Int64?
    /// Test seam for the day label ("Today"/"Yesterday"), which is otherwise relative to the clock.
    var now: Date = Date()

    @State private var loadedByteSize: Int64?

    private var byteSize: Int64? { byteSizeOverride ?? loadedByteSize }

    var body: some View {
        VStack(alignment: .leading, spacing: AP.Space.space4) {
            if let title = GalleryDetailCaption.title(for: item) {
                Text(title)
                    .font(AP.Font.heading)
                    .foregroundStyle(AP.Color.primaryText)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(GalleryDetailCaption.line(for: item.createdAt, bytes: byteSize, now: now))
                .font(AP.Font.supporting)
                .foregroundStyle(AP.Color.secondaryText)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AP.Space.space24)
        .padding(.top, AP.Space.space12)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(GalleryDetailAccessibility.captionIdentifier)
        .task(id: item.id) {
            guard byteSizeOverride == nil else { return }
            let url = item.fileURL
            loadedByteSize = await Task.detached(priority: .utility) {
                GalleryDetailCaption.fileSize(at: url)
            }.value
        }
    }
}

/// The framed media in the pager: photo, `controlFill` placeholder, or the board's in-frame failure
/// panel with its own retry.
struct GalleryDetailPhotoFrame: View {
    let item: GalleryItem
    /// Test seam: production always starts at `.loading`, the rendered failure test starts at `.failed`.
    var initialPhase: GalleryCellPhase = .loading

    @State private var phase: GalleryCellPhase
    @State private var retryToken = 0

    init(item: GalleryItem, initialPhase: GalleryCellPhase = .loading) {
        self.item = item
        self.initialPhase = initialPhase
        _phase = State(initialValue: initialPhase)
    }

    var body: some View {
        if phase == .failed {
            // The failure state takes its natural height instead of the photo's fixed 3:4 box: at the
            // Accessibility sizes the headline, the message and Retry together are taller than that
            // box, and squeezing them into it clipped the control. The page itself scrolls.
            failedPanel
                .background(
                    RoundedRectangle(cornerRadius: AP.Radius.radius24, style: .continuous)
                        .fill(AP.Color.surface)
                        .apElevation(.e1, cornerRadius: AP.Radius.radius24)
                )
                .clipShape(RoundedRectangle(cornerRadius: AP.Radius.radius24, style: .continuous))
        } else {
            // Sized by the 3:4 `Rectangle`, photo as an overlay: a `.fill` image reports the size it
            // covers, so letting it size the tile made the photo outgrow the page inset.
            Rectangle()
                .fill(AP.Color.controlFill)
                .aspectRatio(3 / 4, contentMode: .fit)
                .overlay {
                    GalleryLocalImage(
                        url: item.fileURL,
                        contentMode: .fill,
                        targetSize: FullScreenImageTarget.drawSize,
                        onFailure: markFailed,
                        onSuccess: markLoaded
                    ) {
                        Color.clear
                    }
                    .id(retryToken)
                }
                .clipShape(RoundedRectangle(cornerRadius: AP.Radius.radius24, style: .continuous))
        }
    }

    private var failedPanel: some View {
        VStack(spacing: AP.Space.space8) {
            Image(systemName: GalleryMediaGlyph.failed)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(AP.Color.secondaryText)
                .accessibilityHidden(true)
            Text(GalleryDetailCopy.failedTitle)
                .font(AP.Font.heading)
                .foregroundStyle(AP.Color.primaryText)
                .multilineTextAlignment(.center)
            Text(GalleryDetailCopy.failedMessage)
                .font(AP.Font.supporting)
                .foregroundStyle(AP.Color.secondaryText)
                .multilineTextAlignment(.center)
            Button(GalleryDetailCopy.retryTitle) { retry() }
                .buttonStyle(APSecondaryButtonStyle())
                .frame(maxWidth: 200)
                .padding(.top, AP.Space.space8)
                .accessibilityIdentifier(GalleryDetailAccessibility.failedRetryIdentifier)
        }
        .padding(AP.Space.space24)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(GalleryDetailAccessibility.failedIdentifier)
    }

    private func markFailed() {
        DispatchQueue.main.async {
            if phase != .failed {
                phase = .failed
            }
        }
    }

    private func markLoaded() {
        DispatchQueue.main.async {
            if phase == .loading {
                phase = .loaded
            }
        }
    }

    private func retry() {
        phase = .loading
        retryToken += 1
    }
}

/// F1 page header plus the screen's own Options control. The Options control is a **sibling** in the
/// row, not an overlay: at 320 pt and the Accessibility sizes a wrapping date would otherwise run
/// underneath it. (APPageHeader has no trailing slot, so the reservation lives here.)
struct GalleryDetailHeader: View {
    let title: String
    var onBack: () -> Void = {}
    var onDelete: () -> Void = {}

    var body: some View {
        HStack(alignment: .center, spacing: AP.Space.space8) {
            APPageHeader(
                title: title,
                backLabel: "Back",
                backStyle: .control,
                backIdentifier: GalleryDetailAccessibility.backIdentifier,
                titleIdentifier: GalleryDetailAccessibility.titleIdentifier,
                onBack: onBack
            )
            Menu {
                Button(role: .destructive, action: onDelete) {
                    Label(GalleryDeleteConfirmSpec.confirmTitle, systemImage: "trash")
                }
            } label: {
                APHeaderActionGlyph(systemImage: "ellipsis")
                    .background(
                        RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                            .fill(AP.Color.controlFill)
                    )
            }
            // The menu's own tint would paint the glyph in system blue; the header control is AP ink.
            .tint(AP.Color.primaryText)
            .accessibilityLabel(GalleryDetailCopy.optionsTitle)
            .accessibilityIdentifier(GalleryDetailAccessibility.optionsIdentifier)
            .padding(.trailing, AP.Space.space16)
        }
        .frame(minHeight: AP.HitTarget.minimum)
    }
}

/// Canonical Gallery detail v3: F1 one-row header, framed media with the pager dots, the board's
/// action tray and the board's centred delete confirmation. No count line anywhere (F3).
struct GalleryDetailPager: View {
    let items: [GalleryItem]
    let startIndex: Int
    var zoomNamespace: Namespace.ID?
    let onDelete: (GalleryItem) -> Void
    let onDismiss: () -> Void
    /// The tray's Add pose action. Hidden while the app has not supplied the Add pose destination,
    /// exactly like the grid header's `+`, so it never ships as a dead control.
    var onAddPose: (() -> Void)?
    @State private var page: Int
    @State private var showsDeleteConfirm = false
    @State private var shareItem: GallerySharePayload?
    @State private var isPreparingShare = false
    @State private var isSaving = false
    @State private var toast: GalleryToast?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        items: [GalleryItem],
        startIndex: Int,
        zoomNamespace: Namespace.ID? = nil,
        onDelete: @escaping (GalleryItem) -> Void,
        onDismiss: @escaping () -> Void,
        onAddPose: (() -> Void)? = nil
    ) {
        self.items = items
        self.startIndex = startIndex
        self.zoomNamespace = zoomNamespace
        self.onDelete = onDelete
        self.onDismiss = onDismiss
        self.onAddPose = onAddPose
        _page = State(initialValue: startIndex)
    }

    private var current: GalleryItem { items[page] }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                topbar

                // F5: the snackbar rides directly above the action tray, never mid-screen.
                TabView(selection: $page) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        // Top-aligned and scrollable: the media sits right under the header, and a
                        // failure panel that is taller than the screen (AX sizes) stays reachable.
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 0) {
                                GalleryDetailPhotoFrame(item: item)
                                    .padding(.horizontal, AP.Space.space24)
                                    .padding(.top, AP.Space.space16)
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .tag(index)
                        .accessibilityLabel(GalleryDetailAccessibility.mediaLabel)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: items.count > 1 ? .automatic : .never))
                .frame(maxHeight: .infinity)
                .apSnackbar(toast?.message, tone: toast?.tone ?? .error) { toast = nil }

                // `07-board12`: the caption sits under the pager dots, above the tray, and follows the
                // page the user is on.
                GalleryDetailCaptionView(item: current)
                    .padding(.bottom, AP.Space.space16)

                actionTray
            }
            .background(AP.Color.background.ignoresSafeArea())
            .neoHiddenNavigationBar()
            .overlay {
                if showsDeleteConfirm {
                    GalleryDeleteDialog(
                        onConfirm: {
                            showsDeleteConfirm = false
                            onDelete(current)
                            onDismiss()
                        },
                        onCancel: { showsDeleteConfirm = false }
                    )
                }
            }
            .sheet(item: $shareItem) { payload in
                ShareSheet(items: [payload.url])
                    .onAppear {
                        #if DEBUG
                        NSLog(
                            "%@",
                            "AIPOSE_PERF share_sheet_ms=\(Int(Date().timeIntervalSince(payload.tappedAt) * 1000)) url_is_tmp=\(payload.url.path.hasPrefix(FileManager.default.temporaryDirectory.path))"
                        )
                        #endif
                    }
                    .onDisappear { GallerySharePreparation.discard(payload.url) }
            }
            // F5: failures use the bottom snackbar, above the tray.
            .onChange(of: page) { _ in toast = nil }
            .task(id: toast?.id) {
                guard toast != nil else { return }
                try? await Task.sleep(nanoseconds: UInt64(APSnackbar.autoDismissDelay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                toast = nil
            }
        }
        .navigationViewStyle(.stack)
        .zoomTransition(sourceID: current.id, in: zoomNamespace)
    }

    /// F1/F2: the shared page header — back control and the screen's name on one row — with the
    /// screen's own options control in the trailing slot. The old "3 of 12" line is gone (F3), and the
    /// date lives in the caption block under the frame (`07-board12`).
    private var topbar: some View {
        GalleryDetailHeader(
            title: GalleryDetailCopy.title,
            onBack: onDismiss,
            onDelete: { showsDeleteConfirm = true }
        )
    }

    /// `07-photo-detail`: a raised `surface` tray directly above the bottom safe area — one row of
    /// glyph + word actions at the default sizes, two per row at the Accessibility sizes.
    private var actionTray: some View {
        trayRows
            .padding(.horizontal, AP.Space.space16)
            .padding(.vertical, AP.Space.space12)
            // The bar carries the surface down behind the home indicator; the controls stay above it.
            .background {
                AP.Color.surface
                    .ignoresSafeArea(edges: .bottom)
                    .apElevation(.e1, cornerRadius: 0)
            }
    }

    private var trayRows: some View {
        let rows = GalleryDetailTrayActions.rows(
            hasAddPoseDestination: onAddPose != nil,
            stacks: GalleryDetailTrayActions.stacksRows(dynamicTypeSize: dynamicTypeSize)
        )
        let columns = GalleryDetailTrayActions.columnsPerRow(rows)
        return VStack(spacing: AP.Space.space4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: AP.Space.space4) {
                    ForEach(0..<columns, id: \.self) { index in
                        if index < row.count {
                            trayAction(row[index])
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity, maxHeight: 1)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var shareAction: some View {
        Button { prepareShare() } label: {
            GalleryTrayActionLabel(
                title: isPreparingShare ? GalleryDetailCopy.sharePreparingTitle : GalleryDetailCopy.shareTitle,
                systemImage: "square.and.arrow.up",
                isEnabled: !isPreparingShare
            )
        }
        .buttonStyle(GalleryTrayButtonStyle())
        .disabled(isPreparingShare)
        .accessibilityIdentifier(GalleryDetailAccessibility.shareIdentifier)
        .accessibilityLabel(isPreparingShare ? "Preparing photo for sharing" : "Share photo")
    }

    /// Copying a few MB is file I/O, so it runs off the main thread and the tray action reports a
    /// "Preparing…" state instead of freezing the tap. The sheet is only opened with the temporary
    /// copy (see `GallerySharePreparation`), never with the Application Support path.
    private func prepareShare() {
        guard !isPreparingShare else { return }
        let item = current
        let tappedAt = Date()
        isPreparingShare = true
        toast = nil
        Task {
            let prepared = await Task.detached(priority: .userInitiated) {
                try? GallerySharePreparation.prepare(source: item.fileURL)
            }.value
            isPreparingShare = false
            if let prepared {
                #if DEBUG
                NSLog(
                    "%@",
                    "AIPOSE_PERF share_prepare_ms=\(Int(Date().timeIntervalSince(tappedAt) * 1000)) file=\(prepared.lastPathComponent)"
                )
                #endif
                shareItem = GallerySharePayload(url: prepared, tappedAt: tappedAt)
            } else {
                toast = GalleryToast(
                    message: GallerySharePreparation.Failure
                        .sourceMissing(item.fileURL.lastPathComponent).localizedDescription
                )
            }
        }
    }

    private var saveAction: some View {
        Button { saveCurrentToPhotos() } label: {
            GalleryTrayActionLabel(
                title: isSaving ? GalleryDetailCopy.saveSavingTitle : GalleryDetailCopy.saveTitle,
                systemImage: "arrow.down.to.line",
                isEnabled: !isSaving
            )
        }
        .buttonStyle(GalleryTrayButtonStyle())
        .disabled(isSaving)
        .accessibilityIdentifier(GalleryDetailAccessibility.saveIdentifier)
        .accessibilityLabel(isSaving ? "Saving to Photos" : "Save to Photos")
    }

    @ViewBuilder private func trayAction(_ action: GalleryDetailTrayAction) -> some View {
        switch action {
        case .share: shareAction
        case .save: saveAction
        case .addPose: addPoseAction
        case .delete: trashAction
        }
    }

    /// `07-board12`'s Add pose tray action: it enters the existing Add pose flow instead of inventing a
    /// second one. The viewer leaves first — the full-screen cover would otherwise stay on top of the
    /// Add pose form it opened.
    @ViewBuilder private var addPoseAction: some View {
        if let onAddPose {
            Button {
                onDismiss()
                onAddPose()
            } label: {
                GalleryTrayActionLabel(
                    title: GalleryDetailTrayAction.addPose.title,
                    systemImage: GalleryDetailTrayAction.addPose.systemImage
                )
            }
            .buttonStyle(GalleryTrayButtonStyle())
            .accessibilityIdentifier(GalleryDetailTrayAction.addPose.identifier)
            .accessibilityLabel("Add pose from this photo")
        }
    }

    private var trashAction: some View {
        Button(role: .destructive) { showsDeleteConfirm = true } label: {
            GalleryTrayActionLabel(
                title: GalleryDetailCopy.deleteTitle,
                systemImage: "trash",
                tint: AP.Color.error
            )
        }
        .buttonStyle(GalleryTrayButtonStyle())
        .accessibilityIdentifier(GalleryDetailAccessibility.deleteIdentifier)
        .accessibilityLabel("Delete photo")
    }

    /// Save reuses the existing Photos export port (`PhotosExporter`); the outcome is reported honestly
    /// through the bottom snackbar (success and failure both).
    private func saveCurrentToPhotos() {
        guard !isSaving else { return }
        let item = current
        isSaving = true
        toast = nil
        Task {
            let saved = await PhotosExporter.saveImage(at: item.fileURL)
            await MainActor.run {
                isSaving = false
                toast = GalleryToast(
                    message: PhotosExporter.confirmation(saved: saved),
                    tone: saved ? .success : .error
                )
            }
        }
    }
}

/// Glyph + word action in the detail tray. Minimum 70 pt tall, no chrome of its own.
struct GalleryTrayActionLabel: View {
    let title: String
    let systemImage: String
    var tint: SwiftUI.Color = AP.Color.primaryText
    var isEnabled: Bool = true

    var body: some View {
        VStack(spacing: AP.Space.space4) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .regular))
            Text(title)
                .font(AP.Font.caption)
                .lineLimit(nil)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(isEnabled ? tint : AP.Color.disabled)
        .frame(maxWidth: .infinity, minHeight: 70)
        .contentShape(RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous))
    }
}

/// Tray press response: one fill step plus `scale 0.97`; Reduce Motion keeps the fill only.
struct GalleryTrayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GalleryTrayButtonBody(configuration: configuration)
    }
}

private struct GalleryTrayButtonBody: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                    .fill(fill)
            )
            .scaleEffect(configuration.isPressed && !reduceMotion ? AP.Press.scale : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: AP.Press.duration),
                value: configuration.isPressed
            )
    }

    private var fill: SwiftUI.Color {
        guard isEnabled, configuration.isPressed else { return .clear }
        return AP.Color.controlFillPressed
    }
}

/// `07-photo-delete-confirm`: the scrim, the centred `surface` card, the destructive action first and
/// the neutral cancel under it.
struct GalleryDeleteDialog: View {
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            AP.Color.scrim
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)
                .accessibilityHidden(true)
            VStack(spacing: AP.Space.space16) {
                VStack(spacing: AP.Space.space8) {
                    Text(GalleryDeleteConfirmSpec.title)
                        .font(AP.Font.heading)
                        .foregroundStyle(AP.Color.primaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(GalleryDeleteConfirmSpec.message)
                        .font(AP.Font.supporting)
                        .foregroundStyle(AP.Color.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: AP.Space.space8) {
                    Button(GalleryDeleteConfirmSpec.confirmTitle, action: onConfirm)
                        .buttonStyle(GalleryDestructiveButtonStyle())
                        .accessibilityIdentifier(GalleryDeleteConfirmSpec.confirmIdentifier)
                    Button(GalleryDeleteConfirmSpec.cancelTitle, action: onCancel)
                        .buttonStyle(APSecondaryButtonStyle())
                        .accessibilityIdentifier(GalleryDeleteConfirmSpec.cancelIdentifier)
                }
            }
            .padding(AP.Space.space24)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: AP.Radius.radius24, style: .continuous)
                    .fill(AP.Color.surface)
            )
            .apElevation(.e1, cornerRadius: AP.Radius.radius24)
            .padding(.horizontal, AP.Space.space24)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(GalleryDeleteConfirmSpec.dialogIdentifier)
        }
        .accessibilityAddTraits(.isModal)
    }
}

/// Destructive action: `error` fill with `onError` label. Pressed darkens the fill by 14% (tokens.md),
/// which is the fill stepping down without a second red token.
struct GalleryDestructiveButtonStyle: ButtonStyle {
    /// 14% darker while pressed (tokens.md, destructive button).
    static let pressedDarkening: Double = 0.14

    func makeBody(configuration: Configuration) -> some View {
        GalleryDestructiveButtonBody(configuration: configuration)
    }
}

private struct GalleryDestructiveButtonBody: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .font(AP.Font.heading)
            .foregroundStyle(AP.Color.onError)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, AP.Space.space16)
            .padding(.vertical, AP.Space.space8)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background {
                let shape = RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                if configuration.isPressed {
                    shape
                        .fill(AP.Color.error)
                        .overlay {
                            shape.fill(Color.black.opacity(GalleryDestructiveButtonStyle.pressedDarkening))
                        }
                } else {
                    shape.fill(AP.Color.error)
                }
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? AP.Press.scale : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: AP.Press.duration),
                value: configuration.isPressed
            )
    }
}
