import Combine
import Foundation
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

/// User-visible copy for the Saved and Search state panels, per owner surface:
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

    /// Saved sign-in gate. Neutral on purpose: the Saved tab is reachable without ever having
    /// signed in, so its copy must not say "again" (BUG-261029-03). Named so the absence of that
    /// wording is assertable.
    static let savedSignInTitle = "Sign in to view your saved poses"
    static let savedSignInMessage = "Your saved poses are tied to your account. Sign in to keep them synced."
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

/// What a failed save/unsave tells the user (`FEAT-014` saved mutations).
///
/// The three cases below are the ones a tap can actually produce and that a user can act on: a lost
/// session, a pose that no longer exists, and no connection. Anything else keeps the generic copy,
/// so the screen never invents a cause.
enum SavedMutationCopy {
    static let signInRequired = "Please sign in again."
    static let poseUnavailable = "This pose is no longer available."
    static let offline = "You're offline. Try again when connected."
    static let fallback = "Unable to update this pose."

    /// Codes the saved routes answer for a pose the viewer can no longer save (`savedRoutes.ts`
    /// answers `NOT_FOUND`, `APIClient` falls back to the numeric status when there is no envelope).
    private static let notFoundCodes: Set<String> = ["404", "NOT_FOUND", "POSE_NOT_FOUND"]

    static func text(for error: Error) -> String {
        if let apiError = error as? PoseAPIError {
            if apiError.isUnauthorized { return signInRequired }
            if notFoundCodes.contains(apiError.code) { return poseUnavailable }
        }
        if let clientError = error as? APIClientError, case .httpStatus(let status) = clientError {
            if status == 401 { return signInRequired }
            if status == 404 { return poseUnavailable }
        }
        if let urlError = error as? URLError, urlError.isOffline { return offline }
        return ErrorCopy.text(for: error) ?? fallback
    }

    /// The pose is gone server-side, so offering the same tap again cannot help.
    static func isGone(_ error: Error) -> Bool {
        if let apiError = error as? PoseAPIError { return notFoundCodes.contains(apiError.code) }
        if let clientError = error as? APIClientError, case .httpStatus(let status) = clientError {
            return status == 404
        }
        return false
    }
}

private extension URLError {
    /// No connection / connection dropped mid-request. A timeout is deliberately *not* here: the
    /// request may still have been applied server-side, so it keeps the generic copy.
    var isOffline: Bool {
        switch code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
             .dataNotAllowed, .internationalRoamingOff:
            return true
        default:
            return false
        }
    }
}

@MainActor final class PosesViewModel: ObservableObject, SessionScoped {
    @Published var state: Loadable<[NativePose]> = .idle
    @Published var query = ""
    @Published var filter: PoseLibraryFilter = .community
    /// Where the next window of the current list comes from. Kept beside `state` instead of inside it
    /// because a failed page must not cost the rows already on screen, which `Loadable.failed`
    /// cannot express.
    struct Paging: Equatable, Sendable {
        /// Windows one `loadMore` may fetch on its own before it hands the decision back to the user.
        static let autoFetchBudget = 3
        /// Rows per request. The server's own page size for both feed endpoints.
        static let pageSize = 20

        /// Rows of the server's list already consumed. **Not** `rows.count`: a confirmed unsave
        /// removes a row from the Saved collection, which shifts every later row one position up, so
        /// the cursor has to follow the collection and not the visible list.
        var nextOffset = 0
        var hasMore = false
        var isLoading = false
        var error: String?
        /// Spent by automatic fetches (windows that add nothing to a filtered list). A run that runs
        /// out stops and shows the "Load more results" button, so the list never dead-ends.
        var remainingAutoFetches = Paging.autoFetchBudget
        /// Bumped when the cursor itself moves (a row the user removed). A window that was requested
        /// for the old offset is dropped instead of advancing the cursor past a row it skipped.
        var cursorGeneration = 0
    }

    @Published private(set) var paging = Paging()
    /// Bumped by every action that owns the list from scratch (load, refresh, query change, filter
    /// change, session change). A page whose generation is behind is dropped instead of being
    /// appended to a list it was never fetched for.
    private var listGeneration = 0
    private let service: any PoseServing
    let bookmarkService: (any PoseBookmarkServing)?
    private let filterState: PoseFilterState?
    /// The session boundary this model follows. One instance survives Settings → Account → sign out →
    /// sign in as somebody else (and delete-account → sign-in), so the model itself has to drop the
    /// previous Account's state; the catalog's own clear (`SessionScopeCoordinator`) cannot reach it.
    ///
    /// `nil` keeps directly constructed models (previews, unit tests that only exercise list copy)
    /// session-agnostic — the composition root injects the real boundary, exactly like the adapter's
    /// `hasSession` probe.
    private let boundary: SessionBoundary?
    /// The one fan-out for this boundary. Every model behind it shares a single `observeSessions`
    /// subscription, and each request carries a ticket from it so a stale answer is dropped instead of
    /// being painted into the next Account's screen.
    private let scope: SessionScope?
    private var searchTask: Task<Void, Never>?
    private var debounceNanoseconds: UInt64 = 350_000_000

    init(
        service: any PoseServing,
        bookmarkService: (any PoseBookmarkServing)? = nil,
        filterState: PoseFilterState? = nil,
        boundary: SessionBoundary? = nil,
        debounceNanoseconds: UInt64 = 350_000_000
    ) {
        self.service = service
        self.bookmarkService = bookmarkService
        self.filterState = filterState
        self.boundary = boundary
        self.scope = boundary.map { SessionScope.of($0) }
        self.debounceNanoseconds = debounceNanoseconds
        // Held weakly by the scope, so a throwaway instance (this model is rebuilt inside `body`)
        // neither leaks nor starts its own observer.
        scope?.adopt(self)
    }

    convenience init(
        bundle: PoseServiceBundle,
        boundary: SessionBoundary? = nil,
        debounceNanoseconds: UInt64 = 350_000_000
    ) {
        self.init(
            service: bundle.service,
            bookmarkService: bundle.bookmarkService,
            filterState: bundle.filterState,
            boundary: boundary,
            debounceNanoseconds: debounceNanoseconds
        )
    }

