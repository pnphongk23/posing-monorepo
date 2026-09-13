import Kingfisher
import SwiftUI

enum PoseLibraryFilter: String, CaseIterable, Identifiable {
    case all = "All poses"
    case saved = "My poses"
    case community = "Community"
    var id: String { rawValue }
}

enum SearchScreenContract {
    static let recentSearches = ["Dancing", "Stretching", "Warrior"]
    static let sourceFilters: [PoseLibraryFilter] = [.all, .saved, .community]
}

/// User-visible chrome copy for the Search results panel (prototype `.nb-search-results-header`,
/// `.nb-search-kicker`, `.nb-search-results-count`) and the basic-design empty state SCR-003-02-ST-003.
/// Pure and testable: views call these instead of hardcoding strings.
enum SearchResultsCopy {
    static let screenTitle = "Search"
    static let kicker = "YOUR MATCHES"

    /// `Results` in the blank/reset state; `Results for “<query>”` once a query is confirmed.
    static func heading(query: String) -> String {
        let trimmed = trimmedQuery(query)
        return trimmed.isEmpty ? "Results" : "Results for “\(trimmed)”"
    }

    static func countLabel(for state: Loadable<[NativePose]>) -> String {
        switch state {
        case .idle, .loading:
            return "Searching…"
        case .empty:
            return "0 poses"
        case .failed:
            return "Unavailable"
        case .loaded(let poses):
            return poses.count == 1 ? "1 pose" : "\(poses.count) poses"
        }
    }

    /// `app.js:777` — `searchSource === 'my-poses' ? 'My poses' : searchSource === 'community' ? 'Community' : ''`.
    /// `app.js:846` substitutes `this library` when that label is empty (the All source).
    static func sourceLabel(for filter: PoseLibraryFilter) -> String {
        switch filter {
        case .saved: return "My poses"
        case .community: return "Community"
        case .all: return "this library"
        }
    }

    /// `app.js:845` — `query ? 'No poses match “<query>”' : 'No poses in <sourceLabel.toLocaleLowerCase() || 'this library'> yet'`.
    static func emptyTitle(query: String, filter: PoseLibraryFilter) -> String {
        let trimmed = trimmedQuery(query)
        if !trimmed.isEmpty { return "No poses match “\(trimmed)”" }
        // `toLocaleLowerCase()` in the prototype — `My poses` -> `my poses`, `Community` -> `community`.
        return "No poses in \(sourceLabel(for: filter).lowercased()) yet"
    }

    /// `app.js:846` — exactly `Try a different pose name.` with a query, `Choose another source to
    /// continue.` without one. The prototype appends nothing else; an earlier native string restated
    /// the title and added a `clear the search` instruction the prototype never renders.
    static func emptyMessage(query: String, filter: PoseLibraryFilter) -> String {
        trimmedQuery(query).isEmpty ? "Choose another source to continue." : "Try a different pose name."
    }

    /// `app.js:847-849` — the action is `null` when a query is present **or** the source is All; the
    /// only card action is `Show all poses` on the no-query, non-All branch. The search field keeps
    /// its own clear/X affordance, which is separate and stays.
    static func emptyRecoveryTitle(query: String, filter: PoseLibraryFilter) -> String? {
        guard trimmedQuery(query).isEmpty, filter != .all else { return nil }
        return "Show all poses"
    }

    /// `app.js:837` — `searchResultsCount.hidden = filtered.length === 0`; the reference
    /// `search-no-match.png` renders the header without any count.
    static func hidesCount(for state: Loadable<[NativePose]>) -> Bool {
        if case .empty = state { return true }
        return false
    }

