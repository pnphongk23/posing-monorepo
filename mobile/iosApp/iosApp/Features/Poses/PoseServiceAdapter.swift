import Foundation

enum PoseAdapterError: LocalizedError {
    case poseNotFound(String)
    var errorDescription: String? {
        switch self {
        case .poseNotFound(let id): return "Pose not found: \(id)"
        }
    }
}

/// Shared filter slot so `PoseAPIServiceAdapter` (PoseServing) can route per tab.
final class PoseFilterState: @unchecked Sendable {
    private let lock = NSLock()
    private var _filter: PoseLibraryFilter = .community
    /// Holds filter raw values (e.g. `All`) until `PoseLibraryFilter` gains matching cases.
    private var _pendingRawValue: String?

    var filter: PoseLibraryFilter {
        get { lock.lock(); defer { lock.unlock() }; return _filter }
        set {
            lock.lock()
            _filter = newValue
            _pendingRawValue = nil
            lock.unlock()
        }
    }

    var effectiveRawValue: String {
        lock.lock()
        defer { lock.unlock() }
        return _pendingRawValue ?? _filter.rawValue
    }

    #if DEBUG
    func setFilterRawValueForTesting(_ rawValue: String) {
        lock.lock()
        if let parsed = PoseLibraryFilter(rawValue: rawValue) {
            _filter = parsed
            _pendingRawValue = nil
        } else {
            _pendingRawValue = rawValue
        }
        lock.unlock()
    }
    #endif
}

enum PoseAdapterRoute: String {
    case all = "All poses"
    case saved = "My poses"
    case community = "Community"

    static func from(rawValue: String) -> PoseAdapterRoute {
        if rawValue == "All" || rawValue == PoseLibraryFilter.all.rawValue {
            return .all
        }
        return PoseAdapterRoute(rawValue: rawValue) ?? .community
    }
}

enum PoseAdapterMerge {
    /// Community results first; saved items follow when their id is not already present.
    static func communityFirst(community: [NativePose], saved: [NativePose]) -> [NativePose] {
        let communityIDs = Set(community.map(\.id))
        return community + saved.filter { !communityIDs.contains($0.id) }
    }

    static func filterSavedLocally(_ poses: [NativePose], query: String?) -> [NativePose] {
        guard let query, !query.isEmpty else { return poses }
        return poses.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
}

enum CommunityPoseMapper {
    static func map(_ pose: CommunityPose, isSaved: Bool, baseURL: String) -> NativePose {
        let instructions: [String] = {
            if let description = pose.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                return [description]
            }
            return pose.bodyParts
        }()
        return NativePose(
            id: pose.poseId,
            name: pose.name,
            category: pose.difficulty ?? pose.tags.first ?? "Community",
            imageURL: resolveURL(pose.thumbnailUrl, baseURL: baseURL),
            instructions: instructions,
            isSaved: isSaved
        )
    }

    static func resolveURL(_ path: String, baseURL: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        }
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let relative = trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
        return URL(string: base + relative)
    }
}

// MARK: - Offline pose catalog (cache-first)

/// Which feed a catalog row was observed in. Combined with `PoseRecord.status` (the saved flag)
/// this reproduces the live adapter's three routes exactly, `communityFirst` dedupe included.
enum PoseCatalogSource: Sendable {
    case community
    case saved
}

/// One row to persist, tagged with the feed it came from so the cache can merge it with what the
/// database already knows (a community page must not erase a saved flag, and vice versa).
struct PoseCatalogWrite: Sendable {
    var record: PoseRecord
    var source: PoseCatalogSource
}

/// One fetched page: what the UI should show plus what the cache should persist.
struct PoseCatalogFetch: Sendable {
    var poses: [NativePose]
    var writes: [PoseCatalogWrite]
    /// A query-less community page is the whole page, so it may prune the community bucket.
    /// A search page is server-filtered and therefore only merges into the catalog.
    var replacesCommunityBucket: Bool
    /// The saved endpoint always returns the full saved list (the search text is applied locally).
    var replacesSavedBucket: Bool
}

