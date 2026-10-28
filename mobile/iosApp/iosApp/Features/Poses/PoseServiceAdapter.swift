import Foundation
import GRDB

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
            isSaved: isSaved,
            guideURL: resolveURL(pose.skeletonUrl, baseURL: baseURL)
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

enum GuidePoseMapper {
    static func map(_ guide: GuidePose, baseURL: String) -> NativePose {
        let instructions: [String] = {
            if let description = guide.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                return description
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
            return []
        }()
        return NativePose(
            id: guide.poseId,
            name: guide.name,
            category: guide.tags.first ?? "",
            imageURL: guide.originalUrl.flatMap { CommunityPoseMapper.resolveURL($0, baseURL: baseURL) }
                ?? CommunityPoseMapper.resolveURL(guide.skeletonUrl, baseURL: baseURL),
            instructions: instructions,
            isSaved: false,
            guideURL: CommunityPoseMapper.resolveURL(guide.skeletonUrl, baseURL: baseURL)
        )
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
            isSaved: isSaved,
            guideURL: CommunityPoseMapper.resolveURL(record.skeletonPath, baseURL: baseURL)
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

/// What one account-scoped write must do: the rows to store and the ids to drop.
///
/// Pure on purpose: the merge rules are the interesting part, and the caller runs the result inside
/// a single GRDB write transaction so the session-epoch check and the rows it guards commit (or are
/// skipped) together.
enum PoseCatalogWritePlan {
    static func merge(
        fetch: PoseCatalogFetch,
        existing: [PoseRecord]
    ) -> (upserts: [PoseRecord], deletions: [String]) {
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

        return (upserts, deletions)
    }

    /// Clear: saved-only rows go, rows that also came from the community feed keep their feed entry
    /// with the saved flag demoted.
    static func reset(existing: [PoseRecord]) -> (upserts: [PoseRecord], deletions: [String]) {
        var upserts: [PoseRecord] = []
        var deletions: [String] = []
        for row in existing where row.status == PoseCatalogMapping.savedStatus {
            if row.ownerAccountId == PoseCatalogBucket.saved.rawValue {
                deletions.append(row.poseId)
            } else {
                var updated = row
                updated.status = PoseCatalogMapping.unsavedStatus
                upserts.append(updated)
            }
        }
        return (upserts, deletions)
    }

    /// Executes a plan in one statement at a time. Shared by the cache's own writes so the epoch
    /// check, the upserts and the deletions stay inside one transaction.
    static func apply(_ plan: (upserts: [PoseRecord], deletions: [String]), in db: Database) throws {
        for record in plan.upserts { try record.save(db) }
        guard !plan.deletions.isEmpty else { return }
        let placeholders = Array(repeating: "?", count: plan.deletions.count).joined(separator: ",")
        try db.execute(
            sql: "DELETE FROM Pose WHERE poseId IN (\(placeholders))",
            arguments: StatementArguments(plan.deletions)
        )
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
    /// Bumped by every account-scoped reset (`clearSavedState`).
    ///
    /// A Saved load that is still in flight when the session changes would otherwise write the
    /// previous Account's rows back *after* the clear, so every account-scoped write re-checks this
    /// value **inside** its GRDB write transaction. That is what makes it correct without a lock
    /// around the network: GRDB serializes writers, so a stale write either committed before the
    /// clear (which then removes its rows) or runs after it and is skipped.
    private var sessionEpoch: UInt64 = 0
    #if DEBUG
    /// Test seam: runs immediately before an account-scoped write is queued, so a test can land a
    /// session change in the window between "fetch returned" and "rows committed".
    private var beforeAccountScopedWrite: (@Sendable () async -> Void)?
    #endif
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
        // Captured before anything is awaited: the epoch belongs to the moment this answer was
        // requested, so a revalidation queued here can never commit after the session that asked
        // for it has been dropped.
        let epoch = beginAccountScopedOperation()

        if let hit = memoryEntry(for: key) {
            if !isStale(hit) { return hit.poses }
            scheduleRefresh(for: key, baseURL: baseURL, epoch: epoch, load: load)
            return hit.poses
        }

        if let offline = await databasePoses(for: key, baseURL: baseURL) {
            store(memoryEntry: Entry(poses: offline, refreshedAt: .distantPast), for: key)
            scheduleRefresh(for: key, baseURL: baseURL, epoch: epoch, load: load)
            return offline
        }

        let fetch = try await load()
        // The answer is returned either way (the request already happened), but a stale session's
        // rows are neither committed nor kept where the next Account would read them.
        if await persist(fetch, epoch: epoch) {
            store(memoryEntry: Entry(poses: fetch.poses, refreshedAt: now()), for: key)
        }
        return fetch.poses
    }

    // MARK: session epoch

    /// The epoch a new account-scoped operation starts under. Callers that begin a network request
    /// capture this **before** awaiting it (see `PoseCachingBookmarkService`).
    func beginAccountScopedOperation() -> UInt64 {
        lock.withLocked { sessionEpoch }
    }

    #if DEBUG
    func setBeforeAccountScopedWriteForTesting(_ hook: (@Sendable () async -> Void)?) {
        lock.withLocked { beforeAccountScopedWrite = hook }
    }

    private func accountScopedWriteHook() -> (@Sendable () async -> Void)? {
        lock.withLocked { beforeAccountScopedWrite }
    }
    #endif

    private func isSessionEpochCurrent(_ epoch: UInt64) -> Bool {
        lock.withLocked { sessionEpoch == epoch }
    }

    private func bumpSessionEpoch() {
        lock.withLocked { sessionEpoch &+= 1 }
    }

    /// Community-only writes carry nothing that belongs to an Account, so a session change does not
    /// invalidate them and the epoch check is skipped.
    private func isAccountScoped(_ fetch: PoseCatalogFetch) -> Bool {
        fetch.replacesSavedBucket || fetch.writes.contains { $0.source == .saved }
    }

    /// Save/unsave: the database row changes and every saved-sensitive memory entry is dropped, so
    /// the next read rebuilds from the database (single source of truth) instead of showing a stale
    /// bookmark flag.
    ///
    /// `epoch` is the one captured **before** the bookmark request was sent, so a save that was in
    /// flight across an account switch cannot mark the previous Account's row as saved for the next
    /// one.
    func handleBookmarkChange(poseId: String, isSaved: Bool, epoch: UInt64? = nil) async {
        invalidateSavedSensitiveEntries()

        guard let repository = repositoryProvider() else { return }
        let capturedEpoch = epoch ?? beginAccountScopedOperation()
        do {
            try await repository.database.pool.write { db in
                guard self.isSessionEpochCurrent(capturedEpoch) else { return }
                guard let record = try PoseRecord.fetchOne(db, key: poseId),
                      PoseCatalogBucket(rawValue: record.ownerAccountId) != nil else { return }

                if isSaved {
                    var updated = record
                    updated.status = PoseCatalogMapping.savedStatus
                    try updated.save(db)
                } else if record.ownerAccountId == PoseCatalogBucket.saved.rawValue {
                    // Saved-only row: no feed references it any more.
                    try db.execute(sql: "DELETE FROM Pose WHERE poseId = ?", arguments: [poseId])
                } else {
                    var updated = record
                    updated.status = PoseCatalogMapping.unsavedStatus
                    try updated.save(db)
                }
            }
        } catch {
            // Best effort: the catalog is a cache, so a failed write is healed by the next read.
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
    ///
    /// The read, the merge and the commit happen inside one GRDB write transaction, together with
    /// the session-epoch check: a fetch that crossed an account switch commits nothing.
    private func persist(_ fetch: PoseCatalogFetch, epoch: UInt64) async -> Bool {
        guard let repository = repositoryProvider() else { return false }
        let accountScoped = isAccountScoped(fetch)

        #if DEBUG
        if let hook = accountScopedWriteHook() { await hook() }
        #endif

        do {
            return try await repository.database.pool.write { db -> Bool in
                // GRDB serializes writers, so this either commits before the reset (which then
                // removes its rows) or is skipped here — never commits on the far side of it.
                guard !accountScoped || self.isSessionEpochCurrent(epoch) else { return false }
                let existing = try PoseCatalogCacheStore.cachedRows(in: db)
                try PoseCatalogWritePlan.apply(PoseCatalogWritePlan.merge(fetch: fetch, existing: existing), in: db)
                return true
            }
        } catch {
            return false
        }
    }

    /// Drops every account-scoped row from the catalog.
    ///
    /// Called on a session change (sign-in, sign-out, or a 401 clear): the Saved collection belongs
    /// to one Account, so keeping it would let Account A's rows answer Account B's or a guest's
    /// read (`FEAT-014` FR-005). Saved-only rows are deleted; rows that also came from the
    /// community feed keep their community bucket with the saved flag demoted.
    ///
    /// The epoch is bumped **before** this clear is queued, so every account-scoped write that is
    /// still in flight fails its check instead of repopulating the rows this call is removing.
    func clearSavedState() async {
        invalidateSavedSensitiveEntries()
        bumpSessionEpoch()
        guard let repository = repositoryProvider() else { return }
        do {
            try await repository.database.pool.write { db in
                let existing = try PoseCatalogCacheStore.cachedRows(in: db)
                try PoseCatalogWritePlan.apply(PoseCatalogWritePlan.reset(existing: existing), in: db)
            }
        } catch {
            // Best effort: a failed clear is healed by the next session change.
        }
    }

    /// Rows the pose cache owns (`PoseCatalogBucket` marker present). Read inside the same write
    /// transaction as the rows it is merged with, so the plan cannot be built from a stale snapshot.
    static func cachedRows(in db: Database) throws -> [PoseRecord] {
        try PoseRecord.fetchAll(
            db,
            sql: "SELECT * FROM Pose WHERE ownerAccountId IN (?, ?)",
            arguments: [PoseCatalogBucket.community.rawValue, PoseCatalogBucket.saved.rawValue]
        )
    }

    // MARK: stale-while-revalidate

    private func scheduleRefresh(
        for key: PoseCacheKey,
        baseURL: String,
        epoch: UInt64,
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
            guard await self.persist(fetch, epoch: epoch) else { return }
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
        // Captured before the request is sent: a save whose response lands after a session change
        // belongs to the previous Account and must not be written into the catalog.
        let epoch = cache?.beginAccountScopedOperation()
        try await base.savePose(poseId: poseId)
        await cache?.handleBookmarkChange(poseId: poseId, isSaved: true, epoch: epoch)
    }

    func unsavePose(poseId: String) async throws {
        let epoch = cache?.beginAccountScopedOperation()
        try await base.unsavePose(poseId: poseId)
        await cache?.handleBookmarkChange(poseId: poseId, isSaved: false, epoch: epoch)
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

/// One network page plus the server's total for the whole (filtered) collection.
///
/// The total is what makes `hasMore` correct: `count == limit` is a full page, not necessarily the
/// last one, so paging on the item count alone either drops rows or offers a page that cannot exist.
struct PoseRemotePage: Sendable {
    let poses: [CommunityPose]
    let total: Int

    static let empty = PoseRemotePage(poses: [], total: 0)
}

protocol PoseRemoteFetching: Sendable {
    func fetchCommunity(page: Int, limit: Int, query: String?) async throws -> PoseRemotePage
    func fetchSaved(page: Int, limit: Int) async throws -> PoseRemotePage
}

extension PoseAPIService: PoseRemoteFetching {
    func fetchCommunity(page: Int, limit: Int, query: String?) async throws -> PoseRemotePage {
        let result = try await getCommunityPoses(page: page, limit: limit, q: query)
        return PoseRemotePage(poses: result.data, total: result.pagination.total)
    }

    func fetchSaved(page: Int, limit: Int) async throws -> PoseRemotePage {
        let result = try await getSavedPoses(page: page, limit: limit)
        return PoseRemotePage(poses: result.data, total: result.pagination.total)
    }
}

/// Carries the network's `hasMore` back out of the cache's `load` closure, which may run after the
/// call returned (stale-while-revalidate). A missing value means this call was answered from cache.
private final class PosePageLimitProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var storedHasMore: Bool?
    private var storedConsumed: Int?

    var hasMore: Bool? {
        lock.withLocked { storedHasMore }
    }

    /// Rows the server handed over for the first window, before any local filter or merge.
    var consumed: Int? {
        lock.withLocked { storedConsumed }
    }

    func record(_ value: Bool) {
        lock.withLocked { storedHasMore = value }
    }

    func record(consumed: Int) {
        lock.withLocked { storedConsumed = consumed }
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
            return try await remoteFetch(route: route, query: normalizedQuery, page: 1, limit: pageSize).poses
        }
        let key = PoseCacheKey(route: route, query: normalizedQuery)
        return try await cache.poses(for: key, baseURL: baseURL) {
            try await self.remoteFetch(route: route, query: normalizedQuery, page: 1, limit: pageSize).catalogFetch
        }
    }
    /// Offset-aware window read. Only the first window goes through the offline catalog; later windows
    /// are network-only and are not persisted, so a first-window stale-while-revalidate refresh can
    /// never prune rows the screen has already paged in (and an offline relaunch reads exactly the
    /// cached first window).
    ///
    /// The window is expressed as an offset because the server pages with `OFFSET`. An offset that is
    /// not a multiple of `limit` (the Saved list moved up by a confirmed unsave) still reads the
    /// aligned server page that *covers* it and drops the rows before it, so no row is skipped and
    /// the caller's cursor stays exact.
    func posesPage(query: String?, offset: Int, limit: Int) async throws -> PosePage {
        let route = PoseAdapterRoute.from(rawValue: filterState.effectiveRawValue)
        let normalizedQuery = PoseCacheKey.normalizedQuery(query)
        let window = max(1, limit)
        guard offset > 0 else {
            return try await firstPosesPage(route: route, query: normalizedQuery, limit: window)
        }

        let page = offset / window + 1
        let skipped = offset % window
        let later = try await remoteFetch(route: route, query: normalizedQuery, page: page, limit: window)
        // The rows before `offset` were already read, so they are dropped from the **raw** server rows
        // first and the local name filter runs on what is left. Slicing after the filter would drop
        // the matches that happen to sit in the skipped part of the window — the rows the cursor
        // claims were already shown — and the cursor would then move past them for good. A stale or
        // shrunken total below the offset answers an empty window, which ends the list instead of
        // asking for the same offset again.
        let raw = skipped == 0 ? later.rawPoses : Array(later.rawPoses.dropFirst(skipped))
        let poses = Self.filterLocally(raw, route: route, query: normalizedQuery)
        return PosePage(poses: poses, hasMore: later.hasMore, consumed: max(0, later.consumed - skipped))
    }

    private func firstPosesPage(route: PoseAdapterRoute, query: String?, limit: Int) async throws -> PosePage {
        let probe = PosePageLimitProbe()
        let load: @Sendable () async throws -> PoseCatalogFetch = {
            let fetched = try await self.remoteFetch(route: route, query: query, page: 1, limit: limit)
            probe.record(fetched.hasMore)
            probe.record(consumed: fetched.consumed)
            return fetched.catalogFetch
        }
        guard let cache, await cacheIsUsable(for: route) else {
            let fetched = try await load()
            return PosePage(
                poses: fetched.poses,
                hasMore: probe.hasMore ?? false,
                consumed: probe.consumed ?? fetched.poses.count
            )
        }
        let key = PoseCacheKey(route: route, query: query)
        let poses = try await cache.poses(for: key, baseURL: baseURL, load: load)
        // Answered from cache (memory or database): optimistic, because only the network knows the
        // real total. The next call to the network replaces it with the server's answer.
        return PosePage(
            poses: poses,
            hasMore: probe.hasMore ?? (poses.count >= limit),
            consumed: probe.consumed ?? poses.count
        )
    }

    /// `.saved` and `.all` both carry saved rows, so they are account-scoped; only the community
    /// feed may be answered from the offline catalog without a session.
    private func cacheIsUsable(for route: PoseAdapterRoute) async -> Bool {
        if route == .community { return true }
        return await hasSession()
    }

    /// One network window, its poses and the catalog rows that mirror it.
    private struct RemotePage {
        let poses: [NativePose]
        /// The same rows **before** the local Saved name filter. An unaligned window has to drop the
        /// rows it already showed from this array, not from the filtered one.
        let rawPoses: [NativePose]
        let hasMore: Bool
        /// Rows the server handed over, **before** the local name filter and any merge: this is what
        /// the cursor and `hasMore` are computed from.
        let consumed: Int
        /// `nil` for a window past the first: only the first one mirrors into the offline catalog.
        let fetch: PoseCatalogFetch?

        /// The catalog mirror of this window. A window past the first mirrors nothing: the empty plan
        /// carries no writes and replaces no bucket, so it cannot prune what the first one stored.
        var catalogFetch: PoseCatalogFetch {
            fetch ?? PoseCatalogFetch(
                poses: poses,
                writes: [],
                replacesCommunityBucket: false,
                replacesSavedBucket: false
            )
        }

        /// A window that is deliberately not persisted.
        static func networkOnly(
            _ poses: [NativePose],
            raw: [NativePose],
            consumed: Int,
            hasMore: Bool
        ) -> RemotePage {
            RemotePage(poses: poses, rawPoses: raw, hasMore: hasMore, consumed: consumed, fetch: nil)
        }
    }

    /// The network path plus the catalog rows that mirror the first window.
    ///
    /// `hasMore` is `consumed < total` with the server's own total, never `count == limit`: an
    /// exactly-full window is not the last one, and a total that shrank below the window we just
    /// read means the list ended while we were paging (not a crash, not an endless retry).
    private func remoteFetch(route: PoseAdapterRoute, query: String?, page: Int, limit: Int) async throws -> RemotePage {
        let consumed = (page - 1) * limit
        switch route {
        case .community:
            let data = try await remote.fetchCommunity(page: page, limit: limit, query: query)
            let poses = data.poses.map { CommunityPoseMapper.map($0, isSaved: false, baseURL: baseURL) }
            let hasMore = Self.hasMore(consumed: consumed + data.poses.count, total: data.total)
            guard page == 1 else {
                return .networkOnly(poses, raw: poses, consumed: data.poses.count, hasMore: hasMore)
            }
            return RemotePage(
                poses: poses,
                rawPoses: poses,
                hasMore: hasMore,
                consumed: data.poses.count,
                fetch: PoseCatalogFetch(
                    poses: poses,
                    writes: data.poses.map { write($0, source: .community) },
                    replacesCommunityBucket: query == nil,
                    replacesSavedBucket: false
                )
            )
        case .saved:
            let data = try await remote.fetchSaved(page: page, limit: limit)
            let mapped = data.poses.map { CommunityPoseMapper.map($0, isSaved: true, baseURL: baseURL) }
            // The saved endpoint takes no search text, so a window can contribute zero matches for
            // the query and still not be the last one.
            let poses = Self.filterLocally(mapped, route: route, query: query)
            let hasMore = Self.hasMore(consumed: consumed + data.poses.count, total: data.total)
            guard page == 1 else {
                return .networkOnly(poses, raw: mapped, consumed: data.poses.count, hasMore: hasMore)
            }
            return RemotePage(
                poses: poses,
                rawPoses: mapped,
                hasMore: hasMore,
                consumed: data.poses.count,
                fetch: PoseCatalogFetch(
                    poses: poses,
                    writes: data.poses.map { write($0, source: .saved) },
                    replacesCommunityBucket: false,
                    replacesSavedBucket: true
                )
            )
        case .all:
            let communityData = try await remote.fetchCommunity(page: page, limit: limit, query: query)
            let hasMore = Self.hasMore(consumed: consumed + communityData.poses.count, total: communityData.total)
            let community = communityData.poses.map { CommunityPoseMapper.map($0, isSaved: false, baseURL: baseURL) }
            // Saved rows are merged on the first window only. Paging both feeds would need two
            // cursors and would let one of them skip rows, so later windows follow the community
            // order alone (that is also why the first window's consumed count is the community one).
            guard page == 1 else {
                return .networkOnly(community, raw: community, consumed: communityData.poses.count, hasMore: hasMore)
            }
            let savedData = (try? await remote.fetchSaved(page: 1, limit: limit)) ?? .empty
            let saved = Self.filterLocally(
                savedData.poses.map { CommunityPoseMapper.map($0, isSaved: true, baseURL: baseURL) },
                route: .saved,
                query: query
            )
            let poses = PoseAdapterMerge.communityFirst(community: community, saved: saved)
            return RemotePage(
                poses: poses,
                rawPoses: poses,
                hasMore: hasMore,
                // The merged saved rows are shown once, but the cursor follows the community feed
                // alone (later windows are community-only), so it must not count them.
                consumed: communityData.poses.count,
                fetch: PoseCatalogFetch(
                    poses: poses,
                    writes: communityData.poses.map { write($0, source: .community) }
                        + savedData.poses.map { write($0, source: .saved) },
                    replacesCommunityBucket: query == nil,
                    replacesSavedBucket: true
                )
            )
        }
    }

    /// The only local filter in the paging pipeline: the Saved endpoint takes no search text, so its
    /// query is applied here. Every other route is filtered by the server.
    private static func filterLocally(
        _ poses: [NativePose],
        route: PoseAdapterRoute,
        query: String?
    ) -> [NativePose] {
        route == .saved ? PoseAdapterMerge.filterSavedLocally(poses, query: query) : poses
    }

    /// `consumed < total` — the server's own total, never the item count of one window.
    private static func hasMore(consumed: Int, total: Int) -> Bool {
        guard consumed > 0 else { return false }
        return consumed < total
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
        let community = try await remote.fetchCommunity(page: 1, limit: pageSize, query: nil).poses
        if let match = community.first(where: { $0.poseId == id }) {
            return CommunityPoseMapper.map(match, isSaved: false, baseURL: baseURL)
        }
        let saved = try await remote.fetchSaved(page: 1, limit: pageSize).poses
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