    private static func trimmedQuery(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// User-visible copy for the Poses library state surfaces (report §3.4, `poses-list.html`).
/// Pure and testable: views call these instead of hardcoding strings.
enum PosesListStateCopy {
    static let loadingTitle = "Loading poses"
    static let loadingMessage = "Getting the pose library ready."
    static let emptyTitle = "No poses yet"
    static let emptyMessage = "New poses will appear here when they're available."
    static let errorTitle = "Couldn't load poses"
    static let errorMessage = "Check your connection and try again."
    static let retryActionTitle = "Try again"
}

/// User-visible copy for the `PoseResultsList` transient states, per owner surface:
/// `search.html` (report §3.5) vs `saved-list.html` (report §3.8).
/// Pure and testable: views call these instead of hardcoding strings.
enum PoseResultsStateCopy {
    static let retryActionTitle = "Try again"

    // MARK: Search (`search.html` §3.5)
    static let searchLoadingTitle = "Searching"
    static let searchLoadingMessage = "Looking through your library and the community."
    static let searchErrorTitle = "Search is paused"
    static let searchErrorMessage = "We could not load results right now. Your query is still here."

    // MARK: Saved (`saved-list.html` §3.8)
    static let savedLoadingTitle = "Loading saved poses"
    static let savedLoadingMessage = "Getting your saved collection ready."
    static let savedErrorTitle = "Couldn't load saved poses"
    static let savedErrorMessage = "Check your connection and try again."
    static let savedEmptyTitle = "No saved poses yet"
    static let savedEmptyMessage = "Save poses from Community to find them here."
    static let browseCommunityActionTitle = "Browse Community"
}

/// Low-intensity motion for the Search discovery/results state change (SCR-003-02 "Motion and animation").
/// Reduce Motion turns every state change instant; motion is never the only source of information.
enum SearchMotion {
    static let stateChangeDuration: TimeInterval = 0.18

    static func animation(reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        return .easeInOut(duration: stateChangeDuration)
    }
}

protocol PoseBookmarkServing: Sendable {
    func savePose(poseId: String) async throws
    func unsavePose(poseId: String) async throws
}

struct PoseAPIBookmarkService: PoseBookmarkServing {
    let api: PoseAPIService
    func savePose(poseId: String) async throws { _ = try await api.savePose(poseId: poseId) }
    func unsavePose(poseId: String) async throws { try await api.unsavePose(poseId: poseId) }
}

@MainActor final class PosesViewModel: ObservableObject {
    @Published var state: Loadable<[NativePose]> = .idle
    @Published var query = ""
    @Published var filter: PoseLibraryFilter = .community
    private let service: any PoseServing
    let bookmarkService: (any PoseBookmarkServing)?
    private let filterState: PoseFilterState?
    private var searchTask: Task<Void, Never>?
    private var debounceNanoseconds: UInt64 = 350_000_000

    init(
        service: any PoseServing,
        bookmarkService: (any PoseBookmarkServing)? = nil,
        filterState: PoseFilterState? = nil,
        debounceNanoseconds: UInt64 = 350_000_000
    ) {
        self.service = service
        self.bookmarkService = bookmarkService
        self.filterState = filterState
        self.debounceNanoseconds = debounceNanoseconds
    }

    convenience init(bundle: PoseServiceBundle, debounceNanoseconds: UInt64 = 350_000_000) {
        self.init(
            service: bundle.service,
            bookmarkService: bundle.bookmarkService,
            filterState: bundle.filterState,
            debounceNanoseconds: debounceNanoseconds
        )
    }

    /// Typing path: writes the field text and debounces the search (prototype SCR-003-02 350 ms).
    /// The view calls this from the field's `Binding` setter so the debounce has exactly one owner.
    func updateQuery(_ value: String) {
        query = value
        scheduleSearch()
    }

    func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.debounceNanoseconds)
            guard !Task.isCancelled else { return }
            await self.load()
        }
    }

    /// Drops a debounced search that has not fired yet.
    func cancelPendingSearch() {
        searchTask?.cancel()
        searchTask = nil
    }

    /// Recent-search chip entry (prototype `data-search-query` chips): fills the field with `term`
    /// and searches immediately instead of waiting out the typing debounce.
    func startSearch(for term: String) async {
        cancelPendingSearch()
        filter = .all
        query = term
        await load()
    }

    func load() async {
        state = .loading
        filterState?.filter = filter
        do {
            let values = try await service.poses(query: query.isEmpty ? nil : query)
            state = values.isEmpty ? .empty : .loaded(values)
        } catch {
            state = .failed(ErrorCopy.text(for: error) ?? "Unable to load poses.")
        }
    }

    func toggleSaved(for pose: NativePose) async {
        guard let bookmarkService else { return }
        do {
            if pose.isSaved { try await bookmarkService.unsavePose(poseId: pose.id) }
            else { try await bookmarkService.savePose(poseId: pose.id) }
            await load()
        } catch {
            state = .failed(ErrorCopy.text(for: error) ?? "Unable to update this pose.")
        }
    }

    func updateSavedLocally(poseID: String, saved: Bool) {
        guard case .loaded(var poses) = state else { return }
        guard let index = poses.firstIndex(where: { $0.id == poseID }) else { return }
        poses[index].isSaved = saved
        let filtered = filter == .saved ? poses.filter(\.isSaved) : poses
        state = filtered.isEmpty ? .empty : .loaded(filtered)
    }

    /// Pose detail availability check (report §3.6, `pose-detail.html` unavailable state): a detail
    /// route is only valid while the pose still resolves through the service. Only the definitive
    /// `poseNotFound` signal flips the screen; an inconclusive failure (offline, 5xx) must never
    /// demote a working detail to "unavailable".
    func confirmPublished(_ pose: NativePose) async -> Bool {
        do {
            _ = try await service.pose(id: pose.id)
            return true
        } catch let error as PoseAdapterError {
            if case .poseNotFound = error { return false }
            return true
        } catch {
            return true
        }
    }
}

// MARK: - Prototype metrics (single source of truth, in pt)

/// Measurements read from `docs/prototype/styles/**` and verified against the regenerated
/// 390x844 reference shots (`docs/prototype/screenshots/reference/*.png`).
///
/// NOTE: prototype token names do NOT line up with `AIPoseSpacing` (`--nb-space-md` is 16px but
/// `AIPoseSpacing.md` is 12pt), so the prototype-derived numbers below are absolute points.
enum PoseSurfaceMetrics {
    /// `.nb-phone__content { padding: 0 16px }`
    static let horizontalPadding: CGFloat = 16
    /// `.nb-card--pose-grid`: `border: 2px solid #000; border-radius: 14px; box-shadow: none`
    static let cardBorderWidth: CGFloat = 2
    static let cardCornerRadius: CGFloat = 14
    static let cardPadding: CGFloat = 16
    /// `.nb-grid-pose-item { gap: 4px }` + `.nb-grid-pose-label` (14px regular, outside the card).
    static let cardLabelSpacing: CGFloat = 4
    /// `.nb-search-chip / .nb-search-filter { border: 1.5px solid; border-radius: 10px }`
    static let chipBorderWidth: CGFloat = 1.5
    static let chipCornerRadius: CGFloat = 10
    /// `.nb-search-field { min-height: 56px; border: 2px; border-radius: 14px; box-shadow: 3px 3px 0 }`
    static let searchFieldMinHeight: CGFloat = 56
    static let searchFieldCornerRadius: CGFloat = 14
    /// `.nb-search-form { margin: 0 0 32px }`
    static let searchFormBottomMargin: CGFloat = 32
    /// `.nb-nav-bar { height: 52px }` + `#pose-search .nb-search-nav { margin-bottom: 24px }`
    static let navBarHeight: CGFloat = 52
    static let navBarBottomMargin: CGFloat = 24
    /// `.nb-touch-min`
    static let touchMinimum: CGFloat = 44
}

/// Grid metrics for the 2-column pose grid (`.nb-grid--masonry`, `components/grid.css`).
enum PoseGridMetrics {
    static let horizontalPadding = PoseSurfaceMetrics.horizontalPadding
    /// `.nb-grid--masonry { column-gap: 8px }`
    static let columnSpacing: CGFloat = 8
    /// `.nb-grid--masonry .nb-grid-pose-item { margin-bottom: calc(16px * 0.8) }`
    static let rowSpacing = PoseSurfaceMetrics.cardPadding * 0.8
    /// `app.js createPoseCard` cycles `.nb-card--aspect-{tall,square,short}`; with two columns the
    /// prototype's balanced `column-count: 2` lands one aspect per visual row, which is what the
    /// reference shots show (`poses-list.png` = tall/square/short rows, `search-results.png` =
    /// a single `tall` card for the first result).
    private static let rowAspects: [CGFloat] = [1 / 1.25, 1, 1.25]

    static func aspectRatio(forRow row: Int) -> CGFloat {
        rowAspects[row % rowAspects.count]
    }