/// `NativePose` ⇄ `PoseRecord` for the offline catalog.
///
/// Cache bookkeeping inside the shared `Pose` table (no schema change/migration is allowed):
/// - `ownerAccountId` holds `PoseCatalogBucket` (which feed observed the row);
/// - `status` doubles as the "saved by me" flag (`local`) for cache-owned rows;
/// - only *relative* media paths are stored — `thumbnailPath`/`skeletonPath` are re-resolved
///   against the current `baseURL` on read, so an endpoint switch cannot serve stale absolute URLs.
///
/// Rows whose `ownerAccountId` is not a `PoseCatalogBucket` raw value (legacy local poses) are
/// ignored by every catalog read and are never pruned or rewritten.
enum PoseCatalogMapping {
    static let savedStatus = "local"
    static let unsavedStatus = "published"

    static func record(from pose: CommunityPose, source: PoseCatalogSource, baseURL: String) -> PoseRecord {
        let timestamp = pose.uploadedAt ?? ""
        return PoseRecord(
            poseId: pose.poseId,
            ownerAccountId: bucket(for: source).rawValue,
            name: pose.name,
            description: pose.description,
            tags: jsonString(pose.tags),
            difficulty: pose.difficulty,
            bodyParts: jsonString(pose.bodyParts),
            status: source == .saved ? savedStatus : unsavedStatus,
            originalPath: "",
            skeletonPath: relativePath(pose.skeletonUrl, baseURL: baseURL),
            thumbnailPath: relativePath(pose.thumbnailUrl, baseURL: baseURL),
            currentJobId: nil,
            createdAt: timestamp,
            updatedAt: timestamp
        )
    }

    static func bucket(for source: PoseCatalogSource) -> PoseCatalogBucket {
        source == .saved ? .saved : .community
    }

    /// Inverse of `CommunityPoseMapper.map`, so an offline read yields the same `NativePose` the
    /// live response produced. `isSaved` stays route-owned: the community route never shows a badge.
    static func nativePose(from record: PoseRecord, isSaved: Bool, baseURL: String) -> NativePose {
        let tags = strings(fromJSON: record.tags)
        let bodyParts = strings(fromJSON: record.bodyParts)
        let instructions: [String] = {
            if let description = record.description?.trimmingCharacters(in: .whitespacesAndNewlines),
               !description.isEmpty {
                return [description]
            }
            return bodyParts
        }()
        return NativePose(
            id: record.poseId,
            name: record.name,
            category: record.difficulty ?? tags.first ?? "Community",
            imageURL: CommunityPoseMapper.resolveURL(record.thumbnailPath, baseURL: baseURL),
            instructions: instructions,
            isSaved: isSaved
        )
    }

    /// Drops the current base URL prefix so only the server-relative path is persisted.
    static func relativePath(_ path: String, baseURL: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        if !base.isEmpty, trimmed.hasPrefix(base + "/") {
            return String(trimmed.dropFirst(base.count))
        }
        return trimmed
    }

    private static func jsonString(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values),
              let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }

    private static func strings(fromJSON text: String) -> [String] {
        guard let data = text.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return values
    }
}

/// Identity of one cached answer: route (All / My poses / Community) + normalized search text.
struct PoseCacheKey: Hashable, Sendable {
    let route: PoseAdapterRoute
    let query: String?

