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
    var onTryPose: (NativePose) -> Void = { _ in }
    /// Lets `AppFeatureRoot` hide the dock's active pill while the Search overlay is up: Search is
    /// not a tab, and `reference/search-blank.png` shows both dock items plain grey.
    var onSearchVisibilityChange: (Bool) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
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
        .task {
            session.start()
            if case .idle = model.state { await model.load() }
            await jobsService.refresh()
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
            }
        )
    }

    private func setShowsSearch(_ shown: Bool) {
        withAnimation(SearchMotion.animation(reduceMotion: reduceMotion)) { showsSearch = shown }
        onSearchVisibilityChange(shown)
    }

    /// ONE row: left-aligned page title plus the actions, per `nav-bar.css:60-80`
    private var posesHeader: some View {
        HStack(spacing: AIPoseSpacing.sm) {
            // `.nb-nav-bar__center { flex: 1 1 auto }` with a left-aligned title.
            Text("Poses")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(AIPoseColor.foreground)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            if AppConfig.canExtractPose(isEnabled: AppConfig.shared.isExtractPoseEnabled) {
                Button {
                    guard AppConfig.canExtractPose(isEnabled: AppConfig.shared.isExtractPoseEnabled) else { return }
                    if session.isSignedIn {
                        route = .addPose
                    } else {
                        pendingSignIn = .addPose
                    }
                } label: {
                    PosesHeaderIconLabel(systemImage: "plus")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add pose")
                .accessibilityIdentifier("poses.add-pose")
            }

            if JobsEntryPolicy.canOpen(extractPoseEnabled: AppConfig.shared.isExtractPoseEnabled) {
                Button {
                    guard JobsEntryPolicy.canOpen(extractPoseEnabled: AppConfig.shared.isExtractPoseEnabled) else { return }
                    if session.isSignedIn {
                        route = .jobs(.processing)
                    } else {
                        pendingSignIn = .openJobs
                    }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        PosesHeaderIconLabel(systemImage: "clock.arrow.circlepath")
                        if session.isSignedIn && jobsService.activeCount > 0 {
                            Text("\(jobsService.activeCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(AIPoseColor.surface)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(AIPoseColor.error)
                                .clipShape(Capsule())
                                .offset(x: 4, y: -4)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Jobs\(session.isSignedIn && jobsService.activeCount > 0 ? ", \(jobsService.activeCount) active" : "")")
                .accessibilityIdentifier("poses.jobs")
            }

            Button { setShowsSearch(true) } label: {
                PosesHeaderIconLabel(systemImage: "magnifyingglass")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search")
            .accessibilityIdentifier("poses.open-search")

            if AppConfig.shared.isAccountFeatureEnabled {
                NavigationLink(destination: SavedPosesScreen(model: model, onTryPose: onTryPose)) {
                    PosesHeaderIconLabel(systemImage: "bookmark.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Saved poses")
                .accessibilityIdentifier("poses.header.saved")
            }

            NavigationLink(destination: SettingsScreen(posesModel: model, onTryPose: onTryPose)) {
                PosesHeaderIconLabel(systemImage: "gearshape.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Settings")
            .accessibilityIdentifier("poses.open-settings")
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
            // The footer still mounts: a server-filtered list can be empty on page 1 and hold
            // matches on a later page.
            VStack(spacing: 0) {
                FeatureStateView(
                    tone: .empty,
                    title: PosesListStateCopy.emptyTitle,
                    message: PosesListStateCopy.emptyMessage
                )
                .padding(.horizontal, PoseGridMetrics.horizontalPadding)
                PagingFooter(model: model, bottomInset: 0)
            }
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
                    PoseGrid(poses: poses, model: model, onTryPose: onTryPose, onNearEnd: { requestNextPage() })
                        .padding(.horizontal, PoseGridMetrics.horizontalPadding)
                    PagingFooter(model: model)
                }
            }
        }
    }

    private func requestNextPage() {
        Task { await model.loadMore() }
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
            .neoSurface(
                shape: RoundedRectangle(cornerRadius: NeoChromeTokens.radiusMedium),
                fill: fill,
                borderWidth: NeoChromeTokens.borderThin,
                shadowOffset: 0
            )
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
@MainActor
struct PoseGrid: View {
    let poses: [NativePose]
    @ObservedObject var model: PosesViewModel
    var onTryPose: (NativePose) -> Void = { _ in }
    /// Fired when one of the last rows is drawn, so the caller can page in the next batch.
    var onNearEnd: (() -> Void)?
    @ObservedObject private var aspectRatioCache: PoseAspectRatioCache
    @State private var columnByPoseID: [String: Int]
    @Namespace private var zoomNamespace

    private struct MasonryItem: Identifiable {
        let index: Int
        let pose: NativePose
        var id: String { pose.id }
    }

    init(
        poses: [NativePose],
        model: PosesViewModel,
        onTryPose: @escaping (NativePose) -> Void = { _ in },
        onNearEnd: (() -> Void)? = nil
    ) {
        self.poses = poses
        _model = ObservedObject(wrappedValue: model)
        self.onTryPose = onTryPose
        self.onNearEnd = onNearEnd
        let cache = PoseAspectRatioCache.shared
        _aspectRatioCache = ObservedObject(wrappedValue: cache)
        _columnByPoseID = State(initialValue: Self.assignments(for: poses, using: cache))
    }

    private var itemsByColumn: [[MasonryItem]] {
        var columns = Array(repeating: [MasonryItem](), count: 2)
        for (index, pose) in poses.enumerated() {
            let column = columnByPoseID[pose.id] ?? (index % 2)
            columns[column].append(MasonryItem(index: index, pose: pose))
        }
        return columns
    }

    var body: some View {
        let columns = itemsByColumn
        return HStack(alignment: .top, spacing: PoseGridMetrics.columnSpacing) {
            ForEach(0..<2, id: \.self) { columnIndex in
                LazyVStack(alignment: .leading, spacing: PoseGridMetrics.rowSpacing) {
                    ForEach(columns[columnIndex]) { item in
                        NavigationLink(
                            destination: PoseDetailScreen(pose: item.pose, model: model, onTryPose: onTryPose)
                                .zoomTransition(sourceID: item.pose.id, in: zoomNamespace)
                        ) {
                            PoseCard(
                                pose: item.pose,
                                aspectRatio: aspectRatioCache.ratio(for: item.pose.id),
                                zoomNamespace: zoomNamespace
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(
                            item.index == 0 ? "poses.first-card" : "poses.card.\(item.pose.id)"
                        )
                        .accessibilitySortPriority(Double(poses.count - item.index))
                        // The last rows coming into view is the scroll trigger for the next page.
                        .onAppear {
                            guard item.index >= poses.count - 4 else { return }
                            onNearEnd?()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear(perform: rebuildAssignments)
        .onChange(of: poses.map(\.id)) { _ in rebuildAssignments() }
        .onReceive(
            aspectRatioCache.$ratios
                .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
                .removeDuplicates()
        ) { _ in
            rebuildAssignments()
        }
    }

    private static func assignments(for poses: [NativePose], using cache: PoseAspectRatioCache) -> [String: Int] {
        let columns = PoseGridMetrics.columnAssignments(
            for: poses.map { cache.ratio(for: $0.id) },
            columnWidth: PoseGridMetrics.columnWidth
        )
        return Dictionary(uniqueKeysWithValues: zip(poses.map(\.id), columns))
    }

    private func rebuildAssignments() {
        let updated = Self.assignments(for: poses, using: aspectRatioCache)
        guard updated != columnByPoseID else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            columnByPoseID = updated
        }
    }
}

enum PoseDetailLayoutMetrics {
    /// Footprint of the shared root NeoDockTabBar overlay (48pt bar + 8pt padding + breathing room).
    /// Retained as the dock-parity reference; the dock is hidden on this pushed route.
    static let sharedDockScrollInset: CGFloat = 48 + AIPoseSpacing.sm + AIPoseSpacing.lg
    static let heroCardAspectRatio: CGFloat = 1 / 1.1

    @MainActor static var heroCardWidth: CGFloat {
        let screenWidth = UIScreen.main.bounds.width > 0 ? UIScreen.main.bounds.width : 390
        return max(1, screenWidth - 2 * PoseSurfaceMetrics.horizontalPadding)
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

    /// Card ratio for the hero: the photo's own ratio when known, otherwise the prototype card.
    /// One place for this rule so the card and its tests cannot disagree.
    static func heroAspectRatio(cachedPhotoRatio: CGFloat?) -> CGFloat {
        guard let ratio = cachedPhotoRatio, ratio.isFinite, ratio > 0 else {
            return heroCardAspectRatio
        }
        return ratio
    }
}

/// Loading state for the detail hero: a soft sweep over the card, still when Reduce Motion is on.
private struct PoseHeroShimmer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                AIPoseColor.primary100
                if !reduceMotion {
                    LinearGradient(colors: [.clear, .white.opacity(0.55), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: proxy.size.width * 0.6)
                        .offset(x: sweep ? proxy.size.width : -proxy.size.width)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { sweep = true }
        }
        .accessibilityLabel("Loading pose photo")
    }
}

/// The failed-load state: the same stand-in glyph the grid uses. It is drawn as a card overlay rather
/// than from `KFImage`'s placeholder closure, because `KFImage` keeps the placeholder it was built
/// with — a load that fails after the first layout would otherwise leave the shimmer sweeping forever.
private struct PoseHeroFailureFill: View {
    var body: some View {
        ZStack {
            AIPoseColor.primary100
            Image(systemName: "figure.stand")
                .font(.system(size: 72))
                .foregroundStyle(AIPoseColor.subtext)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Pose photo unavailable")
    }
}

struct PoseDetailScreen: View {
    let pose: NativePose
    @ObservedObject var model: PosesViewModel
    var onTryPose: (NativePose) -> Void
    var isPrivate: Bool = false
    @ObservedObject private var aspectRatioCache = PoseAspectRatioCache.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var heroDidFail = false
    @State private var pendingSignIn: SignInIntent?
    /// Report §3.6 (`pose-detail.html` unavailable state): set only by the definitive
    /// `poseNotFound` signal from `PosesViewModel.confirmPublished` — a stale/deleted pose renders
    /// the shared error state instead of dead detail content.
    @State private var isUnavailable = false
    @Environment(\.dismiss) private var dismiss
    private let boundary = ServiceLocator.sessionBoundary
    init(pose: NativePose, model: PosesViewModel, onTryPose: @escaping (NativePose) -> Void, isPrivate: Bool = false) {
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
        .background(AIPoseColor.background)
        .neoHiddenNavigationBar()
        // Saving is account-scoped, so a guest is asked to sign in and the interrupted save
        // resumes once — never silently dropped, never replayed later (FEAT-013 sign-in gating).
        .signInPrompt($pendingSignIn) { intent in
            guard intent == .savePose else { return }
            Task { await toggleBookmark() }
        }
        // Shared failure surface for an action that did not stick (same pattern as Jobs actions).
        .alert(
            "Couldn't update this pose",
            isPresented: Binding(
                get: { model.bookmarkError != nil },
                set: { if !$0 { model.bookmarkError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { model.bookmarkError = nil }
        } message: {
            Text(model.bookmarkError ?? "")
        }
        .task {
            // §3.6: a detail route is only valid while the pose is still confirmed as published.
            // Private poses skip confirmPublished (D13)
            if !isPrivate {
                if !(await model.confirmPublished(pose)) { isUnavailable = true }
            }
        }
    }

    private var detailContent: some View {
        VStack(spacing: 0) {
            NeoSubscreenHeader(title: pose.name, backIdentifier: "poseDetail.back", onBack: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    poseHeroCard
                    Text(pose.name).font(.largeTitle.bold())
                    Text(pose.category).foregroundStyle(AIPoseColor.subtext)
                    ForEach(Array(pose.instructions.enumerated()), id: \.offset) { index, step in
                        Label("\(index + 1). \(step)", systemImage: "sparkles")
                    }
                    HStack(spacing: AIPoseSpacing.md) {
                        if !isPrivate && AppConfig.shared.isAccountFeatureEnabled {
                            Button { Task { await toggleBookmark() } } label: {
                                Label(isSaved ? "Saved" : "Save pose", systemImage: isSaved ? "bookmark.fill" : "bookmark")
                            }
                            .buttonStyle(NeoButtonStyle(fill: isSaved ? AIPoseColor.accentYellow : AIPoseColor.surface))
                            // No bookmark service: nothing could confirm the save, so the control is
                            // inert rather than silently lying about the pose's saved state. A pose the
                            // server answered 404 for is inert for the same reason: a retry cannot work.
                            .disabled(isSaving || model.bookmarkService == nil || !model.canSave(pose))
                            .accessibilityIdentifier("poseDetail.saveButton")
                            .accessibilityHint(bookmarkUnavailableHint)
                        }
                          Button {
                              routeTryPoseToCamera(pose, onTryPose: onTryPose)
                          } label: {
                              Label("Use this pose", systemImage: "camera")
                          }
                          .buttonStyle(NeoButtonStyle())
                          .accessibilityIdentifier("poseDetail.use")
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

    /// Hero card: the photo fills the bordered card edge to edge and the card takes the photo's own
    /// aspect ratio, so there is no letterbox inside it. The ratio comes from the grid's cache (the
    /// card the user tapped already decoded the same photo); until it is known, the prototype's
    /// `1 / 1.1` is used, with a shimmer placeholder at that size, and the card resizes once the
    /// photo loads.
    ///
    /// Client-only on purpose: a detail route opened without the cache (Jobs, saved list on a cold
    /// start) settles its ratio from the decode it was going to do anyway, so the resize and the
    /// photo's fade-in land in the same animated step — no server width/height field is worth a
    /// contract change for that.
    ///
    /// The photo is loaded with Kingfisher through `AppImage` and downsampled to the drawn width
    /// (memory + disk cache, decode off the main thread); a full-resolution decode here would stall
    /// the pushed screen for ~20-40ms on every appearance.
    private var poseHeroCard: some View {
        let shape = RoundedRectangle(cornerRadius: Self.heroCardCornerRadius)
        return Color.clear
            .frame(maxWidth: .infinity)
            .aspectRatio(heroAspectRatio, contentMode: .fit)
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
                    .placeholder { PoseHeroShimmer() }
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // Card-level, so it is painted whenever the screen re-renders (including a failure that
            // lands after the first layout) and covers the shimmer it replaces.
            .overlay {
                if heroDidFail { PoseHeroFailureFill() }
            }
            .clipShape(shape)
            .neoSurface(
                shape: shape,
                fill: AIPoseColor.surface,
                borderWidth: NeoChromeTokens.borderThick,
                shadowOffset: 0
            )
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

func routeTryPoseToCamera(_ pose: NativePose, onTryPose: (NativePose) -> Void) {
    onTryPose(pose)
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
        if AppConfig.shared.isAccountFeatureEnabled {
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
        } else {
            EmptyView()
        }
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
                title: PoseResultsStateCopy.savedSignInTitle,
                message: PoseResultsStateCopy.savedSignInMessage
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

/// Copy for the paged-list footer. Native (no prototype surface paginates), kept in one place so
/// the footer, its accessibility labels and its tests cannot disagree.
enum PagingFooterCopy {
    static let loadMore = "Load more results"
    static let retry = "Couldn't load more. Tap to retry"
    static let loading = "Loading more poses"
}

/// Footer of a paged list. Shows one of: the auto-fetch spinner, the failed-page retry, or the
/// explicit "Load more results" button once the automatic fetches are spent. Renders nothing at the
/// real end of the list, so a caller can mount it unconditionally.
struct PagingFooter: View {
    @ObservedObject var model: PosesViewModel
    /// Bottom clearance (dock overlay) when this footer is the last thing inside a scroll view.
    var bottomInset: CGFloat = PoseGridMetrics.dockClearance

    var body: some View {
        VStack(spacing: AIPoseSpacing.sm) {
            if let error = model.paging.error {
                footerButton(title: PagingFooterCopy.retry, identifier: "poses.loadMore.retry") {
                    Task { await model.loadMoreResults() }
                }
                // The failure reason (offline, timeout, 5xx) stays available without pushing the
                // retry copy itself off the button.
                .accessibilityHint(error)
            } else if model.paging.hasMore {
                if model.paging.remainingAutoFetches > 0 {
                    ProgressView()
                        .padding(.vertical, AIPoseSpacing.sm)
                        .accessibilityLabel(PagingFooterCopy.loading)
                        // Fires once per appearance, and the model ignores it while a page is in
                        // flight, so a re-render cannot stack requests.
                        .onAppear { Task { await model.loadMore() } }
                } else {
                    footerButton(title: PagingFooterCopy.loadMore, identifier: "poses.loadMore.button") {
                        Task { await model.loadMoreResults() }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, PoseGridMetrics.horizontalPadding)
        .padding(.top, AIPoseSpacing.sm)
        .padding(.bottom, bottomInset)
    }

    private func footerButton(title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AIPoseColor.foreground)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AIPoseSpacing.md)
                .frame(minHeight: PoseSurfaceMetrics.touchMinimum)
                .neoSurface(
                    shape: RoundedRectangle(cornerRadius: NeoChromeTokens.radiusMedium),
                    fill: AIPoseColor.surface,
                    borderWidth: NeoChromeTokens.borderThin,
                    shadowOffset: 0
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
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
            VStack(spacing: 0) {
                stateCard(tone: tone)
                // An empty page is not the end of the list: a search-filtered page can hold no match
                // while the server still has rows behind it.
                PagingFooter(model: model, bottomInset: 0)
            }
        } else if case .empty = model.state {
            // `emptyPresentation == .hidden` (Search): the surface draws its own no-match banner, so
            // only the pagination footer belongs here.
            PagingFooter(model: model, bottomInset: 0)
        } else if case .loaded(let poses) = model.state {
            ScrollView {
                PoseGrid(poses: poses, model: model, onTryPose: onTryPose, onNearEnd: requestNextPage)
                    .padding(.horizontal, PoseGridMetrics.horizontalPadding)
                    .padding(.top, 2)
                PagingFooter(model: model, bottomInset: bottomInset)
            }
        }
    }

    private func requestNextPage() {
        Task { await model.loadMore() }
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