    /// The box a card's artwork is *actually drawn* in — the target for `AppImage.downsample(points:)`.
    /// One grid column (screen − 2×16 content padding − 8 column gap, halved) minus the card's 16pt
    /// artwork inset, and as tall as the tallest card aspect (`1 / 1.25`). Derived from the live screen
    /// width so a larger phone gets a proportionally larger bitmap instead of an upscaled one.
    ///
    /// Asking Kingfisher for anything bigger than this (let alone the file's own size) is what made a
    /// 12-cell screenful decode tens of megapixels on the main thread while scrolling.
    @MainActor static var cardArtworkPoints: CGSize {
        let column = (UIScreen.main.bounds.width - 2 * horizontalPadding - columnSpacing) / 2
        let tallest = column / rowAspects[0]
        return CGSize(
            width: column - 2 * PoseSurfaceMetrics.cardPadding,
            height: tallest - 2 * PoseSurfaceMetrics.cardPadding
        )
    }

    /// Dock (48) + 16 bottom + safe area (34 on iPhone 13) keeps the last row clear of the dock.
    static let dockClearance: CGFloat = 48 + 16 + 34
    /// `.nb-search-discovery` / `.nb-search-results-scroll { padding-bottom: calc(40px + safe-area) }`
    static let searchDockClearance: CGFloat = 40 + 34
}

// MARK: - Poses

struct PosesScreen: View {
    @StateObject var model: PosesViewModel
    @ObservedObject private var purchaseState = RevenueCatAdapter.shared
    var onTryPose: (NativePose) -> Void = { _ in }
    /// Lets `AppFeatureRoot` hide the dock's active pill while the Search overlay is up: Search is
    /// not a tab, and `reference/search-blank.png` shows both dock items plain grey.
    var onSearchVisibilityChange: (Bool) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The Search workspace is presented **in place** instead of being pushed on the stack.
    ///
    /// `AppFeatureRoot` overlays `NeoDockTabBar` on top of its `<tab>Root`, so a `NavigationLink`
    /// push replaces the root view and the dock disappears with it (verified on device; the
    /// `lucton-search-pushed-*` shots show the dock missing). The prototype `screens/search.html`
    /// keeps the dock visible, and nothing inside `RootNavigation` can redraw it — only
    /// `AppFeatureRoot` owns the dock — so the Search screen is overlaid here, where the root ZStack
    /// still paints the dock above it.
    @State private var showsSearch = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                posesHeader
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            if showsSearch {
                // Short states (e.g. the no-match banner) must not let the ZStack centre the overlay.
                SearchScreen(model: model, onClose: { setShowsSearch(false) })
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            }
        }
        // R8: the page title now lives in the single in-content row (`.nb-nav-bar--poses`), so the
        // centred system nav-bar title is gone; keeping both would render the title twice.
        .neoHiddenNavigationBar()
        .background(AIPoseColor.background)
        .task { if case .idle = model.state { await model.load() } }
        .onChange(of: model.filter) { _ in Task { await model.load() } }
    }

    private func setShowsSearch(_ shown: Bool) {
        withAnimation(SearchMotion.animation(reduceMotion: reduceMotion)) { showsSearch = shown }
        onSearchVisibilityChange(shown)
    }

    /// ONE row: left-aligned page title plus the four page actions, per `nav-bar.css:60-80`
    /// (`.nb-nav-bar--poses` — flex, `align-items: center`, `justify-content: flex-start`, gap 8,
    /// `height: 52px`, `margin-bottom: var(--nb-space-md)`; the title is `text-align: left` and the
    /// action group is `margin-left: auto`).
    ///
    /// `reference/poses-list.png` proves the shape: one 67px band at dsf2 (y=112..178) with the
    /// title ink left-aligned at x=39. The previous two-row render (centred system nav-bar title plus
    /// a separate actions row) was justified by a comment about three `My poses`/`Community` category
    /// pills needing 297.7pt beside four 32pt actions. AC2 deleted those pills (report §3.4), so that
    /// constraint is gone and the justification was stale — which is how the two-row header survived
    /// implementation and review. Title ~54pt + actions ~171pt now fit a 390pt screen with room to
    /// spare. `Create Pose` is not part of this surface (§3.4).
    private var posesHeader: some View {
        HStack(spacing: AIPoseSpacing.sm) {
            // `.nb-nav-bar__center { flex: 1 1 auto }` with a left-aligned title.
            Text("Poses")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(AIPoseColor.foreground)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            if purchaseState.lastSnapshot.state != .entitled {
                NavigationLink(destination: PaywallScreen()) {
                    PosesHeaderIconLabel(systemImage: "crown.fill", fill: AIPoseColor.accentYellow)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Upgrade to Premium")
            }

            Button { setShowsSearch(true) } label: {
                PosesHeaderIconLabel(systemImage: "magnifyingglass")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search")
            .accessibilityIdentifier("poses.open-search")

            NavigationLink(destination: SavedPosesScreen(model: model, onTryPose: onTryPose)) {
                PosesHeaderIconLabel(systemImage: "bookmark.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Saved poses")

            NavigationLink(destination: SettingsScreen(posesModel: model, onTryPose: onTryPose)) {
                PosesHeaderIconLabel(systemImage: "gearshape.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Settings")
        }
        // `.nb-nav-bar { height: 52px; margin-bottom: 16px }`.
        .frame(height: 52)
        .padding(.horizontal, AIPoseSpacing.lg)
        .padding(.bottom, AIPoseSpacing.lg)
    }

    /// State cards render in flow at the top of the content column — `poses-list.html` mounts
    /// `.nb-state-message` inside `.nb-phone__content` (16pt side padding, no centring) — and the
    /// frozen `FeatureStateView` is a full-width top-anchored card with no icon slot.
    @ViewBuilder private var content: some View {
        // The card tone is read from the pure `Loadable.stateTone` mapper rather than restated per
        // branch, so the tone a screen produces for a condition is verifiable in a unit test even
        // when the UI state cannot be driven (Saved signed-in states in the parity rig).
        switch model.state.stateTone {
        case .some(.loading):
            FeatureStateView(
                tone: .loading,
                title: PosesListStateCopy.loadingTitle,
                message: PosesListStateCopy.loadingMessage
            )
            .padding(.horizontal, PoseGridMetrics.horizontalPadding)
        case .some(.empty):
            // §3.4: the empty state has no personal Create CTA — poses appear when available.
            FeatureStateView(
                tone: .empty,
                title: PosesListStateCopy.emptyTitle,
                message: PosesListStateCopy.emptyMessage
            )
            .padding(.horizontal, PoseGridMetrics.horizontalPadding)
        case .some(.error):
            FeatureStateView(
                tone: .error,
                title: PosesListStateCopy.errorTitle,
                message: PosesListStateCopy.errorMessage,
                actionTitle: PosesListStateCopy.retryActionTitle
            ) {
                Task { await model.load() }
            }
            .padding(.horizontal, PoseGridMetrics.horizontalPadding)
        // `stateTone` cannot be these for a `Loadable`; listed so the switch stays exhaustive.
        case .some(.offline), .some(.success), .some(.warning):
            EmptyView()
        case nil:
            if case .loaded(let poses) = model.state {
                ScrollView {
                    // §3.4: the visible "<N> poses" catalogue count is removed with the tablist.
                    PoseGrid(poses: poses, model: model, onTryPose: onTryPose)
                        .padding(.horizontal, PoseGridMetrics.horizontalPadding)
                        .padding(.bottom, PoseGridMetrics.dockClearance)
                }
            }
        }
    }
}

/// Prototype `.nb-btn__compact-surface`: a 32pt boxed surface.
private struct PosesHeaderIconLabel: View {
    let systemImage: String
    var fill: Color = AIPoseColor.surface
    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(AIPoseColor.foreground)
            .frame(width: 32, height: 32)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(AIPoseColor.foreground, lineWidth: 1.5))
    }
}

// MARK: - Pose card

/// Prototype `.nb-card--pose-grid` + `.nb-grid-pose-item` (`components/card.css`, `components/grid.css`):
/// square-ish white surface, 2pt black border, radius 14, **no shadow**, artwork centred with 16pt
/// padding, and the pose name rendered *outside* the card as a 14pt regular left-aligned label.
/// The category is intentionally not shown (neither reference shot has it).
struct PoseCard: View {
    let pose: NativePose
    var aspectRatio: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: PoseSurfaceMetrics.cardLabelSpacing) {
            cardSurface
            Text(pose.name)
                .font(.system(size: 14))
                .foregroundStyle(AIPoseColor.foreground)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                // `.nb-grid-pose-label { align-self: flex-start; padding-left: 2px }`
                .padding(.leading, 2)
        }
    }

    private var cardSurface: some View {
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay { artwork.padding(PoseSurfaceMetrics.cardPadding) }
            .background(AIPoseColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: PoseSurfaceMetrics.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: PoseSurfaceMetrics.cardCornerRadius)
                    .stroke(AIPoseColor.foreground, lineWidth: PoseSurfaceMetrics.cardBorderWidth)
            )
            .overlay(alignment: .topTrailing) { savedBadge }
    }

    /// Pose artwork: Kingfisher + `AppImage` downsample to the box the card actually draws.
    /// Two-tier cache (memory 64MB / disk 200MB, `AppImage.configure()`), decode off the main thread,
    /// request coalescing — so re-rendering a grid cell never re-decodes the photo. `AsyncImage` here
    /// meant a full-resolution decode inside the view body, on every render.
    private var artwork: some View {
        KFImage(pose.imageURL)
            .setProcessor(AppImage.downsample(points: PoseGridMetrics.cardArtworkPoints, contentMode: .fit))
            .placeholder {
                Image(systemName: "figure.stand")
                    .font(.system(size: 44))
                    .foregroundStyle(AIPoseColor.subtext)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .resizable()
            .scaledToFit()
    }

    /// `saved-list.html` marks saved cards with `.nb-saved-card__badge` (24pt pink square, top-right).
    @ViewBuilder private var savedBadge: some View {
        if pose.isSaved {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AIPoseColor.foreground)
                .frame(width: 24, height: 24)
                .background(AIPoseColor.primary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(AIPoseColor.foreground, lineWidth: 1.5))
                .padding(8)
                .accessibilityHidden(true)
        }
    }
}

