import Foundation
import GRDB

struct PhotoRepository: Sendable {
    let database: AppDatabase
    /// Needed so a committed capture can drop its in-flight marker. Defaults to the app's capture
    /// directory; tests inject a temporary one.
    let imageStore: PhotoImageStore

    init(database: AppDatabase, imageStore: PhotoImageStore = PhotoImageStore()) {
        self.database = database
        self.imageStore = imageStore
    }

    func all() async throws -> [PhotoRecord] {
        try await database.pool.read { db in
            try PhotoRecord.order(Column("createdAt").desc).fetchAll(db)
        }
    }

    func insert(_ photo: PhotoRecord) async throws -> Int64 {
        let id = try await database.pool.write { db in
            var stored = photo
            try stored.insert(db)
            return stored.id ?? db.lastInsertedRowID
        }
        // The row is committed, so the file is now protected by reference. Dropping the claim is
        // bookkeeping only: if it never happens (crash right here), the sweep still sees a
        // referenced file and keeps it, then reaps the stale marker.
        imageStore.endCapture(imagePath: photo.imagePath)
        return id
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

    // MARK: - in-flight capture ownership

    /// Sidecar written next to a jpeg while it is being captured. Its existence is the claim, its
    /// timestamp is the claim's age.
    static let inFlightMarkerSuffix = ".pending"

    /// How long a claim is believed. A capture writes its jpeg and inserts its row within seconds, so
    /// a claim older than this belongs to a capture that died; the sweep is then allowed to reclaim
    /// the file. Bounded on purpose: a crashed capture must not pin an orphan forever.
    static let inFlightMarkerLifetime: TimeInterval = 60 * 60

    func inFlightMarkerURL(for imagePath: String) -> URL {
        fileURL(for: imagePath).appendingPathExtension(String(Self.inFlightMarkerSuffix.dropFirst()))
    }

    /// Claims `imagePath` before the bytes are written, so on-disk jpeg never exists unclaimed.
    /// Best effort: a marker that cannot be written leaves the file under the age guard, which is
    /// still the safe side of the trade (a late sweep, not a lost photo).
    func beginCapture(imagePath: String) {
        let marker = inFlightMarkerURL(for: imagePath)
        try? fileManager.createDirectory(
            at: marker.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? Data().write(to: marker, options: .atomic)
    }

    /// Releases the claim: the capture either got its row (committed) or its file is being removed
    /// (rolled back). Idempotent.
    func endCapture(imagePath: String) {
        try? fileManager.removeItem(at: inFlightMarkerURL(for: imagePath))
    }

    /// Reclaims files in the capture directory that no `Photo` row references any more.
    ///
    /// A claim (`beginCapture`) makes a file live no matter its age, so a capture that is still being
    /// written is never swept. Once the claim is older than `markerLifetime` it is treated as a crash
    /// remnant and both the claim and its unreferenced file are removed. Files without a claim keep
    /// the `minimumAge` guard. Returns the number of files removed.
    @discardableResult
    func sweepOrphans(
        referencing imagePaths: some Sequence<String>,
        minimumAge: TimeInterval = 24 * 60 * 60,
        markerLifetime: TimeInterval = PhotoImageStore.inFlightMarkerLifetime
    ) -> Int {
        guard let directoryURL else { return 0 }
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        let referenced = canonicalPaths(for: imagePaths)
        let now = Date()
        let cutoff = now.addingTimeInterval(-minimumAge)
        var removed = 0

        func isMarker(_ url: URL) -> Bool {
            url.lastPathComponent.hasSuffix(Self.inFlightMarkerSuffix)
        }

        var claimed: Set<String> = []
        for entry in entries where isMarker(entry) {
            guard let values = try? entry.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            let filename = String(
                entry.lastPathComponent.dropLast(Self.inFlightMarkerSuffix.count)
            )
            let key = canonicalPath(for: filename)
            let claimedFor = now.timeIntervalSince(values.contentModificationDate ?? .distantPast)
            if claimedFor <= markerLifetime {
                claimed.insert(key)
                continue
            }
            // Dead claim: reap it, and the file it never committed. A file that does have a row is
            // left alone — the claim is simply stale bookkeeping.
            try? fileManager.removeItem(at: entry)
            removed += 1
            let fileURL = fileURL(for: filename)
            if !referenced.contains(key), fileManager.fileExists(atPath: fileURL.path) {
                try? fileManager.removeItem(at: fileURL)
                removed += 1
            }
        }

        for entry in entries where !isMarker(entry) {
            guard let values = try? entry.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            let key = entry.resolvingSymlinksInPath().standardizedFileURL.path
            guard !referenced.contains(key) else { continue }
            guard !claimed.contains(key) else { continue }
            let modified = values.contentModificationDate ?? .distantPast
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

    /// Stores one settings payload in a single transaction, which is what makes two promises hold at
    /// once:
    /// - **`pose_json` is never touched.** The row is read and written back inside the same write, so
    ///   the pose columns come from the row itself (D8: saving settings is not a pose clear).
    /// - **The row is forward-only.** A payload is stored only when its `revision` is newer than the
    ///   one already stored, so a debounced write that lands after a newer write is dropped instead
    ///   of rolling the row back.
    func saveSettings(_ write: CameraSnapshotSettingsWrite) async throws {
        try await database.pool.write { db in
            let stored = try CameraSnapshotRecord.fetchOne(db, key: 1)
            if let stored, write.storedRevision(stored.settingsJSON) >= write.revision { return }
            var record = stored
                ?? CameraSnapshotRecord(schemaVersion: write.schemaVersion, settingsJSON: write.json)
            record.schemaVersion = write.schemaVersion
            record.settingsJSON = write.json
            try record.save(db)
        }
    }

    /// Stores (or clears) the remembered pose in one transaction, mirroring `saveSettings`:
    /// - **`settings_json` is never touched.** An existing row is read and written back inside the
    ///   same write, so the settings (and their revision) come from the row itself — remembering a
    ///   pose is not a settings edit and must not roll one back.
    /// - **The singleton row can be created here.** A pose remembered before any settings were stored
    ///   writes the caller's default settings payload, so the row never holds a pose with no settings.
    func savePose(_ write: CameraSnapshotPoseWrite) async throws {
        try await database.pool.write { db in
            if var record = try CameraSnapshotRecord.fetchOne(db, key: 1) {
                record.poseJSON = write.poseJSON
                try record.save(db)
            } else if let poseJSON = write.poseJSON {
                try CameraSnapshotRecord(
                    schemaVersion: write.schemaVersion,
                    settingsJSON: write.defaultSettingsJSON,
                    poseJSON: poseJSON
                ).save(db)
            }
        }
    }
}

/// One remembered-pose payload for the singleton row. `defaultSettingsJSON` is only used when the
/// write has to create the row; the snapshot layer does not know the settings shape, so the camera
/// side supplies it.
struct CameraSnapshotPoseWrite: Sendable {
    let poseJSON: String?
    let schemaVersion: Int64
    let defaultSettingsJSON: String
}

/// One settings payload for the singleton row. `storedRevision` reads the revision out of a stored
/// JSON payload; the snapshot layer does not know the settings shape, so the camera side supplies it.
struct CameraSnapshotSettingsWrite: Sendable {
    let json: String
    let schemaVersion: Int64
    let revision: Int64
    let storedRevision: @Sendable (String) -> Int64
}
