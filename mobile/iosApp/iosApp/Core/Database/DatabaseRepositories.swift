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
