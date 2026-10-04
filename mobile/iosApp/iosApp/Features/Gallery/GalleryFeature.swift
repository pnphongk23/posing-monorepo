import Foundation
import Kingfisher
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
}

@MainActor final class GalleryViewModel: ObservableObject {
    @Published var state: Loadable<[GalleryItem]> = .idle
    @Published var selectedIndex: Int?
    @Published var timeFilter: GalleryTimeFilter = .all
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
        if calendar.isDate(day, inSameDayAs: now) { return "TODAY" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(day, inSameDayAs: yesterday) {
            return "YESTERDAY"
        }
        return sectionDateFormatter.string(from: day).uppercased()
    }

    private static let sectionDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

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
            state = .failed(error.localizedDescription)
        }
    }
}

struct GalleryScreen: View {
    @StateObject var model: GalleryViewModel
    /// All-gallery-empty recovery (`gallery.html` `Open Camera`). The owning root wires this to the
    /// camera entry point; the default keeps every existing call site compiling untouched.
    var onOpenCamera: () -> Void = {}
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
        .background(AIPoseColor.background)
        .task { if case .idle = model.state { await model.load() } }
        .onChange(of: model.timeFilter) { _ in model.applyFilter() }
        .fullScreenCover(isPresented: Binding(
            get: { model.selectedIndex != nil },
            set: { if !$0 { model.selectedIndex = nil } }
        )) {
            if let index = model.selectedIndex {
                GalleryDetailPager(items: model.visibleItems, startIndex: index, zoomNamespace: zoomNamespace) { item in
                    Task { await model.delete(item) }
                } onDismiss: {
                    model.selectedIndex = nil
                }
            }
        }
    }

    private var galleryHeader: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Gallery").font(.title2.bold())
                Spacer()
            }
            .padding(.horizontal, AIPoseSpacing.lg)
            .padding(.top, AIPoseSpacing.sm)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AIPoseSpacing.sm) {
                    ForEach(GalleryTimeFilter.allCases) { filter in
                        NeoFilterChip(
                            title: filter.rawValue,
                            isSelected: model.timeFilter == filter,
                            variant: .gallery,
                            action: { model.timeFilter = filter }
                        )
                        .accessibilityIdentifier(filter.filterIdentifier)
                        .accessibilityLabel(filter.rawValue)
                    }
                }
                .padding(.horizontal, AIPoseSpacing.lg)
                .padding(.vertical, AIPoseSpacing.sm)
            }
        }
    }

    /// State cards render in flow at the top of the content column (`gallery.html` mounts the
    /// state inside the grid column, 16pt side padding, no centring); the frozen `FeatureStateView`
    /// is a full-width top-anchored card with no icon slot.
    @ViewBuilder private var content: some View {
        // Card tone comes from the pure `Loadable.stateTone` mapper; the branches below only choose
        // this screen's copy and placement.
        switch model.state.stateTone {
        case .some(.loading):
            ProgressView("Loading gallery…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .some(.empty):
            // §3.7: only the all-gallery-empty state offers `Open Camera`; the filter-empty state
            // stays actionless. The two states keep distinct copy. The prototype appends the card
            // as a child of the masonry grid (`.nb-gallery-empty-state`: column-span all,
            // `margin: var(--nb-space-md) 0`), so the card occupies the grid slot — 16pt vertical
            // margin, the grid's 16pt side padding — while the header and filter chips stay
            // visible and interactive above it (the chips are the only way out of an empty filter).
            if model.timeFilter == .all {
                FeatureStateView(
                    tone: .empty,
                    title: GalleryStateCopy.emptyAllTitle,
                    message: GalleryStateCopy.emptyAllMessage,
                    actionTitle: GalleryStateCopy.openCameraActionTitle
                ) {
                    onOpenCamera()
                }
                .padding(.horizontal, AIPoseSpacing.lg)
                .padding(.vertical, AIPoseSpacing.lg)
                .accessibilityIdentifier("gallery.empty.openCamera")
            } else {
                FeatureStateView(
                    tone: .empty,
                    title: GalleryStateCopy.emptyFilterTitle,
                    message: GalleryStateCopy.emptyFilterMessage
                )
                .padding(.horizontal, AIPoseSpacing.lg)
                .padding(.vertical, AIPoseSpacing.lg)
            }
        case .some(.error):
            let message: String = {
                if case .failed(let message) = model.state { return message }
                return GalleryStateCopy.errorTitle
            }()
            FeatureStateView(
                tone: .error,
                title: GalleryStateCopy.errorTitle,
                message: message,
                actionTitle: GalleryStateCopy.retryActionTitle
            ) {
                Task { await model.load() }
            }
            .padding(.horizontal, AIPoseSpacing.lg)
        case .some(.offline), .some(.success), .some(.warning):
            // No producer for these tones on this surface.
            EmptyView()
        case nil:
            ScrollView {
                GalleryPhotoGrid(sections: model.dateSections, zoomNamespace: zoomNamespace) { item in
                    model.select(item)
                }
                .padding(.horizontal, AIPoseSpacing.lg)
                .padding(.top, AIPoseSpacing.sm)
                .padding(.bottom, GalleryGridContract.dockInset)
            }
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
    private let placeholder: Placeholder

    init(
        url: URL,
        contentMode: SwiftUI.ContentMode,
        targetSize: CGSize,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.url = url
        self.contentMode = contentMode
        self.targetSize = targetSize
        self.placeholder = placeholder()
    }

    var body: some View {
        KFImage(url)
            .setProcessor(AppImage.downsample(points: targetSize, contentMode: contentMode))
            // A missing file must keep the FEAT-002 E1 placeholder behaviour.
            .placeholder { placeholder }
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

/// Single source of truth for the dense gallery grid geometry consumed by `GalleryPhotoGrid`.
/// SCR-002-01-GRD-002 fixes 3 columns with a 3dp gap; `dockInset` keeps the last row clear of the dock overlay.
enum GalleryGridContract {
    static let columnCount = 3
    static let spacing: CGFloat = 3
    static let cornerRadius: CGFloat = 6
    static let dockInset: CGFloat = 100

    /// The point size one cell is drawn at: the screen width minus the grid's horizontal padding
    /// (`AIPoseSpacing.lg` on each side) split across the three flexible columns. Feeds the image
    /// decode bound — a cell is ~117pt on a 390pt screen, not 4032px.
    @MainActor static var cellDrawSize: CGSize {
        let side = (
            UIScreen.main.bounds.width
                - AIPoseSpacing.lg * 2
                - spacing * CGFloat(columnCount - 1)
        ) / CGFloat(columnCount)
        let bounded = max(side, 1)
        return CGSize(width: bounded, height: bounded)
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

/// One calendar-day bucket of gallery items, newest day first (SCR-002-01-GRD-001).
struct GalleryDateSection: Identifiable, Equatable {
    let day: Date
    let label: String
    let items: [GalleryItem]

    var id: Date { day }
}

/// Small uppercase day header; deliberately subordinate to the single "Gallery" screen title.
struct GalleryDateSectionHeader: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .bold))
            .kerning(0.4)
            .foregroundStyle(AIPoseColor.subtext)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, AIPoseSpacing.sm)
            .padding(.bottom, AIPoseSpacing.xs)
            .accessibilityAddTraits(.isHeader)
    }
}

/// SCR-002-01-GRD-002 / GRD-003: dense square 3-column grid, one header per date group.
struct GalleryPhotoGrid: View {
    let sections: [GalleryDateSection]
    var zoomNamespace: Namespace.ID?
    let onSelect: (GalleryItem) -> Void

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: GalleryGridContract.spacing),
            count: GalleryGridContract.columnCount
        )
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: GalleryGridContract.spacing) {
            ForEach(sections) { section in
                Section {
                    ForEach(section.items) { item in
                        Button { onSelect(item) } label: {
                            GalleryPhotoCell(item: item)
                                .zoomTransitionSource(id: item.id, in: zoomNamespace, cornerRadius: GalleryGridContract.cornerRadius)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    GalleryDateSectionHeader(label: section.label)
                }
            }
        }
    }
}