    #if DEBUG
    /// Test-only: puts the paging cursor in a specific state (an empty page with rows still behind
    /// it, or a failed page) so the footer's rendered states can be driven without a network.
    func setPagingForTesting(error: String? = nil, hasMore: Bool = false, remainingAutoFetches: Int = 0) {
        var next = paging
        next.error = error
        next.hasMore = hasMore
        next.remainingAutoFetches = remainingAutoFetches
        paging = next
    }
    #endif

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
        // `.loading` is painted **before** the ticket is awaited. A session change that lands inside
        // `beginSessionRequest` then sees a loading model and restarts the read; painted afterwards,
        // it would see an idle model, do nothing, and the answer that arrives for the old ticket
        // would be dropped — leaving this screen spinning forever.
        state = .loading
        listGeneration &+= 1
        let generation = listGeneration
        paging = Paging()
        let ticket = await beginSessionRequest()
        guard generation == listGeneration else { return }
        filterState?.filter = filter
        do {
            let page = try await service.posesPage(query: normalizedQuery, offset: 0, limit: Paging.pageSize)
            // A session change while this request was in flight makes the answer belong to the
            // previous Account (its Saved flags included), so it must not reach the screen.
            guard await isCurrentSession(ticket), generation == listGeneration else { return }
            // A window that advanced past nothing cannot be followed: stop instead of asking for the
            // same offset again (a stale total, or a server repeating a window).
            paging.hasMore = page.hasMore && page.consumed > 0
            paging.nextOffset = page.consumed
            state = page.poses.isEmpty ? .empty : .loaded(page.poses)
            await fillFilteredList()
        } catch {
            guard await isCurrentSession(ticket), generation == listGeneration else { return }
            state = .failed(ErrorCopy.text(for: error) ?? "Unable to load poses.")
        }
    }

    /// Appends the next page. Called by the grid when its last rows appear and by the footer's
    /// spinner: a second call while one page is in flight is ignored, so a burst of triggers sends
    /// exactly one request. Safe from both `.loaded` and `.empty`.
    func loadMore() async {
        guard !paging.isLoading, paging.hasMore, paging.remainingAutoFetches > 0 else { return }
        await paginate()
    }

    /// The footer's "Load more results" button and its retry: the user asked for the next page
    /// explicitly, so the auto-fetch budget is refilled rather than leaving a dead end.
    func loadMoreResults() async {
        guard !paging.isLoading, paging.hasMore else { return }
        paging.remainingAutoFetches = Paging.autoFetchBudget
        await paginate()
    }

    /// A filtered page can legitimately hold no matches, so an empty first page is not final while
    /// the server still reports more rows.
    private func fillFilteredList() async {
        guard paging.hasMore, case .empty = state else { return }
        await paginate()
    }

    private func paginate() async {
        let generation = listGeneration
        let cursor = paging.cursorGeneration
        paging.isLoading = true
        paging.error = nil
        // A refresh or a session change resets `paging` itself, so only the generation that started
        // this request may settle it.
        defer {
            if generation == listGeneration { paging.isLoading = false }
        }
        let ticket = await beginSessionRequest()
        guard generation == listGeneration else { return }

        while paging.hasMore {
            guard paging.remainingAutoFetches > 0 else { return }
            paging.remainingAutoFetches -= 1
            let offset = paging.nextOffset
            do {
                let page = try await service.posesPage(
                    query: normalizedQuery,
                    offset: offset,
                    limit: Paging.pageSize
                )
                // A window belongs to the list that asked for it: refreshed, re-filtered, handed to
                // another Account, or computed for a cursor that a removal has since moved. Applying
                // it would resurrect dropped rows or skip one.
                guard await isCurrentSession(ticket),
                      generation == listGeneration,
                      cursor == paging.cursorGeneration else { return }
                paging.nextOffset = offset + page.consumed
                paging.hasMore = page.hasMore && page.consumed > 0
                // A window that adds rows is progress: restore the budget so ordinary scrolling keeps
                // loading. Only a run of windows that add nothing (an empty filtered list) can spend
                // it all, and that is exactly when the user should decide to keep going.
                guard append(page.poses) == 0 else {
                    paging.remainingAutoFetches = Paging.autoFetchBudget
                    return
                }
            } catch {
                guard await isCurrentSession(ticket),
                      generation == listGeneration,
                      cursor == paging.cursorGeneration else { return }
                // Keep the rows already loaded and the cursor: the footer offers a retry of this
                // same window.
                paging.error = ErrorCopy.text(for: error) ?? "Unable to load more poses."
                return
            }
        }
    }

    /// Appends `poses`, dropping ids the list already shows. Returns how many rows were added.
    private func append(_ poses: [NativePose]) -> Int {
        var merged: [NativePose]
        switch state {
        case .loaded(let current):
            merged = current
        case .empty:
            merged = []
        case .idle, .loading, .failed:
            return 0
        }
        var seen = Set(merged.map(\.id))
        var added = 0
        for pose in poses where seen.insert(pose.id).inserted {
            merged.append(pose)
            added += 1
        }
        guard added > 0 else { return 0 }
        state = .loaded(merged)
        return added
    }

    private var normalizedQuery: String? {
        query.isEmpty ? nil : query
    }

    /// Captures the ticket for a request that is about to start. `nil` (no boundary, or no scope)
    /// keeps directly constructed models session-agnostic.
    private func beginSessionRequest() async -> SessionTicket? {
        guard let scope else { return nil }
        return await scope.beginRequest()
    }

    /// A completion is accepted only while the session that asked for it is still the current one.
    private func isCurrentSession(_ ticket: SessionTicket?) async -> Bool {
        guard let scope, let ticket else { return true }
        return await scope.isValid(ticket)
    }

    /// Cheap synchronous variant for the task a reset kicks: its ticket came from the fan-out itself,
    /// so it is superseded only by a *later* reset.
    private func isScopeCurrent(_ ticket: SessionTicket?) -> Bool {
        guard let scope, let ticket else { return true }
        return scope.isCurrent(ticket)
    }

    /// Drops what the previous Account left behind: its confirmed save per pose, its in-flight
    /// bookmarks, its "pose is gone" verdicts, and — for the routes that carry Saved flags — the
    /// loaded list itself. Synchronous: the scope bumps its generation and resets every model in one
    /// turn, so no screen can draw A's answer after another screen already switched to B.
    ///
    /// Without this, A saving pose P and then signing out / deleting the account while B signs in
    /// would leave `savedOverrides[P] = true` standing over B's freshly loaded `false`, and B's first
    /// tap would send an unsave.
    func resetForSessionChange(_ event: SessionEvent) {
        // Only an account-scoped list loses its paging. Saved — and All, which merges the next
        // Account's saved collection — restarts from the first window; the community feed is public,
        // its rows survive the change, so its cursor survives too (a window still in flight is
        // dropped by its session ticket).
        if filter == .saved || filter == .all {
            listGeneration &+= 1
            paging = Paging()
        }
        savedOverrides.removeAll()
        bookmarkRequests.removeAll()
        bookmarkRequestsInFlight = []
        unavailablePoseIDs.removeAll()
        bookmarkError = nil
        // A request that was in flight under the previous session is discarded by its own ticket, so
        // nothing would ever settle `.loading` — remember it and restart below.
        let wasLoading: Bool
        if case .loading = state { wasLoading = true } else { wasLoading = false }
        let ticket = scope?.ticket

        // A Saved (or All) list is account-scoped in its entirety, so it is dropped and re-read.
        if filter == .saved || filter == .all {
            state = .idle
            // The next Account's list is fetched through the normal path (a sign-out has nothing to
            // fetch: the Saved surface gates on the session itself).
            Task { @MainActor [weak self] in
                guard let self, self.isScopeCurrent(ticket) else { return }
                guard await self.boundary?.hasStoredSession() == true else { return }
                guard self.isScopeCurrent(ticket) else { return }
                await self.load()
            }
            return
        }

        if wasLoading {
            // The in-flight answer belongs to the previous session, so this state would stay
            // `.loading` forever. The community feed holds no Account state, so it is re-read even
            // when the change left the app signed out.
            state = .idle
            Task { @MainActor [weak self] in
                guard let self, self.isScopeCurrent(ticket) else { return }
                await self.load()
            }
            return
        }

        // The community feed itself is not account-scoped, but a confirmed save rewrote the loaded
        // row (`updateSavedLocally`), so those rows are demoted rather than left standing as the
        // next Account's answer.
        if case .loaded(let poses) = state {
            state = .loaded(poses.map { $0.isSaved ? $0.withSaved(false) : $0 })
        }
    }

    /// What a bookmark attempt actually achieved. A pose may only be shown as saved for `.saved`.
    enum BookmarkOutcome: Equatable, Sendable {
        case saved(Bool)
        /// No bookmark service is wired (signed out or account features unavailable): nothing was sent.
        case unavailable
        /// Another tap for this pose is still in flight; this one was ignored on purpose.
        case inFlight
        /// The session changed while the request was outstanding, so the answer belongs to the
        /// previous Account. Nothing was recorded; the screen simply shows the current state.
        case discarded
        case failed(String)
    }

    /// Copy for the last failed bookmark attempt; the screen surfaces it with the shared alert pattern.
    @Published var bookmarkError: String?
    /// Poses the server answered `404` for. The pose is gone, so the control stops offering a retry
    /// that cannot succeed instead of failing the same way on every tap.
    @Published private(set) var unavailablePoseIDs: Set<String> = []
    /// Poses with a request in flight, so a rapid second tap cannot desync the local state — and so a
    /// screen that is opened mid-request can show it as busy instead of offering a second save.
    ///
    /// Derived from `bookmarkRequests`, which claims per request: A's late completion can only
    /// release A's own claim, never B's claim for the same pose.
    @Published private(set) var bookmarkRequestsInFlight: Set<String> = []
    private var bookmarkRequests = InFlight<String>()
    /// Server-confirmed saved state per pose id. The single source of truth for the saved UI: it also
    /// covers poses that are not in the loaded list (e.g. a detail screen opened from Jobs).
    @Published private(set) var savedOverrides: [String: Bool] = [:]

    func isBookmarkInFlight(_ poseID: String) -> Bool {
        bookmarkRequests.contains(poseID)
    }

    /// What the UI must show for this pose: a server-confirmed answer first, then the loaded list, then
    /// the caller's own snapshot. Never a local copy made by a screen, which goes stale on navigation.
    func savedState(for pose: NativePose) -> Bool {
        if let confirmed = savedOverrides[pose.id] { return confirmed }
        if case .loaded(let poses) = state, let match = poses.first(where: { $0.id == pose.id }) {
            return match.isSaved
        }
        return pose.isSaved
    }

    /// Saves/unsaves through the server and only then updates the local list. Without a bookmark
    /// service nothing can confirm the save, so the pose is never reported or shown as saved.
    @discardableResult
    func toggleSaved(for pose: NativePose) async -> BookmarkOutcome {
        guard let service = bookmarkService else { return .unavailable }
        // Settle the session before claiming: a reset clears the in-flight claims, so a claim taken
        // before the fan-out belongs to the previous session and would be wiped under this request.
        let ticket = await beginSessionRequest()
        guard let request = beginBookmarkRequest(pose.id) else { return .inFlight }
        defer { endBookmarkRequest(pose.id, request) }

        // Read the shared state, not the caller's snapshot: a screen that was opened before an earlier
        // save completed still has `isSaved == false` and would otherwise send a second save.
        let shouldSave = !savedState(for: pose)
        do {
            if shouldSave { try await service.savePose(poseId: pose.id) }
            else { try await service.unsavePose(poseId: pose.id) }
            guard await isCurrentSession(ticket) else { return .discarded }
            bookmarkError = nil
            updateSavedLocally(poseID: pose.id, saved: shouldSave)
            return .saved(shouldSave)
        } catch {
            guard await isCurrentSession(ticket) else { return .discarded }
            // Nothing was flipped up front, so "rollback" is simply the state we still hold.
            let message = SavedMutationCopy.text(for: error)
            if SavedMutationCopy.isGone(error) { unavailablePoseIDs.insert(pose.id) }
            bookmarkError = message
            return .failed(message)
        }
    }

    /// Claims the pose for one request. The token is what lets a finished request release only its
    /// own claim: resetting the set on a session change must not turn A's late `defer` into a release
    /// of B's claim for the same pose.
    private func beginBookmarkRequest(_ poseID: String) -> UInt64? {
        let token = bookmarkRequests.begin(poseID)
        bookmarkRequestsInFlight = bookmarkRequests.keys
        return token
    }

    private func endBookmarkRequest(_ poseID: String, _ token: UInt64) {
        bookmarkRequests.end(poseID, token)
        bookmarkRequestsInFlight = bookmarkRequests.keys
    }

    /// A pose the server reported as gone is no longer offered a save control.
    func canSave(_ pose: NativePose) -> Bool {
        !unavailablePoseIDs.contains(pose.id)
    }

    /// Records a server-confirmed saved state. The override is what every screen reads, so a detail
    /// screen opened later (or reopened mid-request) cannot show a stale answer.
    func updateSavedLocally(poseID: String, saved: Bool) {
        savedOverrides[poseID] = saved
        if !saved, filter == .saved {
            // An unsave removes the row from the Saved collection itself, so every row behind it
            // moves one position up: the cursor has to move with it or the window after this one
            // starts past a row nobody has seen. Shifting when the row was *not* on screen would at
            // worst re-read a row (deduped by id), never skip one.
            shiftPagingCursorForRemoval()
        }
        guard case .loaded(var poses) = state,
              let index = poses.firstIndex(where: { $0.id == poseID }) else { return }
        poses[index].isSaved = saved
        let filtered = filter == .saved ? poses.filter(\.isSaved) : poses
        state = filtered.isEmpty ? .empty : .loaded(filtered)
    }

    /// Keeps the cursor on the row that is still next. A window already in flight was computed for
    /// the old cursor, so it is invalidated rather than applied.
    private func shiftPagingCursorForRemoval() {
        guard paging.nextOffset > 0 else { return }
        paging.nextOffset -= 1
        paging.cursorGeneration &+= 1
        paging.error = nil
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
    static let cardBorderWidth: CGFloat = NeoChromeTokens.borderThick
    static let cardCornerRadius: CGFloat = NeoChromeTokens.radiusLarge
    /// `.nb-grid-pose-item { gap: 4px }` + `.nb-grid-pose-label` (14px regular, outside the card).
    static let cardLabelSpacing: CGFloat = 4
    /// `.nb-search-chip / .nb-search-filter { border: 1.5px solid; border-radius: 10px }`
    static let chipBorderWidth: CGFloat = NeoChromeTokens.borderThin
    static let chipCornerRadius: CGFloat = NeoChromeTokens.radiusMedium
    /// `.nb-search-field { min-height: 56px; border: 2px; border-radius: 14px; box-shadow: 3px 3px 0 }`
    static let searchFieldMinHeight: CGFloat = 56
    static let searchFieldCornerRadius: CGFloat = NeoChromeTokens.radiusLarge
    /// `.nb-search-form { margin: 0 0 32px }`
    static let searchFormBottomMargin: CGFloat = 32
    /// `.nb-nav-bar { height: 52px }` + `#pose-search .nb-search-nav { margin-bottom: 24px }`
    static let navBarHeight: CGFloat = 52
    static let navBarBottomMargin: CGFloat = 24
    /// `.nb-touch-min`
    static let touchMinimum: CGFloat = NeoChromeTokens.touchMinimum
}

