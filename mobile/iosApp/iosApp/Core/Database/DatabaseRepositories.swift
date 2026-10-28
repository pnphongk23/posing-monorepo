import Foundation
import GRDB

struct PhotoRepository: Sendable {
    let database: AppDatabase

    func all() async throws -> [PhotoRecord] {
        try await database.pool.read { db in
            try PhotoRecord.order(Column("createdAt").desc).fetchAll(db)
        }
    }

    func insert(_ photo: PhotoRecord) async throws -> Int64 {
        try await database.pool.write { db in
            var stored = photo
            try stored.insert(db)
            return stored.id ?? db.lastInsertedRowID
        }
    }

    func toggleFavorite(id: Int64) async throws {
        try await database.pool.write { db in
            try db.execute(sql: "UPDATE Photo SET isFavorite = CASE isFavorite WHEN 0 THEN 1 ELSE 0 END WHERE id = ?", arguments: [id])
        }
    }

    /// Deletes the row and hands back the `imagePath` it referenced so the caller can reclaim the
    /// file. Row first, on purpose: the row/file pair cannot be deleted atomically, and a leftover
    /// file is recoverable (it gets swept) while a leftover row pointing at a missing file is a
    /// broken tile the user sees.
    func delete(id: Int64) async throws -> String? {
        try await database.pool.write { db in
            guard let record = try PhotoRecord.fetchOne(db, key: id) else { return nil }
            try db.execute(sql: "DELETE FROM Photo WHERE id = ?", arguments: [id])
            return record.imagePath
        }
    }

    /// Every `imagePath` a surviving row points at. Compared by `PhotoImageStore.canonicalPath`, not
    /// by string equality: the same file can be spelled as a bare capture name by today's rows and
    /// as an absolute path by legacy ones.
    func imagePaths() async throws -> [String] {
        try await database.pool.read { db in
            try PhotoRecord.fetchAll(db).map(\.imagePath)
        }
    }
}

/// Feed buckets for the offline pose catalog. The catalog lives in the shared `Pose` table and
/// uses the row's `ownerAccountId` as its bucket marker (see `PoseCatalogMapping`): no schema
/// change or migration is allowed for the pose cache, so cache bookkeeping rides on existing
/// columns. Rows whose `ownerAccountId` is not one of these values (e.g. legacy local poses) are
/// **not** cache-owned and are never read or pruned by the catalog.
///
/// - `community`: row was observed in the community feed. It may also be saved (`status == local`),
///   exactly like `PoseAdapterMerge.communityFirst` keeps a community entry for a saved pose.
/// - `saved`: row is known only from the viewer's saved feed (saved, no longer in the community
///   page we hold).
enum PoseCatalogBucket: String, CaseIterable, Sendable {
    case community = "cache:community"
    case saved = "cache:saved"
}

struct PoseRepository: Sendable {
    let database: AppDatabase

    func pose(id: String) async throws -> PoseRecord? {
        try await database.pool.read { db in try PoseRecord.fetchOne(db, key: id) }
    }

    func save(_ pose: PoseRecord) async throws {
        try await database.pool.write { db in try pose.save(db) }
    }

    /// Every row of `Pose`, cache-owned or not. Ordered by the stored timestamp so the offline
    /// catalog (which has no server pagination order) is at least stable between reads.
    func all() async throws -> [PoseRecord] {
        try await database.pool.read { db in
            try PoseRecord
                .order(Column("createdAt").desc, Column("poseId").asc)
                .fetchAll(db)
        }
    }

    /// Rows the pose cache owns (`PoseCatalogBucket` marker present), ignoring legacy local poses.
    func cached() async throws -> [PoseRecord] {
        try await database.pool.read { db in
            try PoseRecord
                .filter(
                    sql: "ownerAccountId IN (?, ?)",
                    arguments: [PoseCatalogBucket.community.rawValue, PoseCatalogBucket.saved.rawValue]
                )
                .order(Column("createdAt").desc, Column("poseId").asc)
                .fetchAll(db)
        }
    }

    /// Batch upsert in a single write transaction (cache writes a whole fetched page at once).
    func upsert(_ poses: [PoseRecord]) async throws {
        guard !poses.isEmpty else { return }
        try await database.pool.write { db in
            for pose in poses { try pose.save(db) }
        }
    }