/// Prototype `.nb-grid--masonry`: two fixed columns, 8pt column gap, `nb-space-md * 0.8` row gap.
struct PoseGrid: View {
    let poses: [NativePose]
    @ObservedObject var model: PosesViewModel
    var onTryPose: (NativePose) -> Void = { _ in }

    private static let columns = [
        GridItem(.flexible(), spacing: PoseGridMetrics.columnSpacing),
        GridItem(.flexible(), spacing: PoseGridMetrics.columnSpacing),
    ]

    var body: some View {
        LazyVGrid(columns: Self.columns, spacing: PoseGridMetrics.rowSpacing) {
            ForEach(Array(poses.enumerated()), id: \.element.id) { index, pose in
                NavigationLink(destination: PoseDetailScreen(pose: pose, model: model, onTryPose: onTryPose)) {
                    PoseCard(pose: pose, aspectRatio: PoseGridMetrics.aspectRatio(forRow: index / 2))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

enum PoseDetailLayoutMetrics {
    /// Footprint of the shared root NeoDockTabBar overlay (48pt bar + 8pt padding + breathing room).
    /// Retained as the dock-parity reference; the dock is hidden on this pushed route.
    static let sharedDockScrollInset: CGFloat = 48 + AIPoseSpacing.sm + AIPoseSpacing.lg

    /// Artwork box of the detail hero card on a 390pt-wide phone: card = content width (390 − 2×16)
    /// with a `1 / 1.1` aspect, inset by the card's 24pt padding → 310×346pt. The `AppImage.downsample`
    /// target for `poseHeroCard` (a single big image, so a touch of slack costs nothing).
    static let heroArtworkPoints = CGSize(width: 310, height: 346)
}

struct PoseDetailScreen: View {
    let pose: NativePose
    @ObservedObject var model: PosesViewModel
    var onTryPose: (NativePose) -> Void
    @State private var isSaved: Bool
    @State private var showsPaywall = false
    @State private var pendingSignIn: SignInIntent?
    /// Report §3.6 (`pose-detail.html` unavailable state): set only by the definitive
    /// `poseNotFound` signal from `PosesViewModel.confirmPublished` — a stale/deleted pose renders
    /// the shared error state instead of dead detail content.
    @State private var isUnavailable = false
    @Environment(\.dismiss) private var dismiss
    private let boundary = ServiceLocator.sessionBoundary
    init(pose: NativePose, model: PosesViewModel, onTryPose: @escaping (NativePose) -> Void) {
        self.pose = pose
        self.model = model
        self.onTryPose = onTryPose
        _isSaved = State(initialValue: pose.isSaved)
    }
    var body: some View {
        VStack(spacing: 0) {
            if isUnavailable {
                unavailableState
            } else {
                detailContent
            }
        }
        // R2: `unavailableState` is a header plus one short card, so without this the whole subscreen
        // collapses to the card's height and centres, putting the back button mid-screen.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AIPoseColor.background)
        .neoHiddenNavigationBar()
        .sheet(isPresented: $showsPaywall) { PaywallScreen() }
        // Saving is account-scoped, so a guest is asked to sign in and the interrupted save
        // resumes once — never silently dropped, never replayed later (FEAT-013 sign-in gating).
        .signInPrompt($pendingSignIn) { intent in
            guard intent == .savePose else { return }
            Task { await toggleBookmark() }
        }
        .task {
            // §3.6: a detail route is only valid while the pose is still confirmed as published.
            if !(await model.confirmPublished(pose)) { isUnavailable = true }
        }
    }

    private var detailContent: some View {
        VStack(spacing: 0) {
            NeoSubscreenHeader(title: pose.name, onBack: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    poseHeroCard
                    Text(pose.name).font(.largeTitle.bold())
                    Text(pose.category).foregroundStyle(AIPoseColor.subtext)
                    ForEach(Array(pose.instructions.enumerated()), id: \.offset) { index, step in
                        Label("\(index + 1). \(step)", systemImage: "sparkles")
                    }
                    HStack(spacing: AIPoseSpacing.md) {
                        Button { Task { await toggleBookmark() } } label: {
                            Label(isSaved ? "Saved" : "Save pose", systemImage: isSaved ? "bookmark.fill" : "bookmark")
                        }.buttonStyle(NeoButtonStyle(fill: isSaved ? AIPoseColor.accentYellow : AIPoseColor.surface))
                        Button {
                            switch poseTryPoseDestination(
                                hasPremiumAccess: RevenueCatAdapter.shared.lastSnapshot.state == .entitled
                            ) {
                            case .camera:
                                onTryPose(pose)
                            case .paywall:
                                showsPaywall = true
                            }
                        } label: {
                            Label("Use this pose", systemImage: "camera")
                        }.buttonStyle(NeoButtonStyle())
                    }
                }.padding()
            }
        }
    }

    /// Report §3.6: the shared error state for a pose that is no longer confirmed as published,
    /// with the `Return to Poses` recovery action (this screen is always pushed, so dismissal is
    /// the honest route back). The frozen component is top-anchored with no icon slot.
    private var unavailableState: some View {
        VStack(spacing: 0) {
            NeoSubscreenHeader(title: "Pose unavailable", onBack: { dismiss() })
            FeatureStateView(
                tone: .error,
                title: "Pose unavailable",
                message: "This pose could not be confirmed as published. Return to Poses and try again.",
                actionTitle: "Return to Poses"
            ) {
                dismiss()
            }
            .padding(.horizontal, PoseSurfaceMetrics.horizontalPadding)
            .accessibilityIdentifier("poseDetail.returnToPoses")
        }
    }

    /// Prototype `pose-detail.html` `.nb-card.nb-card--pose-detail` (card.css): white card,
    /// `aspect-ratio: 1 / 1.1`, thick border, radius 14, `box-shadow: none` and artwork inset
    /// by `--nb-space-lg` (24pt). Uses the live `pose.imageURL` only.
    ///
    /// The photo is loaded with Kingfisher through `AppImage` and downsampled to the drawn box
    /// (memory + disk cache, decode off the main thread); a full-resolution decode here would stall
    /// the pushed screen for ~20-40ms on every appearance.
    private var poseHeroCard: some View {
        KFImage(pose.imageURL)
            .setProcessor(AppImage.downsample(points: PoseDetailLayoutMetrics.heroArtworkPoints, contentMode: .fit))
            .placeholder {
                AIPoseColor.primary100.frame(height: 340).overlay(Image(systemName: "figure.stand").font(.system(size: 72)))
            }
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: Self.heroCardCornerRadius))
        .padding(AIPoseSpacing.xl)
        .aspectRatio(1 / 1.1, contentMode: .fit)
        .background(AIPoseColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: Self.heroCardCornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Self.heroCardCornerRadius).stroke(AIPoseColor.foreground, lineWidth: 2))
    }

    private static let heroCardCornerRadius: CGFloat = 14

    private func toggleBookmark() async {
        let next = !isSaved
        guard await boundary.hasStoredSession() else {
            pendingSignIn = .savePose
            return
        }
        if model.bookmarkService != nil {
            await model.toggleSaved(for: pose.withSaved(isSaved))
            isSaved = next
        } else {
            isSaved = next
            model.updateSavedLocally(poseID: pose.id, saved: next)
        }
    }
}

enum PoseTryPoseDestination: Equatable {
    case camera
    case paywall
}

func poseTryPoseDestination(hasPremiumAccess: Bool) -> PoseTryPoseDestination {
    hasPremiumAccess ? .camera : .paywall
}

// MARK: - Search

/// Prototype `screens/search.html` (`.nb-search-screen`): full-height workspace with a 52pt nav bar,
/// a 56pt search field, and either `.nb-search-discovery` (blank) or `.nb-search-results-panel`.
/// The dock tab bar is drawn by `AppFeatureRoot` above this screen, so the scroll areas only need to
/// reserve `40px + safe-area` at the bottom (see `PoseGridMetrics.searchDockClearance`).
struct SearchScreen: View {
    @ObservedObject var model: PosesViewModel
    /// Supplied when the workspace is overlaid in place (keeps the dock tab bar visible);
    /// falls back to the navigation `dismiss` action when it is pushed instead.
    var onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFieldFocused: Bool
    @State private var selectedSource: PoseLibraryFilter = .all