/// In-memory cache for loaded pose artwork aspect ratios (width / height).
/// Respects real image proportions to drive client-side 2-column masonry layout without letterboxing.
@MainActor
final class PoseAspectRatioCache: ObservableObject {
    static let shared = PoseAspectRatioCache()
    private static let capacity = 512

    @Published private(set) var ratios: [String: CGFloat] = [:]
    private var insertionOrder: [String] = []

    private init() {}

    func ratio(for poseId: String) -> CGFloat {
        ratios[poseId] ?? PoseGridMetrics.defaultAspectRatio
    }

    func updateRatio(width: CGFloat, height: CGFloat, for poseId: String) {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return }
        let ratio = width / height
        guard ratio.isFinite, ratio > 0 else { return }
        if let existing = ratios[poseId], abs(existing - ratio) < 0.001 {
            return
        }
        if ratios[poseId] == nil {
            insertionOrder.append(poseId)
        }
        ratios[poseId] = ratio
        while insertionOrder.count > Self.capacity {
            ratios.removeValue(forKey: insertionOrder.removeFirst())
        }
    }

    #if DEBUG
    func setRatioForTesting(_ ratio: CGFloat, for poseId: String) {
        ratios[poseId] = ratio
    }
    func resetForTesting() {
        ratios.removeAll()
        insertionOrder.removeAll()
    }
    #endif
}

/// Grid metrics for the 2-column staggered masonry pose grid (`.nb-grid--masonry`, `components/grid.css`).
enum PoseGridMetrics {
    static let horizontalPadding = PoseSurfaceMetrics.horizontalPadding
    /// `.nb-grid--masonry { column-gap: 8px }`
    static let columnSpacing: CGFloat = 8
    /// `.nb-grid--masonry .nb-grid-pose-item { margin-bottom: calc(16px * 0.8) }`
    static let rowSpacing: CGFloat = 12.8
    static let defaultAspectRatio: CGFloat = 1.0
    /// Artwork decode stays bounded to the prototype's tallest card (1.25x column height).
    /// Layout itself keeps the true image ratio, including taller portraits.
    static let minimumDownsampleAspectRatio: CGFloat = 0.8
    static let labelHeightForBalancing: CGFloat = 34

    @MainActor static var columnWidth: CGFloat {
        let screenWidth = UIScreen.main.bounds.width > 0 ? UIScreen.main.bounds.width : 390
        let contentWidth = screenWidth - 2 * horizontalPadding
        return max(1, (contentWidth - columnSpacing) / 2)
    }

    /// Assign each item in source order to the column with the lower accumulated height.
    /// Ratios are image width / height; invalid and not-yet-loaded values stay square.
    static func columnAssignments(
        for aspectRatios: [CGFloat],
        columnWidth: CGFloat,
        itemSpacing: CGFloat = rowSpacing,
        labelHeight: CGFloat = labelHeightForBalancing,
        labelSpacing: CGFloat = PoseSurfaceMetrics.cardLabelSpacing
    ) -> [Int] {
        guard !aspectRatios.isEmpty else { return [] }
        let width = max(1, columnWidth.isFinite ? columnWidth : 1)
        var heights = [CGFloat](repeating: 0, count: 2)
        var counts = [Int](repeating: 0, count: 2)

        return aspectRatios.map { ratio in
            let column = heights[0] <= heights[1] ? 0 : 1
            let safeRatio = ratio.isFinite && ratio > 0 ? ratio : defaultAspectRatio
            let gap = counts[column] == 0 ? 0 : itemSpacing
            heights[column] += width / safeRatio + labelHeight + labelSpacing + gap
            counts[column] += 1
            return column
        }
    }

    /// The maximum bounding box for card artwork downsampling:
    /// one column wide and at most 1.25 times as tall as it is wide.
    @MainActor static var cardArtworkPoints: CGSize {
        return CGSize(
            width: columnWidth,
            height: columnWidth / minimumDownsampleAspectRatio
        )
    }

    /// Dock (48) + 16 bottom + safe area (34 on iPhone 13) keeps the last row clear of the dock.
    static let dockClearance: CGFloat = 48 + 16 + 34
    /// `.nb-search-discovery` / `.nb-search-results-scroll { padding-bottom: calc(40px + safe-area) }`
    static let searchDockClearance: CGFloat = 40 + 34
}

enum PosesRoute: Hashable {
    case addPose
    case jobs(JobsTab)

    var isJobs: Bool {
        if case .jobs = self { return true }
        return false
    }

    var jobsTab: JobsTab {
        if case .jobs(let tab) = self { return tab }
        return .processing
    }
}

enum JobsEntryPolicy {
    static func canOpen(extractPoseEnabled: Bool) -> Bool {
        AppConfig.canExtractPose(isEnabled: extractPoseEnabled)
    }
}

// MARK: - Poses