    func delete(ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        try await database.pool.write { db in
            try db.execute(
                sql: "DELETE FROM Pose WHERE poseId IN (\(placeholders))",
                arguments: StatementArguments(ids)
            )
        }
    }
}

/// Owns the jpeg side of a `Photo` row. Rows and files cannot be deleted atomically, so the row
/// always goes first: the worst an interrupted delete can leave behind is a file nothing points at,
/// which `sweepOrphans` reclaims on the next gallery read. The opposite order would leave a row
/// whose `imagePath` no longer exists, i.e. a broken tile in the gallery.
/// `FileManager` is not `Sendable`, but these are stateless filesystem calls on one directory;
/// the type carries no mutable state, so sharing it across actors is safe.
struct PhotoImageStore: @unchecked Sendable {
    let directoryURL: URL?
    let fileManager: FileManager

    init(
        directoryURL: URL? = PhotoImageStore.defaultDirectoryURL,
        fileManager: FileManager = .default
    ) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
    }

    /// `CaptureImageStorage` writes captures here; `Photo.imagePath` holds the bare file name.
    static var defaultDirectoryURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("aipose", isDirectory: true)
    }

    /// Absolute paths (legacy rows) are used as-is, bare file names resolve against the capture
    /// directory — the same rule `GalleryMediaPath.fileURL` applies when reading.
    func fileURL(for imagePath: String) -> URL {
        if imagePath.hasPrefix("/") { return URL(fileURLWithPath: imagePath) }
        let directory = directoryURL ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return directory.appendingPathComponent(imagePath)
    }

    /// One identity per file, however a row spells the path: `capture_1.jpg` and
    /// `/…/aipose/capture_1.jpg` resolve to the same string, and symlinked containers (`/tmp` →
    /// `/private/tmp`) do not split it. Reference checks and the sweep both compare these keys, so a
    /// shared file is never removed while another row still points at it.
    func canonicalPath(for imagePath: String) -> String {
        fileURL(for: imagePath).resolvingSymlinksInPath().standardizedFileURL.path
    }

    func canonicalPaths(for imagePaths: some Sequence<String>) -> Set<String> {
        Set(imagePaths.map(canonicalPath(for:)))
    }

    func isReferenced(_ imagePath: String, among imagePaths: some Sequence<String>) -> Bool {
        canonicalPaths(for: imagePaths).contains(canonicalPath(for: imagePath))
    }

    /// Idempotent: a file that is already gone is not an error, so a retried delete succeeds.
    func remove(imagePath: String) {
        try? fileManager.removeItem(at: fileURL(for: imagePath))
    }

    /// Reclaims files in the capture directory that no `Photo` row references any more.
    ///
    /// `minimumAge` is what makes the sweep safe while a capture is in flight: a jpeg is written
    /// before its row is inserted, so a fresh unreferenced file may simply belong to a capture that
    /// is still being saved. The guard is a day, not an hour: a capture task can be suspended
    /// between the write and the metadata insert (app backgrounded), and nothing in the pipeline
    /// records ownership before the insert lands. Returns the number of files removed.
    @discardableResult
    func sweepOrphans(
        referencing imagePaths: some Sequence<String>,
        minimumAge: TimeInterval = 24 * 60 * 60
    ) -> Int {
        guard let directoryURL else { return 0 }
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        let referenced = canonicalPaths(for: imagePaths)

        let cutoff = Date().addingTimeInterval(-minimumAge)
        var removed = 0
        for entry in entries {
            let values = try? entry.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            guard !referenced.contains(entry.resolvingSymlinksInPath().standardizedFileURL.path) else { continue }
            let modified = values?.contentModificationDate ?? .distantPast
            guard modified <= cutoff else { continue }
            if (try? fileManager.removeItem(at: entry)) != nil { removed += 1 }
        }
        return removed
    }
}

struct CameraSnapshotRepository: Sendable {
    let database: AppDatabase

    func snapshot() async throws -> CameraSnapshotRecord? {
        try await database.pool.read { db in try CameraSnapshotRecord.fetchOne(db, key: 1) }
    }

    func save(_ snapshot: CameraSnapshotRecord) async throws {
        precondition(snapshot.id == 1)
        try await database.pool.write { db in try snapshot.save(db) }
    }

    func clearPose() async throws {
        try await database.pool.write { db in
            try db.execute(sql: "UPDATE CameraSnapshot SET pose_json = NULL WHERE id = 1")
        }
    }
}