    var body: some View {
        VStack(spacing: 0) {
            SearchNavHeader(title: SearchResultsCopy.screenTitle, onBack: close)
            searchField
            if showsDiscovery {
                discovery
            } else {
                resultsPanel
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AIPoseColor.background)
        .animation(SearchMotion.animation(reduceMotion: reduceMotion), value: showsDiscovery)
        .animation(SearchMotion.animation(reduceMotion: reduceMotion), value: model.state.panelStateKey)
        .neoHiddenNavigationBar()
        .task {
            selectedSource = .all
            model.filter = .all
            await model.load()
        }
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    // MARK: search field (`.nb-search-field`)

    private var searchField: some View {
        HStack(spacing: 4) {
            // The prototype's SVG glyph is inset ~4pt inside its 20px box; SF Symbols are not.
            Image(systemName: "magnifyingglass")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(AIPoseColor.foreground)
                .frame(width: 20, height: 20)
                .padding(.leading, 4)

            TextField("Search poses", text: Binding(get: { model.query }, set: { model.updateQuery($0) }))
                .font(.system(size: 16))
                .foregroundStyle(AIPoseColor.foreground)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .submitLabel(.search)
                .frame(minHeight: PoseSurfaceMetrics.touchMinimum)
                .focused($isFieldFocused)
                .onSubmit {
                    // Pressing the keyboard's Search key only dismisses the keyboard (standard iOS
                    // search behaviour). The debounced search has already run for this query; calling
                    // `load()` again would rebuild the grid and flash placeholders over artwork that
                    // is already loaded. If the user submits inside the debounce window, the pending
                    // scheduled search still fires.
                    isFieldFocused = false
                }
                .accessibilityIdentifier("search.field")

            if !model.query.isEmpty {
                Button { clearSearch() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(AIPoseColor.foreground)
                        .frame(width: PoseSurfaceMetrics.touchMinimum, height: PoseSurfaceMetrics.touchMinimum)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        // `.nb-search-field { padding: 4px 4px 4px 12px; min-height: 56px }`
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .frame(minHeight: PoseSurfaceMetrics.searchFieldMinHeight)
        .background(AIPoseColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: PoseSurfaceMetrics.searchFieldCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: PoseSurfaceMetrics.searchFieldCornerRadius)
                .stroke(AIPoseColor.foreground, lineWidth: 2)
        )
        // `:focus-within { transform: translate(-1.5px,-1.5px); box-shadow: shadow-small }`
        .shadow(color: AIPoseColor.foreground, radius: 0, x: isFieldFocused ? 1.5 : 3, y: isFieldFocused ? 1.5 : 3)
        .offset(x: isFieldFocused ? -1.5 : 0, y: isFieldFocused ? -1.5 : 0)
        .padding(.horizontal, PoseSurfaceMetrics.horizontalPadding)
        .padding(.bottom, PoseSurfaceMetrics.searchFormBottomMargin)
    }

    private func clearSearch() {
        withAnimation(SearchMotion.animation(reduceMotion: reduceMotion)) {
            selectedSource = .all
            model.filter = .all
        }
        model.cancelPendingSearch()
        Task { await model.startSearch(for: "") }
    }

    // MARK: discovery (`.nb-search-discovery`)

    private var showsDiscovery: Bool {
        model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedSource == .all
    }

    private var discovery: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Recent searches")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AIPoseColor.foreground)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)

                HStack(spacing: 8) {
                    ForEach(SearchScreenContract.recentSearches, id: \.self) { term in
                        SearchChip(title: term) { Task { await model.startSearch(for: term) } }
                            .accessibilityIdentifier("search.recent.\(term.lowercased())")
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, PoseSurfaceMetrics.horizontalPadding)
            .padding(.bottom, PoseGridMetrics.searchDockClearance)
        }
    }

    // MARK: results (`.nb-search-results-panel`)

    private var resultsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Prototype `#search-state-message` (`.nb-state-message.nb-search-state`) sits between the
            // search form and the results panel; the prototype hides the grid when nothing matches.
            if case .empty = model.state { noMatchBanner }
            resultsHeader
            filterRow
            PoseResultsList(
                model: model,
                context: .search,
                bottomInset: PoseGridMetrics.searchDockClearance,
                emptyPresentation: .hidden
            )
        }
    }

    /// `.nb-state-message.nb-search-state` (report §3.5 no-match): the frozen shared card carries
    /// the tone surface, structure and a11y; copy stays `SearchResultsCopy`. The wrapper adds 8pt of
    /// bottom padding because `.nb-search-state { margin: 0 0 16px }` on top of the component's own
    /// 8pt bottom margin makes the prototype's 16px total.
    private var noMatchBanner: some View {
        FeatureStateView(
            tone: .empty,
            title: SearchResultsCopy.emptyTitle(query: model.query, filter: model.filter),
            message: SearchResultsCopy.emptyMessage(query: model.query, filter: model.filter),
            actionTitle: SearchResultsCopy.emptyRecoveryTitle(query: model.query, filter: model.filter)
        ) {
            // `app.js:848` `Show all poses` -> `setSource('all')`, the same path the source chip takes.
            withAnimation(SearchMotion.animation(reduceMotion: reduceMotion)) {
                selectedSource = .all
                model.filter = .all
            }
            Task { await model.load() }
        }
        .padding(.horizontal, PoseSurfaceMetrics.horizontalPadding)
        .padding(.bottom, 8)
        .accessibilityIdentifier("search-empty-banner")
    }

    /// `.nb-search-results-header`: kicker + heading left, count right, `margin-bottom: 16px`.
    private var resultsHeader: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(SearchResultsCopy.kicker)
                    .font(.system(size: 12, weight: .bold))
                    .kerning(0.72)
                    .foregroundStyle(AIPoseColor.subtext)
                    .accessibilityIdentifier("search-results-kicker")
                Text(SearchResultsCopy.heading(query: model.query))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AIPoseColor.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityIdentifier("search-results-heading")
            }
            Spacer(minLength: 0)
            // R12: `app.js:837` hides the count at zero, and `search-no-match.png` shows the header
            // with no count. The label function is unchanged; only its visibility is conditional.
            if !SearchResultsCopy.hidesCount(for: model.state) {
                Text(SearchResultsCopy.countLabel(for: model.state))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AIPoseColor.subtext)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .frame(maxWidth: 110, alignment: .trailing)
                    .accessibilityIdentifier("search-results-count")
            }
        }
        .padding(.horizontal, PoseSurfaceMetrics.horizontalPadding)
        .padding(.bottom, 16)
    }

    /// `.nb-search-filter-row { gap: 4px; padding: 2px 2px 6px; margin-bottom: 16px }`.
    /// No "Source" heading — the prototype has none.
    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(SearchScreenContract.sourceFilters) { source in
                    SearchChip(title: source.rawValue, kind: .filter, isActive: selectedSource == source) {
                        withAnimation(SearchMotion.animation(reduceMotion: reduceMotion)) {
                            selectedSource = source
                            model.filter = source
                        }
                        Task { await model.load() }
                    }
                    .accessibilityIdentifier("search.source.\(source.id)")
                }
            }
            .padding(.horizontal, 2)
            .padding(.top, 2)
            .padding(.bottom, 6)
        }
        .padding(.horizontal, PoseSurfaceMetrics.horizontalPadding)
        .padding(.bottom, 16)
    }

}