struct PosesScreen: View {
    @StateObject var model: PosesViewModel
    @ObservedObject var jobsService: JobsService = ServiceLocator.jobsService
    @StateObject private var session = SessionPresenceModel()
    var onTryPose: (CameraPoseRequest) -> Void = { _ in }
    /// Lets `AppFeatureRoot` hide the dock's active pill while the Search overlay is up: Search is
    /// not a tab, and `reference/search-blank.png` shows both dock items plain grey.
    var onSearchVisibilityChange: (Bool) -> Void = { _ in }
    /// BUG-261029-05: the camera is a tab, so closing it rebuilt this screen from its root and the
    /// pose detail the user came from was gone. The app root hands the detail back here, and the
    /// rebuilt stack pushes it once.
    var resumePose: CameraPoseRequest?
    /// Fired when the handed-back detail was taken. One-shot: a later visit to this tab must not
    /// silently re-open the pose.
    var onResumeHandled: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Multi-select category chips over the loaded catalogue (design B: one accent, one neutral).
    @State private var categoryFilter = APCategoryFilter()
    /// The labelled "More" menu: Add pose, Jobs, Saved live here now, so the header keeps three
    /// 44 pt actions instead of five (`01-nav-map` "Poses header" / "More menu").
    @State private var showsMoreMenu = false
    /// The Search workspace is presented **in place** instead of being pushed on the stack.
    ///
    /// `AppFeatureRoot` overlays `NeoDockTabBar` on top of its `<tab>Root`, so a `NavigationLink`
    /// push replaces the root view and the dock disappears with it (verified on device; the
    /// `lucton-search-pushed-*` shots show the dock missing). The prototype `screens/search.html`
    /// keeps the dock visible, and nothing inside `RootNavigation` can redraw it — only
    /// `AppFeatureRoot` owns the dock — so the Search screen is overlaid here, where the root ZStack
    /// still paints the dock above it.
    @State private var showsSearch = false
    @State private var pendingSignIn: SignInIntent?
    @State private var route: PosesRoute?
    /// The pose detail being restored after a camera visit; `nil` whenever nothing has to be re-pushed.
    @State private var resumedPose: CameraPoseRequest?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                posesHeader
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            if showsMoreMenu && !showsSearch {
                // The page dims behind the card; tapping anywhere outside it closes the menu.
                Color.black.opacity(0.08)
                    .ignoresSafeArea()
                    .onTapGesture { setShowsMoreMenu(false) }
                    .zIndex(1)
                moreMenuOverlay
                    .zIndex(2)
            }
            if showsSearch {
                // Short states (e.g. the no-match banner) must not let the ZStack centre the overlay.
                SearchScreen(model: model, onClose: { setShowsSearch(false) })
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(AP.Color.background)
                    .transition(.move(edge: .trailing))
                    .zIndex(2)
            }
        }
        // R8: the page title now lives in the single in-content row (`.nb-nav-bar--poses`), so the
        // centred system nav-bar title is gone; keeping both would render the title twice.
        .neoHiddenNavigationBar()
        .background(AP.Color.background)
        .task {
            session.start()
            if case .idle = model.state { await model.load() }
            await jobsService.refresh()
        }
        // Seed the restore target once this rebuilt root is on screen: the push itself is the hidden
        // `NavigationLink` below, the same mechanism the Add pose / Jobs routes already use here.
        .onAppear {
            guard resumedPose == nil, let resumePose else { return }
            resumedPose = resumePose
            onResumeHandled()
        }
        .onChange(of: model.filter) { _ in Task { await model.load() } }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                Task { await jobsService.refresh() }
            }
        }
        .signInPrompt($pendingSignIn) { intent in
            Task {
                await jobsService.refresh()
                if intent == .addPose && AppConfig.canExtractPose(isEnabled: AppConfig.shared.isExtractPoseEnabled) {
                    route = .addPose
                } else if intent == .openJobs && JobsEntryPolicy.canOpen(extractPoseEnabled: AppConfig.shared.isExtractPoseEnabled) {
                    route = .jobs(.processing)
                }
            }
        }
        .background(
            Group {
                NavigationLink(
                    destination: AddPoseScreen(
                        posesModel: model,
                        onTryPose: onTryPose,
                        onOpenJobs: { tab in
                            guard JobsEntryPolicy.canOpen(extractPoseEnabled: AppConfig.shared.isExtractPoseEnabled) else { return }
                            route = .jobs(tab)
                        }
                    ),
                    isActive: Binding(
                        get: { route == .addPose },
                        set: { isPresented in
                            if !isPresented && route == .addPose {
                                route = nil
                                Task { await jobsService.refresh() }
                            }
                        }
                    )
                ) {
                    EmptyView()
                }
                .hidden()

                NavigationLink(
                    destination: JobsScreen(
                        jobsService: jobsService,
                        posesModel: model,
                        initialTab: route?.jobsTab ?? .processing,
                        onTryPose: onTryPose,
                        onAddPose: {
                            if AppConfig.canExtractPose(isEnabled: AppConfig.shared.isExtractPoseEnabled) {
                                route = .addPose
                            }
                        }
                    )
                    .id(route),
                    isActive: Binding(
                        get: { route?.isJobs == true && JobsEntryPolicy.canOpen(extractPoseEnabled: AppConfig.shared.isExtractPoseEnabled) },
                        set: { isPresented in
                            if isPresented && !JobsEntryPolicy.canOpen(extractPoseEnabled: AppConfig.shared.isExtractPoseEnabled) {
                                route = nil
                            } else if !isPresented && route?.isJobs == true {
                                route = nil
                                Task { await jobsService.refresh() }
                            }
                        }
                    )
                ) {
                    EmptyView()
                }
                .hidden()

                // The detail the camera was closed on top of. Popping it clears the state, so this
                // link disappears with it and nothing else in this session re-pushes the pose.
                if let resumedPose {
                    NavigationLink(
                        destination: PoseDetailScreen(
                            pose: resumedPose.pose,
                            model: model,
                            onTryPose: onTryPose,
                            // A private detail (Jobs / Add pose) stays private: confirming it against
                            // the public catalogue would answer 404 and show "Pose unavailable".
                            isPrivate: resumedPose.isPrivate
                        ),
                        isActive: Binding(
                            get: { self.resumedPose != nil },
                            set: { isPresented in
                                if !isPresented { self.resumedPose = nil }
                            }
                        )
                    ) {
                        EmptyView()
                    }
                    .hidden()
                }
            }
        )
    }

    private func setShowsSearch(_ shown: Bool) {
        withAnimation(SearchMotion.animation(reduceMotion: reduceMotion)) { showsSearch = shown }
        onSearchVisibilityChange(shown)
    }

    /// Artboard `02-poses-home-loaded`: the large title and three 44 pt actions on one line at the
    /// default sizes, and the actions dropped under the title at the Accessibility sizes.
    private var posesHeader: some View {
        VStack(alignment: .leading, spacing: AP.Space.space12) {
            if dynamicTypeSize.isAccessibilitySize {
                posesTitle
                HStack(spacing: AP.Space.space8) {
                    Spacer(minLength: 0)
                    headerActions
                }
            } else {
                HStack(alignment: .center, spacing: AP.Space.space8) {
                    posesTitle
                    Spacer(minLength: AP.Space.space8)
                    headerActions
                }
            }
        }
        .padding(.horizontal, AP.Space.space16)
        .padding(.top, AP.Space.space8)
        .padding(.bottom, AP.Space.space12)
    }

    private var posesTitle: some View {
        Text("Poses")
            .font(AP.Font.display)
            .foregroundStyle(AP.Color.primaryText)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private var headerActions: some View {
        HStack(spacing: AP.Space.space8) {
            APHeaderActionButton(systemImage: "magnifyingglass", accessibilityLabel: "Search") {
                setShowsMoreMenu(false)
                setShowsSearch(true)
            }
            .accessibilityIdentifier("poses.open-search")

            NavigationLink(destination: SettingsScreen(posesModel: model, onTryPose: onTryPose)) {
                APHeaderActionGlyph(systemImage: "sun.max")
            }
            .buttonStyle(APControlFillButtonStyle())
            .accessibilityLabel("Open Settings")
            .accessibilityIdentifier("poses.open-settings")

            moreButton
        }
    }

    /// The menu layer: full width and vertically scrollable at the Accessibility sizes, so a card that
    /// is taller than the screen still reaches Add pose / Jobs / Saved.
    @ViewBuilder private var moreMenuOverlay: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView {
                    moreMenuCard
                        .padding(.top, menuTopInset)
                }
            } else {
                moreMenuCard
                    .padding(.top, menuTopInset)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, AP.Space.space16)
    }

    /// Where the menu card starts: just under the header. The header's height follows the type size
    /// (one line at the default sizes, title above the actions at AX), so the inset does too.
    private var menuTopInset: CGFloat {
        let titleHeight: CGFloat = dynamicTypeSize.isAccessibilitySize ? 62 : 41
        return AP.Space.space8 + titleHeight + AP.Space.space12 + AP.HitTarget.minimum + AP.Space.space12
    }

    private var moreButton: some View {
        Button {
            setShowsMoreMenu(!showsMoreMenu)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(showsMoreMenu ? AP.Color.selectedForeground : AP.Color.primaryText)
                .frame(width: AP.HitTarget.minimum, height: AP.HitTarget.minimum)
                .background(
                    RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                        .fill(showsMoreMenu ? AP.Color.selectedBackground : AP.Color.controlFill)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More")
        .accessibilityAddTraits(showsMoreMenu ? .isSelected : [])
        .accessibilityIdentifier("poses.more")
    }

    /// `01-nav-map` "More menu": the labelled card with Add pose, Jobs and Saved. The three entry
    /// identifiers are unchanged — they moved, they did not disappear.
    private var moreMenuCard: some View {
        APMoreMenu(
            jobsActiveCount: jobsService.activeCount,
            isSignedIn: session.isSignedIn,
            isAddPoseEnabled: AppConfig.canExtractPose(isEnabled: AppConfig.shared.isExtractPoseEnabled),
            isJobsEnabled: JobsEntryPolicy.canOpen(extractPoseEnabled: AppConfig.shared.isExtractPoseEnabled),
            savedDestination: AppConfig.shared.isAccountFeatureEnabled
                ? AnyView(SavedPosesScreen(model: model, onTryPose: onTryPose))
                : nil,
            maxWidth: dynamicTypeSize.isAccessibilitySize ? nil : 296,
            onAddPose: openAddPose,
            onJobs: openJobs,
            onSavedTapped: { setShowsMoreMenu(false) }
        )
    }

    private func setShowsMoreMenu(_ shown: Bool) {
        withAnimation(SearchMotion.animation(reduceMotion: reduceMotion)) { showsMoreMenu = shown }
    }

    private func openAddPose() {
        guard AppConfig.canExtractPose(isEnabled: AppConfig.shared.isExtractPoseEnabled) else { return }
        setShowsMoreMenu(false)
        if session.isSignedIn {
            route = .addPose
        } else {
            pendingSignIn = .addPose
        }
    }

    private func openJobs() {
        guard JobsEntryPolicy.canOpen(extractPoseEnabled: AppConfig.shared.isExtractPoseEnabled) else { return }
        setShowsMoreMenu(false)
        if session.isSignedIn {
            route = .jobs(.processing)
        } else {
            pendingSignIn = .openJobs
        }
    }

    /// The catalogue body: chips, grid and paged footer, or the state panel the presentation rule
    /// picks for this model state (`APCatalogPresentationRule`, tested).
    @ViewBuilder private var content: some View {
        let rows = model.state.rows
        let visible = categoryFilter.apply(to: rows)
        let presentation = APCatalogPresentationRule.presentation(
            for: model.state,
            hasVisiblePoses: !visible.isEmpty,
            isFilterActive: categoryFilter.isActive
        )

        switch presentation {
        case .loading:
            ScrollView {
                APPoseGridSkeleton()
                    .padding(.horizontal, AP.Space.space16)
                    .padding(.top, AP.Space.space4)
                APPagingFooter(model: model, bottomInset: 0)
            }
        case .failed:
            APErrorStateView(
                title: PosesListStateCopy.errorTitle,
                message: PosesListStateCopy.errorMessage,
                retry: { Task { await model.load() } },
                style: .plain
            )
        case .empty:
            VStack(spacing: 0) {
                APEmptyStateView(
                    title: PosesListStateCopy.emptyTitle,
                    message: PosesListStateCopy.emptyMessage,
                    style: .plain
                )
                // A filtered server list can be empty on page 1 and hold rows behind it.
                APPagingFooter(model: model, bottomInset: 0)
            }
        case .noMatch:
            VStack(spacing: 0) {
                categoryChips(for: rows)
                APEmptyStateView(
                    title: APCategoryFilter.emptyTitle,
                    message: categoryFilter.message,
                    actionTitle: APCategoryFilter.recoveryTitle,
                    action: {
                        withAnimation(APCatalogMotion.animation(reduceMotion: reduceMotion)) {
                            categoryFilter.clear()
                        }
                    },
                    style: .plain
                )
            }
        case .grid:
            ScrollView {
                categoryChips(for: rows)
                APPoseGrid(poses: visible, model: model, onTryPose: onTryPose, onNearEnd: { requestNextPage() })
                    .padding(.horizontal, AP.Space.space16)
                APPagingFooter(model: model)
            }
        }
    }

    @ViewBuilder private func categoryChips(for poses: [NativePose]) -> some View {
        let categories = APCategoryFilter.categories(in: poses)
        if !categories.isEmpty {
            APCategoryFilterBar(
                categories: categories,
                filter: categoryFilter,
                onToggle: { category in
                    withAnimation(APCatalogMotion.animation(reduceMotion: reduceMotion)) {
                        categoryFilter.toggle(category)
                    }
                },
                onClear: {
                    withAnimation(APCatalogMotion.animation(reduceMotion: reduceMotion)) {
                        categoryFilter.clear()
                    }
                }
            )
            .padding(.horizontal, AP.Space.space16)
            .padding(.bottom, AP.Space.space12)
        }
    }

    private func requestNextPage() {
        Task { await model.loadMore() }
    }
}

// MARK: - Pose card

/// Prototype `.nb-card--pose-grid` + `.nb-grid-pose-item` (`components/card.css`, `components/grid.css`):
/// white surface, 2pt black border, radius 14, **no shadow**, and the pose name rendered *outside*
/// the image surface as a 14pt regular left-aligned label.
/// The category is intentionally not shown (neither reference shot has it).
struct PoseCard: View {
    let pose: NativePose
    var aspectRatio: CGFloat = 1
    /// When set, the card surface is registered as the zoom-transition source for its pose.
    var zoomNamespace: Namespace.ID?

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
            .frame(maxWidth: .infinity)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay { artwork.frame(maxWidth: .infinity, maxHeight: .infinity) }
            .clipShape(RoundedRectangle(cornerRadius: PoseSurfaceMetrics.cardCornerRadius))
            .neoSurface(
                shape: RoundedRectangle(cornerRadius: PoseSurfaceMetrics.cardCornerRadius),
                fill: AIPoseColor.surface,
                borderWidth: PoseSurfaceMetrics.cardBorderWidth,
                shadowOffset: 0
            )
            .overlay(alignment: .topTrailing) { savedBadge }
            .animation(.easeInOut(duration: 0.2), value: aspectRatio)
            .zoomTransitionSource(id: pose.id, in: zoomNamespace, cornerRadius: PoseSurfaceMetrics.cardCornerRadius)
    }

    /// Pose artwork: Kingfisher + `AppImage` downsample to the box the card actually draws.
    /// Two-tier cache (memory 64MB / disk 200MB, `AppImage.configure()`), decode off the main thread,
    /// request coalescing — so re-rendering a grid cell never re-decodes the photo. `AsyncImage` here
    /// meant a full-resolution decode inside the view body, on every render.
    private var artwork: some View {
        KFImage(pose.imageURL)
            .setProcessor(AppImage.downsample(points: PoseGridMetrics.cardArtworkPoints, contentMode: .fit))
            .onSuccess { result in
                PoseAspectRatioCache.shared.updateRatio(
                    width: result.image.size.width,
                    height: result.image.size.height,
                    for: pose.id
                )
            }
            .placeholder {
                Image(systemName: "figure.stand")
                    .font(.system(size: 44))
                    .foregroundStyle(AIPoseColor.subtext)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .resizable()
            .scaledToFill()
            .clipped()
    }

    /// `saved-list.html` marks saved cards with `.nb-saved-card__badge` (24pt pink square, top-right).
    @ViewBuilder private var savedBadge: some View {
        if pose.isSaved {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AIPoseColor.foreground)
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .neoSurface(
                    shape: RoundedRectangle(cornerRadius: NeoChromeTokens.radiusSmall),
                    fill: AIPoseColor.primary,
                    borderWidth: NeoChromeTokens.borderThin,
                    shadowOffset: 0
                )
                .padding(8)
                .accessibilityHidden(true)
        }
    }
}