/// Dense square photo card. Keeps the FEAT-002 E1 missing-file placeholder behaviour.
struct GalleryPhotoCell: View {
    let item: GalleryItem

    var body: some View {
        Rectangle()
            .fill(AIPoseColor.surfaceVariant)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                GalleryLocalImage(url: item.fileURL, contentMode: .fill, targetSize: GalleryGridContract.cellDrawSize) {
                    AIPoseColor.surfaceVariant.overlay {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(AIPoseColor.subtext)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: GalleryGridContract.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: GalleryGridContract.cornerRadius)
                    .stroke(AIPoseColor.foreground, lineWidth: 1.5)
            )
            .accessibilityLabel("\(item.title), \(item.createdAt.formatted(date: .abbreviated, time: .shortened))")
    }
}

enum GalleryDetailPresentation {
    static let styleVersion = 2
}

struct GalleryDetailPhotoFrame: View {
    let item: GalleryItem

    var body: some View {
        Rectangle()
            .fill(AIPoseColor.surfaceVariant)
            .aspectRatio(3 / 4, contentMode: .fit)
            .overlay {
                GalleryLocalImage(url: item.fileURL, contentMode: .fill, targetSize: FullScreenImageTarget.drawSize) {
                    VStack(spacing: AIPoseSpacing.sm) {
                        Image(systemName: "exclamationmark.triangle")
                        Text("Couldn't load photo").font(.footnote)
                    }
                    .foregroundStyle(AIPoseColor.subtext)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AIPoseColor.surfaceVariant)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22))
    }
}