/// `.nb-nav-bar.nb-search-nav`: 52pt tall bar with a 44pt boxed back control, a centred 20pt bold
/// title, `margin-bottom: 24px` (`#pose-search .nb-search-nav`). The trailing column is empty but
/// keeps `--nb-touch-min` reserved, exactly like `.nb-nav-bar__right`.
private struct SearchNavHeader: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(AIPoseColor.foreground)
                .lineLimit(1)
                .padding(.horizontal, PoseSurfaceMetrics.touchMinimum + 8)
            HStack(spacing: 8) {
                NeoBackButton(accessibilityLabel: "Back", action: onBack)
                    .accessibilityIdentifier("search.back")
                Spacer(minLength: 0)
                Color.clear.frame(width: PoseSurfaceMetrics.touchMinimum, height: PoseSurfaceMetrics.touchMinimum)
            }
        }
        .frame(height: PoseSurfaceMetrics.navBarHeight)
        .padding(.horizontal, PoseSurfaceMetrics.horizontalPadding)
        .padding(.bottom, PoseSurfaceMetrics.navBarBottomMargin)
    }
}

/// Which owner surface renders a `PoseResultsList` — Search (`search.html`) and Saved
/// (`saved-list.html`) carry different frozen state copy.
enum PoseResultsContext {
    case search
    case saved
}