/// Prototype `.nb-grid--masonry`: two fixed columns, 8pt column gap, `nb-space-md * 0.8` row gap.
enum PoseDetailLayoutMetrics {
    /// Footprint of the shared root NeoDockTabBar overlay (48pt bar + 8pt padding + breathing room).
    /// Retained as the dock-parity reference; the dock is hidden on this pushed route.
    static let sharedDockScrollInset: CGFloat = 48 + AIPoseSpacing.sm + AIPoseSpacing.lg
    static let heroCardAspectRatio: CGFloat = 1 / 1.1

    /// The hero is full-bleed (artboard `04-pose-detail-loaded`), so its box is the screen width.
    @MainActor static var heroCardWidth: CGFloat {
        let screenWidth = UIScreen.main.bounds.width > 0 ? UIScreen.main.bounds.width : 390
        return max(1, screenWidth)
    }

    @MainActor static var heroCardHeight: CGFloat {
        heroCardWidth / heroCardAspectRatio
    }

    /// Tallest photo ratio the hero decodes at card width. Twice as tall as wide covers every
    /// normal portrait; only panorama-tall photos are capped (and upscale slightly) so one pose
    /// cannot force a multi-megapixel decode.
    static let minimumDownsampleAspectRatio: CGFloat = 0.5

    /// The photo fills the card, so it is decoded at the card's width and bounded in height by the
    /// tallest ratio the card can draw.
    @MainActor static var heroArtworkPoints: CGSize {
        CGSize(width: heroCardWidth, height: heroCardWidth / minimumDownsampleAspectRatio)
    }

    /// Tallest the hero may draw: half the screen, so the title and the first instruction stay above
    /// the fold on every phone.
    @MainActor static var heroMaxHeight: CGFloat {
        let screenHeight = UIScreen.main.bounds.height > 0 ? UIScreen.main.bounds.height : 844
        return max(240, screenHeight * 0.5)
    }

    /// Extra room under the last instruction so the pinned CTA never covers it.
    static let ctaClearance: CGFloat = AP.HitTarget.minimum + AP.Space.space24

    /// Card ratio for the hero: the photo's own ratio when known, otherwise the prototype card.
    /// One place for this rule so the card and its tests cannot disagree.
    static func heroAspectRatio(cachedPhotoRatio: CGFloat?) -> CGFloat {
        guard let ratio = cachedPhotoRatio, ratio.isFinite, ratio > 0 else {
            return heroCardAspectRatio
        }
        return ratio
    }
}