/// Canonical Gallery detail v2: light-cream canvas, framed media, date/time topbar and a 3-up action tray.
struct GalleryDetailPager: View {
    let items: [GalleryItem]
    let startIndex: Int
    var zoomNamespace: Namespace.ID?
    let onDelete: (GalleryItem) -> Void
    let onDismiss: () -> Void
    @State private var page: Int
    @State private var confirmDelete = false
    @State private var showOptions = false
    @State private var shareItem: GallerySharePayload?
    @State private var isPreparingShare = false
    @State private var isSaving = false
    @State private var saveStatus: String?

    init(
        items: [GalleryItem],
        startIndex: Int,
        zoomNamespace: Namespace.ID? = nil,
        onDelete: @escaping (GalleryItem) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.items = items
        self.startIndex = startIndex
        self.zoomNamespace = zoomNamespace
        self.onDelete = onDelete
        self.onDismiss = onDismiss
        _page = State(initialValue: startIndex)
    }

    private var current: GalleryItem { items[page] }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                topbar

                TabView(selection: $page) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        GalleryDetailPhotoFrame(item: item)
                            .padding(.horizontal, 18)
                            .padding(.top, AIPoseSpacing.md)
                            .tag(index)
                            .accessibilityLabel("Photo \(index + 1) of \(items.count)")
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: items.count > 1 ? .automatic : .never))
                .frame(maxHeight: .infinity)

                if let saveStatus {
                    Text(saveStatus)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AIPoseColor.subtext)
                        .padding(.top, AIPoseSpacing.sm)
                        .accessibilityLabel(saveStatus)
                }

                actionTray
            }
            .background(AIPoseColor.background.ignoresSafeArea())
            .neoHiddenNavigationBar()
            .confirmationDialog("Delete this photo?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { onDelete(current); onDismiss() }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Photo options", isPresented: $showOptions, titleVisibility: .visible) {
                Button("Delete Photo", role: .destructive) { onDelete(current); onDismiss() }
                Button("Cancel", role: .cancel) {}
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
            .onChange(of: page) { _ in saveStatus = nil }
        }
        .navigationViewStyle(.stack)
        .zoomTransition(sourceID: current.id, in: zoomNamespace)
    }

    /// Prototype `.topbar`: plain circular back control, centered date/time, plain options control.
    private var topbar: some View {
        NeoSubscreenHeader(
            title: current.createdAt.formatted(date: .abbreviated, time: .omitted),
            subtitle: current.createdAt.formatted(date: .omitted, time: .shortened),
            backLabel: "Back",
            plainControls: true,
            titleEmphasis: .topbar,
            horizontalPadding: 18,
            bottomPadding: 14,
            onBack: onDismiss
        ) {
            NeoPlainIconButton(systemImage: "ellipsis", accessibilityLabel: "Photo options") {
                showOptions = true
            }
        }
    }

    /// Prototype `.action-tray` / `.action-grid`: 3-up evenly divided labelled icon actions on the cream canvas.
    private var actionTray: some View {
        HStack(spacing: 4) {
            shareAction
            saveAction
            trashAction
        }
        .padding(.horizontal, AIPoseSpacing.md)
        .padding(.top, 18)
        .padding(.bottom, AIPoseSpacing.lg)
    }

    @ViewBuilder private var shareAction: some View {
        Button { prepareShare() } label: {
            GalleryTrayActionLabel(
                title: isPreparingShare ? "Preparing…" : "Share",
                systemImage: "square.and.arrow.up"
            )
        }
        .buttonStyle(.plain)
        .disabled(isPreparingShare)
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
        saveStatus = nil
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
                saveStatus = GallerySharePreparation.Failure.sourceMissing(item.fileURL.lastPathComponent).localizedDescription
            }
        }
    }

    private var saveAction: some View {
        Button { saveCurrentToPhotos() } label: {
            GalleryTrayActionLabel(title: isSaving ? "Saving…" : "Save", systemImage: "arrow.down.to.line")
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .accessibilityLabel(isSaving ? "Saving to Photos" : "Save to Photos")
    }

    private var trashAction: some View {
        Button(role: .destructive) { confirmDelete = true } label: {
            GalleryTrayActionLabel(title: "Trash", systemImage: "trash", tint: AIPoseColor.error)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete photo")
    }

    /// Save reuses the existing Photos export port (`PhotosExporter`); the outcome is reported honestly.
    private func saveCurrentToPhotos() {
        guard !isSaving else { return }
        let item = current
        isSaving = true
        saveStatus = nil
        Task {
            let saved = await PhotosExporter.saveImage(at: item.fileURL)
            await MainActor.run {
                isSaving = false
                saveStatus = PhotosExporter.confirmation(saved: saved)
            }
        }
    }
}

/// Vertical icon + 11pt bold label used by the detail v2 action tray (min height 70pt, no chrome, radius 14 tap shape).
struct GalleryTrayActionLabel: View {
    let title: String
    let systemImage: String
    var tint: Color = AIPoseColor.foreground

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .regular))
            Text(title)
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, minHeight: 70)
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}