/// How `PoseResultsList` renders the `.empty` state.
enum PoseResultsEmptyPresentation {
    /// Centered `FeatureStateView` (Saved poses).
    case centered
    /// Render nothing; the owner draws the prototype's inline banner instead (Search).
    case hidden
}

/// Prototype `.nb-search-chip` / `.nb-search-filter` (search.css): rounded-rect control (radius 10,
/// **not** a capsule), white fill, 1.5pt black border and a hard 1.5pt shadow. The shared
/// `NeoFilterChip` uses a capsule + blue active fill, which the prototype does not.
private struct SearchChip: View {
    enum Kind {
        /// `.nb-search-chip`: 14pt semibold, `padding: 8px 12px`, always shadowed.
        case recent
        /// `.nb-search-filter`: 12pt semibold, `padding: 4px 8px`, `box-shadow: none` unless active.
        case filter
    }

    let title: String
    var kind: Kind = .recent
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: kind == .recent ? 14 : 12, weight: .semibold))
                .foregroundStyle(AIPoseColor.foreground)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, kind == .recent ? 12 : 8)
                .padding(.vertical, kind == .recent ? 8 : 4)
                .frame(minHeight: PoseSurfaceMetrics.touchMinimum)
                .background(isActive ? AIPoseColor.accentYellow : AIPoseColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: PoseSurfaceMetrics.chipCornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: PoseSurfaceMetrics.chipCornerRadius)
                        .stroke(AIPoseColor.foreground, lineWidth: PoseSurfaceMetrics.chipBorderWidth)
                )
                .shadow(
                    color: (kind == .recent || isActive) ? AIPoseColor.foreground : .clear,
                    radius: 0, x: 1.5, y: 1.5
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// MARK: - Saved

enum SavedSurfaceStage: Equatable {
    case resolvingSession
    case signInRequired
    case list

    static func resolve(isSessionResolved: Bool, isSignedIn: Bool) -> SavedSurfaceStage {
        guard isSessionResolved else { return .resolvingSession }
        return isSignedIn ? .list : .signInRequired
    }

    /// Tone of the shared state card this stage renders on its own; `nil` hands off to the list,
    /// which derives its own tone from `Loadable.stateTone`.
    var tone: FeatureStateTone? {
        switch self {
        case .resolvingSession: return .loading
        case .signInRequired: return .empty
        case .list: return nil
        }
    }
}

/// Account-scoped Saved collection. The list only exists in a signed-in context: while no session
/// is stored (or right after a 401 cleared it) the screen shows the sign-in-required panel instead
/// of calling `/api/me/saved`, so a guest can never be shown cached rows as current (FEAT-013/FEAT-014).
struct SavedPosesScreen: View {
    @ObservedObject var model: PosesViewModel
    var onTryPose: (NativePose) -> Void = { _ in }
    @StateObject private var session = SessionPresenceModel()
    @State private var pendingSignIn: SignInIntent?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            // The stage decision is pure (`SavedSurfaceStage.resolve`) so the signed-in states that
            // `GET /api/me/saved` returns 401 for in the parity rig remain verifiable in unit tests.
            switch SavedSurfaceStage.resolve(isSessionResolved: session.isResolved, isSignedIn: session.isSignedIn) {
            case .resolvingSession:
                savedResolvingSession
            case .signInRequired:
                savedSignInRequired
            case .list:
                PoseResultsList(
                    model: model,
                    onTryPose: onTryPose,
                    context: .saved,
                    // `saved-list.html` `Browse Community` returns to the published Poses collection;
                    // this screen is always pushed, so dismissal is the only honest route there.
                    onBrowseCommunity: { dismiss() }
                )
                .onAppear {
                    model.filter = .saved
                    Task { await model.load() }
                }
            }
        }
        // R3: the session-resolve, sign-in-gate and non-loaded list states are single short cards;
        // without a top-aligned expander they centre in the pushed view instead of anchoring under
        // the navigation bar. A loaded `PoseResultsList` (ScrollView) still fills the frame.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Saved poses")
        .task { session.start() }
        // A successful sign-in flips `SessionPresenceModel` through the boundary's `.signedIn`
        // event, which mounts the list and loads it — no explicit resume needed here.
        .signInPrompt($pendingSignIn)
    }

    /// `saved-list.html` loading state through the shared component (report §3.8). The card is
    /// top-anchored like every state surface; the frozen component owns the geometry.
    private var savedResolvingSession: some View {
        FeatureStateView(
            tone: .loading,
            title: PoseResultsStateCopy.savedLoadingTitle,
            message: PoseResultsStateCopy.savedLoadingMessage
        )
        .padding(.horizontal, PoseSurfaceMetrics.horizontalPadding)
    }

    /// FEAT-013 auth gate. Copy stays native (`SignInRequiredPanel` in the KMP `SavedScreen`); the
    /// presentation is the shared state component instead of the old one-off Image/Text stack.
    private var savedSignInRequired: some View {
        VStack(spacing: AIPoseSpacing.md) {
            FeatureStateView(
                tone: .empty,
                title: "Sign in to view your saved poses",
                message: "Your saved poses are tied to your account. Continue with Google to keep them synced."
            )
            .padding(.horizontal, PoseSurfaceMetrics.horizontalPadding)
            // The spinner state lives inside the presented sign-in prompt (`SignInPromptModel`),
            // so the gate button itself never needs the in-flight flag.
            ContinueWithGoogleButton(isAuthenticating: false) { pendingSignIn = .openSaved }
                .padding(.horizontal, PoseSurfaceMetrics.horizontalPadding)
                .accessibilityLabel("Continue with Google")
                .accessibilityIdentifier("saved.signIn")
        }
        .padding(.vertical, AIPoseSpacing.xl)
        .accessibilityElement(children: .contain)
    }
}