/// The failed-load state: the same stand-in glyph the grid uses. It is drawn as a card overlay rather
/// than from `KFImage`'s placeholder closure, because `KFImage` keeps the placeholder it was built
/// with — a load that fails after the first layout would otherwise leave the shimmer sweeping forever.
private struct PoseHeroFailureFill: View {
    var body: some View {
        ZStack {
            AP.Color.controlFill
            Image(systemName: "figure.stand")
                .font(.system(size: 72))
                .foregroundStyle(AP.Color.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(PoseDetailCopy.heroUnavailable)
    }
}

struct PoseDetailScreen: View {
    let pose: NativePose
    @ObservedObject var model: PosesViewModel
    var onTryPose: (CameraPoseRequest) -> Void
    var isPrivate: Bool = false
    @ObservedObject private var aspectRatioCache = PoseAspectRatioCache.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var heroDidFail = false
    @State private var pendingSignIn: SignInIntent?
    /// Report §3.6 (`pose-detail.html` unavailable state): set only by the definitive
    /// `poseNotFound` signal from `PosesViewModel.confirmPublished` — a stale/deleted pose renders
    /// the shared error state instead of dead detail content.
    @State private var isUnavailable = false
    @Environment(\.dismiss) private var dismiss
    private let boundary = ServiceLocator.sessionBoundary
    init(pose: NativePose, model: PosesViewModel, onTryPose: @escaping (CameraPoseRequest) -> Void, isPrivate: Bool = false) {
        self.pose = pose
        self.model = model
        self.onTryPose = onTryPose
        self.isPrivate = isPrivate
    }

    /// Saved state and in-flight state come from the shared model, so navigating away mid-request and
    /// coming back cannot leave this screen showing a stale answer.
    private var isSaved: Bool { model.savedState(for: pose) }
    private var isSaving: Bool { model.isBookmarkInFlight(pose.id) }
    /// Why the save control is inert, in the user's terms — never a generic "unavailable".
    private var bookmarkUnavailableHint: String {
        if model.bookmarkService == nil { return "Saving is unavailable right now" }
        if !model.canSave(pose) { return SavedMutationCopy.poseUnavailable }
        return ""
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
        .background(AP.Color.background)
        .neoHiddenNavigationBar()
        // Saving is account-scoped, so a guest is asked to sign in and the interrupted save
        // resumes once — never silently dropped, never replayed later (FEAT-013 sign-in gating).
        .signInPrompt($pendingSignIn) { intent in
            guard intent == .savePose else { return }
            Task { await toggleBookmark() }
        }
        // F5: a save/unsave failure is a bottom snackbar above the pinned bar, never mid-screen.
        .apSnackbar(
            model.bookmarkError,
            tone: .error,
            actionTitle: "Dismiss",
            action: { model.bookmarkError = nil },
            onDismiss: { model.bookmarkError = nil }
        )
        .task {
            // §3.6: a detail route is only valid while the pose is still confirmed as published.
            // Private poses skip confirmPublished (D13)
            if !isPrivate {
                if !(await model.confirmPublished(pose)) { isUnavailable = true }
            }
        }
    }

    private var detailContent: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    poseHeroCard
                    VStack(alignment: .leading, spacing: AP.Space.space16) {
                        // `poseDetail.title` keeps its label (the pose name) and value (the pose id) so
                        // the E2E lane can prove which pose the screen came back to.
                        Text(pose.name)
                            .font(AP.Font.display)
                            .foregroundStyle(AP.Color.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("poseDetail.title")
                            .accessibilityValue(pose.id)

                        let tags = PoseDetailTags.chips(for: pose)
                        if !tags.isEmpty {
                            tagRow(tags)
                        }

                        if !pose.instructions.isEmpty {
                            Text(PoseDetailCopy.howToPose)
                                .font(AP.Font.heading)
                                .foregroundStyle(AP.Color.primaryText)
                                .accessibilityAddTraits(.isHeader)
                                .padding(.top, AP.Space.space4)
                            VStack(alignment: .leading, spacing: AP.Space.space12) {
                                ForEach(Array(pose.instructions.enumerated()), id: \.offset) { index, step in
                                    APNumberedStep(
                                        number: index + 1,
                                        text: PoseDetailTags.stepText(step)
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, AP.Space.space16)
                    .padding(.top, AP.Space.space16)
                    // The pinned CTA is a safe-area inset, but the hero's top bleed makes the scroll
                    // view taller than the inset accounts for; this keeps the last step clear of it.
                    .padding(.bottom, PoseDetailLayoutMetrics.ctaClearance)
                }
            }
            // BUG-261029-06: the CTA is pinned below the content instead of living at the end of it.
            .safeAreaInset(edge: .bottom, spacing: 0) { usePoseBar }
            // The hero reaches y = 0 (artboard `04-pose-detail-loaded`): the *scroll view* ignores the
            // top safe area, so the artwork bleeds under the status bar while the floating back control
            // below stays inside it.
            .ignoresSafeArea(.container, edges: .top)
            backControl
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// The floating back control over the hero (F2: the one shared component, `surface` fill for
    /// contrast on the photo), inside the safe area so the status bar never covers it.
    private var backControl: some View {
        APBackButton(style: .overlay, accessibilityLabel: PoseDetailCopy.back) { dismiss() }
            .padding(.leading, AP.Space.space16)
            .padding(.top, AP.Space.space8)
            .accessibilityIdentifier("poseDetail.back")
    }

    /// Tag chips wrap: one per row at the Accessibility sizes.
    @ViewBuilder private func tagRow(_ tags: [String]) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AP.Space.space8) {
                ForEach(tags, id: \.self) { APTagChip(title: $0) }
            }
        } else {
            HStack(spacing: AP.Space.space8) {
                ForEach(tags, id: \.self) { APTagChip(title: $0) }
            }
        }
    }

    /// `Save pose` / `Saved`. Saving needs an account: a pose is only shown as saved once the server
    /// confirmed it, so this never flips local state up front and never invents a save.
    @ViewBuilder private var saveControl: some View {
        if isSaved {
            APCategoryChip(title: PoseDetailCopy.saved, isSelected: true) {
                Task { await toggleBookmark() }
            }
            .disabled(isSaving)
            .accessibilityLabel("Remove from saved")
            .accessibilityIdentifier("poseDetail.saveButton")
            .accessibilityHint(bookmarkUnavailableHint)
        } else {
            Button {
                Task { await toggleBookmark() }
            } label: {
                HStack(spacing: AP.Space.space8) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 16, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(PoseDetailCopy.save)
                        .font(AP.Font.heading)
                }
                .padding(.horizontal, AP.Space.space16)
                .frame(minHeight: AP.HitTarget.minimum)
            }
            .buttonStyle(APControlFillButtonStyle())
            // No bookmark service: nothing could confirm the save, so the control is inert rather
            // than silently lying about the pose's saved state.
            .disabled(isSaving || model.bookmarkService == nil || !model.canSave(pose))
            .accessibilityLabel("Save pose")
            .accessibilityIdentifier("poseDetail.saveButton")
            .accessibilityHint(bookmarkUnavailableHint)
        }
    }

    /// The always-visible primary action (`poseDetail.use`).
    ///
    /// `.safeAreaInset` is what makes this correct on every device instead of a fixed height pinned
    /// over the content: the bar is placed above the home indicator (safe-area aware), and the
    /// `ScrollView` is inset by exactly the bar's height, so no instruction and no Save control can
    /// end up hidden behind it. The label wraps and the bar grows with Dynamic Type, and the content
    /// inset follows it automatically — so the CTA stays on screen at accessibility sizes too.
    private var usePoseBar: some View {
        HStack(spacing: AP.Space.space8) {
            if showsSaveControl {
                saveBarButton
            }
            Button {
                routeTryPoseToCamera(pose, isPrivate: isPrivate, onTryPose: onTryPose)
            } label: {
                HStack(spacing: AP.Space.space8) {
                    Image(systemName: "camera")
                        .font(.system(size: 17, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(PoseDetailCopy.tryPose)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .buttonStyle(APPrimaryButtonStyle())
            // Stable E2E handle: the Maestro flows and the detail tests target this id.
            .accessibilityIdentifier("poseDetail.use")
        }
        .padding(.horizontal, AP.Space.space16)
        .padding(.top, AP.Space.space12)
        .padding(.bottom, AP.Space.space8)
        .frame(maxWidth: .infinity)
        // Continues under the home indicator instead of leaving a strip of screen behind it.
        .background(AP.Color.background.ignoresSafeArea(edges: .bottom))
    }

    private var showsSaveControl: Bool {
        AppConfig.shared.isAccountFeatureEnabled && !isPrivate
    }

    /// F9: the square Save control, left of the primary action, same height and aligned. Saved shows
    /// the filled bookmark on the selected fill.
    private var saveBarButton: some View {
        Button {
            Task { await toggleBookmark() }
        } label: {
            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isSaved ? AP.Color.selectedForeground : AP.Color.primaryText)
                .frame(width: 52, height: 52)
                .background(
                    RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                        .fill(isSaved ? AP.Color.selectedBackground : AP.Color.controlFill)
                )
        }
        .buttonStyle(APDockPressStyle())
        .disabled(isSaving || model.bookmarkService == nil || !model.canSave(pose))
        .accessibilityLabel(isSaved ? "Remove from saved" : "Save pose")
        .accessibilityIdentifier("poseDetail.saveButton")
        .accessibilityHint(bookmarkUnavailableHint)
    }

    /// `04-pose-detail-unavailable`: the shared error panel, a Retry, and the way back to the list.
    private var unavailableState: some View {
        VStack(spacing: 0) {
            APErrorStateView(
                title: PoseDetailCopy.unavailableTitle,
                message: PoseDetailCopy.unavailableMessage,
                retryTitle: PoseDetailCopy.retry,
                retry: { Task { await confirmAvailability() } },
                style: .plain
            )
            Button(PoseDetailCopy.backToPoses) { dismiss() }
                .buttonStyle(.plain)
                .font(AP.Font.supporting.weight(.semibold))
                .foregroundStyle(AP.Color.accentText)
                .apMinimumHitTarget()
                // The unavailable state's way out keeps its own handle (a single view can carry only
                // one identifier; the floating control keeps `poseDetail.back`).
                .accessibilityIdentifier("poseDetail.returnToPoses")
                .padding(.bottom, AP.Space.space32)
        }
    }

    private func confirmAvailability() async {
        guard !isPrivate else {
            isUnavailable = false
            return
        }
        isUnavailable = !(await model.confirmPublished(pose))
    }

    /// Hero: the photo fills the width edge to edge (artboard `04-pose-detail-loaded`), the card
    /// taking the photo's own aspect ratio so there is no letterbox. The ratio comes from the grid's
    /// cache (the card the user tapped already decoded the same photo); until it is known the
    /// prototype's `1 / 1.1` is used with a flat skeleton at that size, and the card resizes once the
    /// photo loads.
    ///
    /// The photo is loaded with Kingfisher through `AppImage` and downsampled to the drawn width
    /// (memory + disk cache, decode off the main thread); a full-resolution decode here would stall
    /// the pushed screen for ~20-40ms on every appearance.
    private var poseHeroCard: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .aspectRatio(heroAspectRatio, contentMode: .fit)
            // A portrait photo must not eat the screen: the hero stops at half the screen height and
            // the artwork fills that box instead of shrinking to fit it.
            .frame(maxHeight: PoseDetailLayoutMetrics.heroMaxHeight)
            .overlay {
                KFImage(pose.imageURL)
                    .setProcessor(AppImage.downsample(points: PoseDetailLayoutMetrics.heroArtworkPoints, contentMode: .fit))
                    .onSuccess { result in
                        heroDidFail = false
                        aspectRatioCache.updateRatio(
                            width: result.image.size.width,
                            height: result.image.size.height,
                            for: pose.id
                        )
                    }
                    .onFailure { _ in heroDidFail = true }
                    .placeholder {
                        AP.Color.controlFill
                            .accessibilityLabel(PoseDetailCopy.heroLoading)
                    }
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // Card-level, so it is painted whenever the screen re-renders (including a failure that
            // lands after the first layout) and covers the placeholder it replaces.
            .overlay {
                if heroDidFail { PoseHeroFailureFill() }
            }
            .clipped()
            // Reduce Motion: the one resize still happens, it just snaps instead of easing.
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: heroAspectRatio)
    }

    private var heroAspectRatio: CGFloat {
        PoseDetailLayoutMetrics.heroAspectRatio(cachedPhotoRatio: aspectRatioCache.ratios[pose.id])
    }

    private static let heroCardCornerRadius: CGFloat = NeoChromeTokens.radiusLarge

    /// Saving needs an account: a pose is only shown as saved once the server confirmed it, so this
    /// never flips local state up front and never invents a save for a missing bookmark service.
    private func toggleBookmark() async {
        guard AppConfig.shared.isAccountFeatureEnabled, !isSaving else { return }
        guard await boundary.hasStoredSession() else {
            pendingSignIn = .savePose
            return
        }
        // The model owns the attempt (and its in-flight flag); this screen only reads the result.
        await model.toggleSaved(for: pose.withSaved(isSaved))
    }
}

/// "Use this pose" hands the camera the pose **and** its lane: a private pose restored after the
/// camera came back must not be confirmed against the public catalogue (BUG-261029-05 review).
func routeTryPoseToCamera(_ pose: NativePose, isPrivate: Bool, onTryPose: (CameraPoseRequest) -> Void) {
    onTryPose(CameraPoseRequest(pose: pose, isPrivate: isPrivate))
}

// MARK: - Search

/// Prototype `screens/search.html` (`.nb-search-screen`): full-height workspace with a 52pt nav bar,
/// a 56pt search field, and either `.nb-search-discovery` (blank) or `.nb-search-results-panel`.
/// The dock tab bar is drawn by `AppFeatureRoot` above this screen, so the scroll areas only need to
/// reserve `40px + safe-area` at the bottom (see `PoseGridMetrics.searchDockClearance`).
struct SearchScreen: View {
    @ObservedObject var model: PosesViewModel
    /// Supplied when the workspace is overlaid in place (the dock is hidden while it is up, so the
    /// back control is the only way out); falls back to the navigation `dismiss` action when pushed.
    var onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var isFieldFocused: Bool
    @State private var selectedSource: PoseLibraryFilter = .all
    /// AX only: the source filter row stays tucked until the compact toggle is opened.
    @State private var showsSourceFilters = false

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // At the AX sizes the header, the field and the chips are taller than the space above
                // the keyboard; scrolling keeps them from being pushed off the top of the screen.
                ScrollView {
                    content
                }
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AP.Color.background)
        .animation(SearchMotion.animation(reduceMotion: reduceMotion), value: showsDiscovery)
        .animation(SearchMotion.animation(reduceMotion: reduceMotion), value: model.state.panelStateKey)
        .neoHiddenNavigationBar()
        .task {
            selectedSource = .all
            model.filter = .all
            await model.load()
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            searchHeader
            searchField
            if showsDiscovery {
                discovery
            } else {
                resultsPanel
            }
        }
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    // MARK: header (`03-search-idle`: Back, then the large Search title)

    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: AP.Space.space12) {
            Button(action: close) {
                APHeaderActionGlyph(systemImage: "chevron.left")
            }
            .buttonStyle(APControlFillButtonStyle())
            .accessibilityLabel("Back")
            .accessibilityIdentifier("search.back")

            Text(SearchResultsCopy.screenTitle)
                .font(AP.Font.display)
                .foregroundStyle(AP.Color.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AP.Space.space16)
        .padding(.top, AP.Space.space8)
        .padding(.bottom, AP.Space.space12)
    }

    // MARK: search field (`.nb-search-field` replaced)

    private var searchField: some View {
        HStack(spacing: AP.Space.space8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AP.Color.accentText)
                .accessibilityHidden(true)

            TextField("Search poses", text: Binding(get: { model.query }, set: { model.updateQuery($0) }))
                .font(AP.Font.body)
                .foregroundStyle(AP.Color.primaryText)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .submitLabel(.search)
                .frame(minHeight: AP.HitTarget.minimum)
                .focused($isFieldFocused)
                .onSubmit {
                    // The keyboard's Search key only dismisses the keyboard: the debounced search has
                    // already run, and re-loading would rebuild the grid over loaded artwork.
                    isFieldFocused = false
                }
                .accessibilityIdentifier("search.field")

            if !model.query.isEmpty {
                Button { clearSearch() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AP.Color.primaryText)
                        .frame(width: AP.HitTarget.minimum, height: AP.HitTarget.minimum)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, AP.Space.space16)
        .padding(.trailing, AP.Space.space8)
        .padding(.vertical, AP.Space.space4)
        .frame(minHeight: 56)
        .background(
            RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                .fill(isFieldFocused || !model.query.isEmpty ? AP.Color.selectedBackground : AP.Color.controlFill)
        )
        .padding(.horizontal, AP.Space.space16)
        .padding(.bottom, AP.Space.space16)
    }

    private func clearSearch() {
        withAnimation(SearchMotion.animation(reduceMotion: reduceMotion)) {
            selectedSource = .all
            model.filter = .all
        }
        model.cancelPendingSearch()
        Task { await model.startSearch(for: "") }
    }

    // MARK: discovery (`03-search-idle`)

    private var showsDiscovery: Bool {
        model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedSource == .all
    }

    private var discovery: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AP.Space.space12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Recent")
                        .font(AP.Font.heading)
                        .foregroundStyle(AP.Color.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                    Button("Clear") {
                        withAnimation(SearchMotion.animation(reduceMotion: reduceMotion)) {
                            selectedSource = .all
                            model.filter = .all
                        }
                        model.cancelPendingSearch()
                        Task { await model.startSearch(for: "") }
                    }
                    .buttonStyle(.plain)
                    .font(AP.Font.caption.weight(.semibold))
                    .foregroundStyle(AP.Color.accentText)
                    .apMinimumHitTarget()
                }

                // Chips wrap: at the Accessibility sizes one chip per row, never a clipped line.
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: AP.Space.space8) {
                        ForEach(SearchScreenContract.recentSearches, id: \.self) { term in
                            recentChip(term, fillsWidth: true)
                        }
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AP.Space.space8) {
                            ForEach(SearchScreenContract.recentSearches, id: \.self) { term in
                                recentChip(term, fillsWidth: false)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, AP.Space.space16)
            .padding(.bottom, APGridLayout.rowSpacing)
        }
    }

    private func recentChip(_ term: String, fillsWidth: Bool) -> some View {
        APSearchTermChip(title: term, systemImage: "clock") {
            Task { await model.startSearch(for: term) }
        }
        .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
        .accessibilityIdentifier("search.recent.\(term.lowercased())")
    }

    // MARK: results (`03-search-results`)

    @ViewBuilder private var resultsPanel: some View {
        let presentation = resultsPresentation

        if case .grid = presentation {
            VStack(alignment: .leading, spacing: 0) {
                resultsHeader
                ScrollView {
                    sourceFilterRow
                    APPoseGrid(
                        poses: model.state.rows,
                        model: model,
                        onNearEnd: { Task { await model.loadMore() } }
                    )
                    .padding(.horizontal, AP.Space.space16)
                    searchPagingFooter
                }
            }
        } else {
            APSearchStatePanel(
                model: model,
                presentation: presentation,
                failureTitle: PoseResultsStateCopy.searchErrorTitle,
                failureMessage: PoseResultsStateCopy.searchErrorMessage,
                emptyTitle: SearchResultsCopy.emptyTitle(query: model.query, filter: model.filter),
                emptyMessage: SearchResultsCopy.emptyMessage(query: model.query, filter: model.filter),
                emptyActionTitle: SearchResultsCopy.emptyRecoveryTitle(query: model.query, filter: model.filter)
                    ?? "Clear search",
                onEmptyAction: {
                    withAnimation(SearchMotion.animation(reduceMotion: reduceMotion)) {
                        selectedSource = .all
                        model.filter = .all
                    }
                    model.cancelPendingSearch()
                    Task { await model.startSearch(for: "") }
                },
                onRetry: { Task { await model.load() } },
                emptyIdentifier: "search-empty-banner",
                retryIdentifier: "search.retry"
            )
        }
    }

    @ViewBuilder private var searchPagingFooter: some View {
        if APSearchChrome.mountsPagingFooter(for: resultsPresentation) {
            APPagingFooter(model: model, bottomInset: APGridLayout.rowSpacing)
        }
    }

    private var resultsPresentation: APCatalogPresentation {
        APCatalogPresentationRule.presentation(
            for: model.state,
            hasVisiblePoses: !model.state.rows.isEmpty,
            isFilterActive: model.filter != .all
        )
    }

    /// The source filter, one selection. Compact at the default sizes (one scrolling row, inside the
    /// results scroll), tucked behind a single toggle at the AX sizes so it cannot eat the viewport.
    /// The `search.source.*` identifiers live on the chips in both states.
    @ViewBuilder private var sourceFilterRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AP.Space.space8) {
                Button {
                    showsSourceFilters.toggle()
                } label: {
                    Text("Filter: \(selectedSource.rawValue)")
                        .font(AP.Font.supporting)
                        .lineLimit(1)
                        .padding(.horizontal, AP.Space.space16)
                        .frame(maxWidth: .infinity, minHeight: AP.HitTarget.minimum, alignment: .leading)
                }
                .buttonStyle(APControlFillButtonStyle())
                .accessibilityLabel("Filter, \(selectedSource.rawValue)")
                .accessibilityAddTraits(showsSourceFilters ? .isSelected : [])

                if showsSourceFilters {
                    ForEach(SearchScreenContract.sourceFilters) { source in
                        sourceChip(source, fillsWidth: true)
                    }
                }
            }
            .padding(.horizontal, AP.Space.space16)
            .padding(.bottom, AP.Space.space8)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AP.Space.space8) {
                    ForEach(SearchScreenContract.sourceFilters) { source in
                        sourceChip(source, fillsWidth: false)
                    }
                }
                .padding(.horizontal, AP.Space.space16)
            }
            .padding(.bottom, AP.Space.space8)
        }
    }

    private func sourceChip(_ source: PoseLibraryFilter, fillsWidth: Bool) -> some View {
        APCategoryChip(
            title: source.rawValue,
            isSelected: selectedSource == source,
            fillsWidth: fillsWidth,
            action: { apply(source: source) }
        )
        .accessibilityIdentifier("search.source.\(source.id)")
    }

    private func apply(source: PoseLibraryFilter) {
        withAnimation(SearchMotion.animation(reduceMotion: reduceMotion)) {
            selectedSource = source
            model.filter = source
        }
        Task { await model.load() }
    }

    /// `03-search-results`: the count and the grid, nothing else. The old kicker + heading block ate
    /// the viewport at the AX sizes and is gone from the design; its two text identifiers
    /// (`search-results-kicker`, `search-results-heading`) go with it and are reported to QA.
    @ViewBuilder private var resultsHeader: some View {
        if !SearchResultsCopy.hidesCount(for: model.state) {
            Text(SearchResultsCopy.countLabel(for: model.state))
                .font(AP.Font.supporting)
                .foregroundStyle(AP.Color.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AP.Space.space16)
                .padding(.bottom, AP.Space.space8)
                .accessibilityIdentifier("search-results-count")
        }
    }

    /// `03-search-no-results`: the same borderless panel as the catalogue, with the search copy.
    private var noMatchPanel: some View {
        APEmptyStateView(
            title: SearchResultsCopy.emptyTitle(query: model.query, filter: model.filter),
            message: SearchResultsCopy.emptyMessage(query: model.query, filter: model.filter),
            actionTitle: SearchResultsCopy.emptyRecoveryTitle(query: model.query, filter: model.filter)
                ?? "Clear search",
            action: {
                withAnimation(SearchMotion.animation(reduceMotion: reduceMotion)) {
                    selectedSource = .all
                    model.filter = .all
                }
                model.cancelPendingSearch()
                Task { await model.startSearch(for: "") }
            },
            style: .plain
        )
        .accessibilityIdentifier("search-empty-banner")
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
    var onTryPose: (CameraPoseRequest) -> Void = { _ in }
    @StateObject private var session = SessionPresenceModel()
    @State private var pendingSignIn: SignInIntent?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var stage: SavedSurfaceStage {
        SavedSurfaceStage.resolve(isSessionResolved: session.isResolved, isSignedIn: session.isSignedIn)
    }

    var body: some View {
        if AppConfig.shared.isAccountFeatureEnabled {
            VStack(spacing: 0) {
                header(for: stage)
                body(by: stage)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(AP.Color.background)
            .neoHiddenNavigationBar()
            .task { session.start() }
            // A successful sign-in flips `SessionPresenceModel` through the boundary's `.signedIn`
            // event, which mounts the list and loads it — no explicit resume needed here.
            .signInPrompt($pendingSignIn)
        } else {
            EmptyView()
        }
    }

    // MARK: header (`06-saved-populated`: back, title, count)

    private func header(for stage: SavedSurfaceStage) -> some View {
        VStack(alignment: .leading, spacing: AP.Space.space8) {
            APBackButton { dismiss() }
                .accessibilityIdentifier("saved.back")

            Text("Saved")
                .font(AP.Font.display)
                .foregroundStyle(AP.Color.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            // The count only belongs to the signed-in collection: the gate must not show the
            // catalogue's row count (the model still holds the Poses tab's list at this point).
            if case .list = stage, case .loaded(let poses) = model.state, !poses.isEmpty {
                Text(SavedCountCopy.label(poses.count))
                    .font(AP.Font.supporting)
                    .foregroundStyle(AP.Color.secondaryText)
                    .accessibilityIdentifier("saved.count")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AP.Space.space16)
        .padding(.top, AP.Space.space8)
        .padding(.bottom, AP.Space.space12)
    }

    @ViewBuilder private func body(by stage: SavedSurfaceStage) -> some View {
        switch stage {
        case .resolvingSession:
            // `06-saved-loading`: the list's own skeleton, not a spinner.
            VStack(spacing: 0) {
                APSavedListSkeleton(
                    rows: dynamicTypeSize.isAccessibilitySize ? 3 : 5
                )
                Spacer(minLength: 0)
            }
            .accessibilityIdentifier("saved.loading")
        case .signInRequired:
            savedSignInRequired
        case .list:
            APSavedSurface(model: model) { listBody }
        }
    }

    /// The signed-in collection: state panels while loading/failed/empty, the row list once loaded.
    @ViewBuilder private var listBody: some View {
        let presentation = APCatalogPresentationRule.presentation(
            for: model.state,
            hasVisiblePoses: !model.state.rows.isEmpty,
            isFilterActive: false
        )
        switch presentation {
        case .loading:
            VStack(spacing: 0) {
                APSavedListSkeleton(rows: dynamicTypeSize.isAccessibilitySize ? 3 : 5)
                Spacer(minLength: 0)
            }
            .accessibilityIdentifier("saved.loading")
        case .failed:
            VStack(spacing: 0) {
                APErrorStateView(
                    title: PoseResultsStateCopy.savedErrorTitle,
                    message: PoseResultsStateCopy.savedErrorMessage,
                    retryTitle: PoseResultsStateCopy.retryActionTitle,
                    retry: { Task { await model.load() } },
                    style: .plain
                )
                .accessibilityIdentifier("saved.retry")
                // A failed page is not the end of the list: keep the paging footer reachable.
                APPagingFooter(model: model, bottomInset: AP.Space.space16)
            }
        case .empty, .noMatch:
            VStack(spacing: 0) {
                APEmptyStateView(
                    title: PoseResultsStateCopy.savedEmptyTitle,
                    message: PoseResultsStateCopy.savedEmptyMessage,
                    actionTitle: PoseResultsStateCopy.browseCommunityActionTitle,
                    action: { dismiss() },
                    style: .plain,
                    glyph: "bookmark"
                )
                .accessibilityIdentifier("saved.browseCommunity")
                APPagingFooter(model: model, bottomInset: AP.Space.space16)
            }
        case .grid:
            APSavedList(
                poses: model.state.rows,
                model: model,
                onTryPose: onTryPose,
                onNearEnd: { Task { await model.loadMore() } }
            )
        }
    }

    /// FEAT-013 auth gate. Copy stays native (`SignInRequiredPanel` in the KMP `SavedScreen`); the
    /// presentation is the shared state panel with the account action below it. The gate keeps its
    /// existing semantics: the tap opens the same sign-in prompt (`SignInIntent.openSaved`).
    private var savedSignInRequired: some View {
        // F4: the one shared state panel — accent-tint circle, centred copy, wide action.
        APEmptyStateView(
            title: PoseResultsStateCopy.savedSignInTitle,
            message: PoseResultsStateCopy.savedSignInMessage,
            actionTitle: "Sign in",
            action: { pendingSignIn = .openSaved },
            style: .plain,
            glyph: "bookmark"
        )
        .accessibilityIdentifier("saved.signIn")
    }
}

/// Copy for the paged-list footer. Native (no prototype surface paginates), kept in one place so
/// the footer, its accessibility labels and its tests cannot disagree.
/// Footer of a paged list. Shows one of: the auto-fetch spinner, the failed-page retry, or the
/// explicit "Load more results" button once the automatic fetches are spent. Renders nothing at the
/// real end of the list, so a caller can mount it unconditionally.
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