    static func normalizedQuery(_ query: String?) -> String? {
        guard let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

enum PoseCachePolicy {
    /// A freshly fetched answer is served from memory without touching the network for this long.
    static let freshnessWindow: TimeInterval = 300
}

/// Runs stale-while-revalidate work. Production detaches it; tests drive it by hand.
protocol PoseRefreshScheduling: Sendable {
    func schedule(_ operation: @escaping @Sendable () async -> Void)
}

struct DetachedPoseRefreshScheduler: PoseRefreshScheduling {
    func schedule(_ operation: @escaping @Sendable () async -> Void) {
        Task.detached(priority: .utility) { await operation() }
    }
}

/// Lazily opened shared catalog database. A `static let` is resolved on first access — i.e. on the
/// first cache read, which is already off the main thread — so app launch does not open the pool
/// twice (the gallery bootstrap opens it eagerly) and cannot fail a migration race.
enum PoseCatalogDatabase {
    static let shared: AppDatabase? = try? AppDatabase()

    static var repository: PoseRepository? {
        shared.map { PoseRepository(database: $0) }
    }
}

/// Cache-first pose source: memory → database → network (awaited only on a cold miss).
///
/// 1. **memory** — same route + query inside a session: no I/O while the entry is fresh;
/// 2. **database** — app relaunch / new service instance: answers immediately and revalidates in
///    the background, so an offline launch still shows the catalog instead of `.failed`;
/// 3. **network** — only when nothing is cached; its error propagates (the view offers retry).
///
/// Writes always land in the database (source of truth) and refresh the memory entry.
final class PoseCatalogCacheStore: @unchecked Sendable {
    private struct Entry {
        var poses: [NativePose]
        var refreshedAt: Date
    }

    private let lock = NSLock()
    private var memory: [PoseCacheKey: Entry] = [:]
    private var inFlight: Set<PoseCacheKey> = []
    /// Bumped when a bookmark change touches a key, so a slower revalidation cannot resurrect
    /// pre-change data (e.g. re-marking an unsaved pose as saved).
    private var generations: [PoseCacheKey: UInt64] = [:]
    private let repositoryProvider: @Sendable () -> PoseRepository?
    private let freshnessWindow: TimeInterval
    private let now: @Sendable () -> Date
    private let scheduler: any PoseRefreshScheduling

    init(
        repositoryProvider: @escaping @Sendable () -> PoseRepository?,
        freshnessWindow: TimeInterval = PoseCachePolicy.freshnessWindow,
        scheduler: any PoseRefreshScheduling = DetachedPoseRefreshScheduler(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.repositoryProvider = repositoryProvider
        self.freshnessWindow = freshnessWindow
        self.scheduler = scheduler
        self.now = now
    }

    convenience init(
        repository: PoseRepository?,
        freshnessWindow: TimeInterval = PoseCachePolicy.freshnessWindow,
        scheduler: any PoseRefreshScheduling = DetachedPoseRefreshScheduler(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.init(
            repositoryProvider: { repository },
            freshnessWindow: freshnessWindow,
            scheduler: scheduler,
            now: now
        )
    }

    /// App wiring: the shared `AppDatabase` catalog, detached revalidation, wall-clock freshness.
    ///
    /// Deliberately one instance for the process: it is the account-scoped cache that
    /// sign-out/account-switch cleanup must reach (`SessionScopeCoordinator`), and the app builds
    /// a new `PoseServiceBundle` whenever the endpoint is resolved, so per-bundle caches would let
    /// a stale Account's rows survive in an unreachable instance.
    static let shared = PoseCatalogCacheStore(repositoryProvider: { PoseCatalogDatabase.repository })

    static func makeDefault() -> PoseCatalogCacheStore {
        shared
    }

    func poses(
        for key: PoseCacheKey,
        baseURL: String,
        load: @escaping @Sendable () async throws -> PoseCatalogFetch
    ) async throws -> [NativePose] {
        if let hit = memoryEntry(for: key) {
            if !isStale(hit) { return hit.poses }
            scheduleRefresh(for: key, baseURL: baseURL, load: load)
            return hit.poses
        }

        if let offline = await databasePoses(for: key, baseURL: baseURL) {
            store(memoryEntry: Entry(poses: offline, refreshedAt: .distantPast), for: key)
            scheduleRefresh(for: key, baseURL: baseURL, load: load)
            return offline
        }

        let fetch = try await load()
        await persist(fetch)
        store(memoryEntry: Entry(poses: fetch.poses, refreshedAt: now()), for: key)
        return fetch.poses
    }

    /// Save/unsave: the database row changes and every saved-sensitive memory entry is dropped, so
    /// the next read rebuilds from the database (single source of truth) instead of showing a stale
    /// bookmark flag.
    func handleBookmarkChange(poseId: String, isSaved: Bool) async {
        invalidateSavedSensitiveEntries()

        guard let repository = repositoryProvider(),
              let record = try? await repository.pose(id: poseId),
              PoseCatalogBucket(rawValue: record.ownerAccountId) != nil else { return }

        if isSaved {
            var updated = record
            updated.status = PoseCatalogMapping.savedStatus
            try? await repository.upsert([updated])
        } else if record.ownerAccountId == PoseCatalogBucket.saved.rawValue {
            // Saved-only row: no feed references it any more.
            try? await repository.delete(ids: [poseId])
        } else {
            var updated = record
            updated.status = PoseCatalogMapping.unsavedStatus
            try? await repository.upsert([updated])
        }
    }

    // MARK: memory

    private func memoryEntry(for key: PoseCacheKey) -> Entry? {
        lock.withLocked { memory[key] }
    }

    private func isStale(_ entry: Entry) -> Bool {
        now().timeIntervalSince(entry.refreshedAt) >= freshnessWindow
    }

    private func store(memoryEntry: Entry, for key: PoseCacheKey) {
        lock.withLocked { memory[key] = memoryEntry }
    }

    private func generation(of key: PoseCacheKey) -> UInt64 {
        lock.withLocked { generations[key] ?? 0 }
    }

    private func invalidateSavedSensitiveEntries() {
        lock.withLocked {
            for key in Array(memory.keys) where key.route != .community {
                memory.removeValue(forKey: key)
                generations[key, default: 0] += 1
            }
        }
    }

    // MARK: database

    /// Offline answer for `key`, or `nil` when the catalog holds nothing for this route (which
    /// falls through to the network so an error can still surface as `.failed`).
    private func databasePoses(for key: PoseCacheKey, baseURL: String) async -> [NativePose]? {
        guard let repository = repositoryProvider() else { return nil }
        guard let rows = try? await repository.cached() else { return nil }

        let communityRows = rows.filter { $0.ownerAccountId == PoseCatalogBucket.community.rawValue }
        let savedRows = rows.filter { $0.status == PoseCatalogMapping.savedStatus }

        switch key.route {
        case .community:
            guard !communityRows.isEmpty else { return nil }
            let poses = communityRows.map {
                PoseCatalogMapping.nativePose(from: $0, isSaved: false, baseURL: baseURL)
            }
            let filtered = PoseAdapterMerge.filterSavedLocally(poses, query: key.query)
            // The server owns community search matching, so a local name filter that matches nothing
            // is not an answer: fall through to the network (which reports the offline failure)
            // instead of claiming "no poses found".
            if key.query != nil, filtered.isEmpty { return nil }
            return filtered
        case .saved:
            guard !savedRows.isEmpty else { return nil }
            let poses = savedRows.map {
                PoseCatalogMapping.nativePose(from: $0, isSaved: true, baseURL: baseURL)
            }
            return PoseAdapterMerge.filterSavedLocally(poses, query: key.query)
        case .all:
            guard !communityRows.isEmpty || !savedRows.isEmpty else { return nil }
            let community = PoseAdapterMerge.filterSavedLocally(
                communityRows.map { PoseCatalogMapping.nativePose(from: $0, isSaved: false, baseURL: baseURL) },
                query: key.query
            )
            let savedOnly = savedRows
                .filter { $0.ownerAccountId != PoseCatalogBucket.community.rawValue }
                .map { PoseCatalogMapping.nativePose(from: $0, isSaved: true, baseURL: baseURL) }
            return PoseAdapterMerge.communityFirst(
                community: community,
                saved: PoseAdapterMerge.filterSavedLocally(savedOnly, query: key.query)
            )
        }
    }

    /// Merges one fetched page into the catalog. Bucket and saved flag come from the *combination*
    /// of what the feed reported and what the database already knew:
    /// - a community page never clears an existing saved flag;
    /// - a saved page keeps a row in the community bucket when it was already there;
    /// - a replaced bucket prunes rows the fresh page no longer contains, demoting still-saved rows
    ///   to the `saved` bucket instead of deleting them.
    private func persist(_ fetch: PoseCatalogFetch) async {
        guard let repository = repositoryProvider() else { return }
        let existing = (try? await repository.cached()) ?? []
        let existingByID = Dictionary(existing.map { ($0.poseId, $0) }, uniquingKeysWith: { first, _ in first })
        let fetchedIDs = Set(fetch.writes.map(\.record.poseId))

        var upserts: [PoseRecord] = []
        var deletions: [String] = []

        for write in fetch.writes {
            var record = write.record
            if let current = existingByID[record.poseId] {
                if record.createdAt.isEmpty { record.createdAt = current.createdAt }
                if record.updatedAt.isEmpty { record.updatedAt = current.updatedAt }
                switch write.source {
                case .community:
                    if current.status == PoseCatalogMapping.savedStatus {
                        record.status = PoseCatalogMapping.savedStatus
                    }
                case .saved:
                    record.ownerAccountId = current.ownerAccountId == PoseCatalogBucket.community.rawValue
                        ? PoseCatalogBucket.community.rawValue
                        : PoseCatalogBucket.saved.rawValue
                    record.status = PoseCatalogMapping.savedStatus
                }
            }
            upserts.append(record)
        }

        for row in existing where !fetchedIDs.contains(row.poseId) {
            var updated = row
            var removed = false
            if fetch.replacesCommunityBucket, row.ownerAccountId == PoseCatalogBucket.community.rawValue {
                if row.status == PoseCatalogMapping.savedStatus {
                    updated.ownerAccountId = PoseCatalogBucket.saved.rawValue
                } else {
                    removed = true
                }
            }
            if fetch.replacesSavedBucket, updated.status == PoseCatalogMapping.savedStatus {
                updated.status = PoseCatalogMapping.unsavedStatus
                if updated.ownerAccountId == PoseCatalogBucket.saved.rawValue { removed = true }
            }
            if removed {
                deletions.append(row.poseId)
            } else {
                upserts.append(updated)
            }
        }

        try? await repository.upsert(upserts)
        try? await repository.delete(ids: deletions)
    }

    /// Drops every account-scoped row from the catalog.
    ///
    /// Called on a session change (sign-in, sign-out, or a 401 clear): the Saved collection belongs
    /// to one Account, so keeping it would let Account A's rows answer Account B's or a guest's
    /// read (`FEAT-014` FR-005). Saved-only rows are deleted; rows that also came from the
    /// community feed keep their community bucket with the saved flag demoted.
    func clearSavedState() async {
        invalidateSavedSensitiveEntries()
        guard let repository = repositoryProvider(),
              let rows = try? await repository.cached() else { return }

        var upserts: [PoseRecord] = []
        var deletions: [String] = []
        for row in rows where row.status == PoseCatalogMapping.savedStatus {
            if row.ownerAccountId == PoseCatalogBucket.saved.rawValue {
                deletions.append(row.poseId)
            } else {
                var updated = row
                updated.status = PoseCatalogMapping.unsavedStatus
                upserts.append(updated)
            }
        }
        try? await repository.upsert(upserts)
        try? await repository.delete(ids: deletions)
    }

    // MARK: stale-while-revalidate

    private func scheduleRefresh(
        for key: PoseCacheKey,
        baseURL: String,
        load: @escaping @Sendable () async throws -> PoseCatalogFetch
    ) {
        let generation = generation(of: key)
        let inserted = lock.withLocked { inFlight.insert(key).inserted }
        guard inserted else { return }
        scheduler.schedule { [weak self] in
            guard let self else { return }
            let fetch = try? await load()
            defer { self.lock.withLocked { _ = self.inFlight.remove(key) } }
            guard let fetch, self.generation(of: key) == generation else { return }
            await self.persist(fetch)
            self.store(memoryEntry: Entry(poses: fetch.poses, refreshedAt: self.now()), for: key)
        }
    }
}

/// Decorates the live bookmark service so a save/unsave is reflected by the offline catalog before
/// the next read (`PosesViewModel` reloads right after toggling).
struct PoseCachingBookmarkService: PoseBookmarkServing {
    let base: any PoseBookmarkServing
    let cache: PoseCatalogCacheStore?

    init(base: any PoseBookmarkServing, cache: PoseCatalogCacheStore?) {
        self.base = base
        self.cache = cache
    }

    func savePose(poseId: String) async throws {
        try await base.savePose(poseId: poseId)
        await cache?.handleBookmarkChange(poseId: poseId, isSaved: true)
    }

    func unsavePose(poseId: String) async throws {
        try await base.unsavePose(poseId: poseId)
        await cache?.handleBookmarkChange(poseId: poseId, isSaved: false)
    }
}

private extension NSLock {
    /// `NSLock.withLock` is iOS 16+; the app targets iOS 15.
    func withLocked<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

protocol PoseRemoteFetching: Sendable {
    func fetchCommunity(page: Int, limit: Int, query: String?) async throws -> [CommunityPose]
    func fetchSaved(page: Int, limit: Int) async throws -> [CommunityPose]
}

extension PoseAPIService: PoseRemoteFetching {
    func fetchCommunity(page: Int, limit: Int, query: String?) async throws -> [CommunityPose] {
        try await getCommunityPoses(page: page, limit: limit, q: query).data
    }

    func fetchSaved(page: Int, limit: Int) async throws -> [CommunityPose] {
        try await getSavedPoses(page: page, limit: limit).data
    }
}

struct PoseAPIServiceAdapter: PoseServing {
    let remote: any PoseRemoteFetching
    let baseURL: String
    let filterState: PoseFilterState
    var pageSize: Int = 20
    /// Offline catalog. `nil` keeps the adapter network-only, which is what callers without a
    /// database (unit tests that only exercise routing) still get.
    var cache: PoseCatalogCacheStore?
    /// Session probe that stops the catalog from answering the account-scoped routes while no
    /// session exists. The composition root injects the real `SessionBoundary` check; the default
    /// keeps direct constructions (routing/paging tests) cache-only and session-agnostic.
    var hasSession: @Sendable () async -> Bool = { true }

    init(
        api: PoseAPIService,
        baseURL: String,
        filterState: PoseFilterState,
        pageSize: Int = 20,
        cache: PoseCatalogCacheStore? = nil,
        hasSession: @escaping @Sendable () async -> Bool = { true }
    ) {
        self.remote = api
        self.baseURL = baseURL
        self.filterState = filterState
        self.pageSize = pageSize
        self.cache = cache
        self.hasSession = hasSession
    }

    init(
        remote: any PoseRemoteFetching,
        baseURL: String,
        filterState: PoseFilterState,
        pageSize: Int = 20,
        cache: PoseCatalogCacheStore? = nil,
        hasSession: @escaping @Sendable () async -> Bool = { true }
    ) {
        self.remote = remote
        self.baseURL = baseURL
        self.filterState = filterState
        self.pageSize = pageSize
        self.cache = cache
        self.hasSession = hasSession
    }

    /// Cache-first: with a catalog attached, a read answers from memory/database and only awaits the
    /// network when nothing is cached (see `PoseCatalogCacheStore.poses`).
    func poses(query: String?) async throws -> [NativePose] {
        let route = PoseAdapterRoute.from(rawValue: filterState.effectiveRawValue)
        let normalizedQuery = PoseCacheKey.normalizedQuery(query)
        guard let cache, await cacheIsUsable(for: route) else {
            return try await remoteFetch(route: route, query: normalizedQuery).poses
        }
        let key = PoseCacheKey(route: route, query: normalizedQuery)
        return try await cache.poses(for: key, baseURL: baseURL) {
            try await self.remoteFetch(route: route, query: normalizedQuery)
        }
    }

    /// `.saved` and `.all` both carry saved rows, so they are account-scoped; only the community
    /// feed may be answered from the offline catalog without a session.
    private func cacheIsUsable(for route: PoseAdapterRoute) async -> Bool {
        if route == .community { return true }
        return await hasSession()
    }

    /// Untouched network path plus the catalog rows that mirror it.
    private func remoteFetch(route: PoseAdapterRoute, query: String?) async throws -> PoseCatalogFetch {
        switch route {
        case .community:
            let data = try await remote.fetchCommunity(page: 1, limit: pageSize, query: query)
            return PoseCatalogFetch(
                poses: data.map { CommunityPoseMapper.map($0, isSaved: false, baseURL: baseURL) },
                writes: data.map { write($0, source: .community) },
                replacesCommunityBucket: query == nil,
                replacesSavedBucket: false
            )
        case .saved:
            let data = try await remote.fetchSaved(page: 1, limit: pageSize)
            let poses = data.map { CommunityPoseMapper.map($0, isSaved: true, baseURL: baseURL) }
            return PoseCatalogFetch(
                poses: PoseAdapterMerge.filterSavedLocally(poses, query: query),
                writes: data.map { write($0, source: .saved) },
                replacesCommunityBucket: false,
                replacesSavedBucket: true
            )
        case .all:
            let communityData = try await remote.fetchCommunity(page: 1, limit: pageSize, query: query)
            let savedData = (try? await remote.fetchSaved(page: 1, limit: pageSize)) ?? []
            let community = communityData.map { CommunityPoseMapper.map($0, isSaved: false, baseURL: baseURL) }
            let saved = PoseAdapterMerge.filterSavedLocally(
                savedData.map { CommunityPoseMapper.map($0, isSaved: true, baseURL: baseURL) },
                query: query
            )
            return PoseCatalogFetch(
                poses: PoseAdapterMerge.communityFirst(community: community, saved: saved),
                writes: communityData.map { write($0, source: .community) }
                    + savedData.map { write($0, source: .saved) },
                replacesCommunityBucket: query == nil,
                replacesSavedBucket: true
            )
        }
    }

    private func write(_ pose: CommunityPose, source: PoseCatalogSource) -> PoseCatalogWrite {
        PoseCatalogWrite(
            record: PoseCatalogMapping.record(from: pose, source: source, baseURL: baseURL),
            source: source
        )
    }

    func pose(id: String) async throws -> NativePose {
        if let match = try await poses(query: nil).first(where: { $0.id == id }) {
            return match
        }
        let community = try await remote.fetchCommunity(page: 1, limit: pageSize, query: nil)
        if let match = community.first(where: { $0.poseId == id }) {
            return CommunityPoseMapper.map(match, isSaved: false, baseURL: baseURL)
        }
        let saved = try await remote.fetchSaved(page: 1, limit: pageSize)
        if let match = saved.first(where: { $0.poseId == id }) {
            return CommunityPoseMapper.map(match, isSaved: true, baseURL: baseURL)
        }
        throw PoseAdapterError.poseNotFound(id)
    }
}

struct PoseServiceBundle: Sendable {
    let service: PoseAPIServiceAdapter
    let filterState: PoseFilterState
    /// Cached-aware bookmark service (`PoseCachingBookmarkService`), so a save/unsave updates the
    /// offline catalog; kept as an existential to avoid leaking the decorator to callers.
    let bookmarkService: any PoseBookmarkServing
}

enum PoseServiceBootstrap {
    static func make(
        api: PoseAPIService = ServiceLocator.makePoseAPIService(),
        baseURL: String = AppConfig.shared.SERVER_BASE_URL
    ) -> PoseServiceBundle {
        let filterState = PoseFilterState()
        let cache = PoseCatalogCacheStore.makeDefault()
        let service = PoseAPIServiceAdapter(
            api: api,
            baseURL: baseURL,
            filterState: filterState,
            cache: cache,
            hasSession: { await ServiceLocator.sessionBoundary.hasStoredSession() }
        )
        return PoseServiceBundle(
            service: service,
            filterState: filterState,
            bookmarkService: PoseCachingBookmarkService(
                base: PoseAPIBookmarkService(api: api),
                cache: cache
            )
        )
    }
}