struct PoseResultsList: View {
    @ObservedObject var model: PosesViewModel
    var onTryPose: (NativePose) -> Void = { _ in }
    /// Owner surface: Search and Saved have different frozen loading/error/empty copy.
    var context: PoseResultsContext = .search
    /// Bottom clearance for the dock overlay; the shared Search workspace reserves less than the tab root.
    var bottomInset: CGFloat = PoseGridMetrics.dockClearance
    /// The Search workspace renders its own inline banner instead (prototype `#search-state-message`).
    var emptyPresentation: PoseResultsEmptyPresentation = .centered
    /// Saved list only: recovery for the empty state (prototype `Browse Community` → back to Poses).
    var onBrowseCommunity: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let tone = stateTone {
            stateCard(tone: tone)
        } else if case .loaded(let poses) = model.state {
            ScrollView {
                PoseGrid(poses: poses, model: model, onTryPose: onTryPose)
                    .padding(.horizontal, PoseGridMetrics.horizontalPadding)
                    .padding(.top, 2)
                    .padding(.bottom, bottomInset)
            }
        }
    }

    /// Shared-card tone for the current result, or `nil` when this surface draws the grid — or
    /// nothing at all, which is how Search renders its own inline `#search-state-message` banner.
    /// Derived from the pure `Loadable.stateTone` mapper so the Saved list states the parity rig
    /// cannot drive (`GET /api/me/saved` → 401) stay mechanically verifiable.
    var stateTone: FeatureStateTone? {
        switch model.state {
        case .loaded:
            return nil
        case .empty:
            return emptyPresentation == .centered ? model.state.stateTone : nil
        case .idle, .loading, .failed:
            return model.state.stateTone
        }
    }

    @ViewBuilder private func stateCard(tone: FeatureStateTone) -> some View {
        switch tone {
        case .loading:
            FeatureStateView(
                tone: .loading,
                title: stateCopy.loadingTitle,
                message: stateCopy.loadingMessage
            )
            .padding(.horizontal, PoseSurfaceMetrics.horizontalPadding)
        case .error:
            FeatureStateView(
                tone: .error,
                title: stateCopy.errorTitle,
                message: stateCopy.errorMessage,
                actionTitle: PoseResultsStateCopy.retryActionTitle
            ) {
                Task { await model.load() }
            }
            .padding(.horizontal, PoseSurfaceMetrics.horizontalPadding)
            .accessibilityIdentifier(context == .saved ? "saved.retry" : "search.retry")
        case .empty:
            emptyState
        case .offline, .success, .warning:
            // No `Loadable` producer maps to these tones on this surface; the camera pose picker owns
            // `.offline` separately (see `PosePickerViewModel.stateTone`).
            EmptyView()
        }
    }

    /// Per-surface loading/error copy (report §3.5 vs §3.8).
    private var stateCopy: (loadingTitle: String, loadingMessage: String, errorTitle: String, errorMessage: String) {
        switch context {
        case .search:
            return (
                PoseResultsStateCopy.searchLoadingTitle,
                PoseResultsStateCopy.searchLoadingMessage,
                PoseResultsStateCopy.searchErrorTitle,
                PoseResultsStateCopy.searchErrorMessage
            )
        case .saved:
            return (
                PoseResultsStateCopy.savedLoadingTitle,
                PoseResultsStateCopy.savedLoadingMessage,
                PoseResultsStateCopy.savedErrorTitle,
                PoseResultsStateCopy.savedErrorMessage
            )
        }
    }

    /// Context-aware empty state (SCR-003-02-ST-003). Search keeps the `SearchResultsCopy` copy;
    /// with a query present the card has no action at all (`app.js:847`), and the only action is
    /// `Show all poses` on the no-query, non-All branch. The Saved list owns the `saved-list.html`
    /// "No saved poses yet" state with `Browse Community` whenever no query is in play.
    @ViewBuilder private var emptyState: some View {
        if context == .saved, model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            FeatureStateView(
                tone: .empty,
                title: PoseResultsStateCopy.savedEmptyTitle,
                message: PoseResultsStateCopy.savedEmptyMessage,
                actionTitle: PoseResultsStateCopy.browseCommunityActionTitle
            ) {
                onBrowseCommunity()
            }
            .padding(.horizontal, PoseSurfaceMetrics.horizontalPadding)
            .accessibilityIdentifier("saved.browseCommunity")
        } else if let recoveryTitle = SearchResultsCopy.emptyRecoveryTitle(query: model.query, filter: model.filter) {
            FeatureStateView(
                tone: .empty,
                title: SearchResultsCopy.emptyTitle(query: model.query, filter: model.filter),
                message: SearchResultsCopy.emptyMessage(query: model.query, filter: model.filter),
                actionTitle: recoveryTitle
            ) {
                Task { await model.startSearch(for: "") }
            }
        } else {
            FeatureStateView(
                tone: .empty,
                title: SearchResultsCopy.emptyTitle(query: model.query, filter: model.filter),
                message: SearchResultsCopy.emptyMessage(query: model.query, filter: model.filter)
            )
        }
    }
}

private extension Loadable where Value == [NativePose] {
    /// Equatable presentation summary used only to drive the low-intensity results-panel cross-fade.
    var panelStateKey: String {
        switch self {
        case .idle: return "idle"
        case .loading: return "loading"
        case .empty: return "empty"
        case .failed: return "failed"
        case .loaded(let poses): return "loaded-\(poses.count)-\(poses.map(\.id).joined(separator: ","))"
        }
    }
}

private extension NativePose {
    func withSaved(_ saved: Bool) -> NativePose {
        var copy = self
        copy.isSaved = saved
        return copy
    }
}
