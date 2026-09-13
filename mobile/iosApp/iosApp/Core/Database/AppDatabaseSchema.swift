import Foundation
import GRDB

enum AppDatabaseSchema {
    static let sqliteHeader = "SQLite format 3\u{0}"
    static let currentUserVersion = 2

    static let poseColumns = [
        "poseId", "ownerAccountId", "name", "description", "tags", "difficulty",
        "bodyParts", "status", "originalPath", "skeletonPath", "thumbnailPath",
        "currentJobId", "createdAt", "updatedAt",
    ]

    static let photoColumns = [
        "id", "imagePath", "poseId", "poseName", "createdAt", "isFavorite",
    ]

    static let cameraSnapshotColumns = [
        "id", "schemaVersion", "settings_json", "pose_json",
    ]

    static let poseIndexes = [
        "idx_pose_createdAt", "idx_pose_ownerAccountId", "idx_pose_status",
    ]

    static let photoIndexes = [
        "idx_photo_createdAt", "idx_photo_poseId", "idx_photo_isFavorite",
    ]

    static let allIndexes: [String] = (poseIndexes + photoIndexes).sorted()

    enum InspectionResult: Sendable, Equatable {
        case valid(userVersion: Int)
        case malformed(reason: String)
        case unknownSchema(reason: String)
    }

    static func inspectFile(at url: URL, fileManager: FileManager = .default) -> InspectionResult {
        guard fileManager.fileExists(atPath: url.path) else {
            return .malformed(reason: "missing file")
        }
        guard let header = try? Data(contentsOf: url, options: [.mappedIfSafe]).prefix(16),
              String(data: header, encoding: .utf8) == sqliteHeader else {
            return .malformed(reason: "invalid SQLite header")
        }
        do {
            var configuration = Configuration()
            configuration.readonly = true
            let queue = try DatabaseQueue(path: url.path, configuration: configuration)
            return try queue.read { db in
                try inspectExistingDatabase(db)
            }
        } catch {
            return .malformed(reason: error.localizedDescription)
        }
    }

    static func inspectExistingDatabase(_ db: Database) throws -> InspectionResult {
        let tables = try String.fetchAll(
            db,
            sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'grdb_migrations'
                ORDER BY name
                """
        )
        let unexpected = Set(tables).subtracting(["Pose", "Photo", "CameraSnapshot"])
        if !unexpected.isEmpty {
            return .unknownSchema(reason: "unexpected tables: \(unexpected.sorted().joined(separator: ", "))")
        }
        guard tables.contains("Pose"), tables.contains("Photo") else {
            return .unknownSchema(reason: "missing Pose or Photo table")
        }

        let poseInfo = try tableColumns(db, table: "Pose")
        guard poseInfo == poseColumns else {
            return .unknownSchema(reason: "Pose column mismatch")
        }
        let photoInfo = try tableColumns(db, table: "Photo")
        guard photoInfo == photoColumns else {
            return .unknownSchema(reason: "Photo column mismatch")
        }
        if tables.contains("CameraSnapshot") {
            let snapshotInfo = try tableColumns(db, table: "CameraSnapshot")
            guard snapshotInfo == cameraSnapshotColumns else {
                return .unknownSchema(reason: "CameraSnapshot column mismatch")
            }
        }

        let userVersion = try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
        if userVersion > currentUserVersion {
            return .unknownSchema(reason: "unsupported user_version \(userVersion)")
        }
        return .valid(userVersion: userVersion)
    }

    static func assertPostMigrationSchema(_ db: Database) throws {
        let inspection = try inspectExistingDatabase(db)
        guard case .valid = inspection else {
            throw AppDatabaseError.unknownLegacySchema(inspectionDescription(inspection))
        }
        try XCTAssertSchemaParity(db)
    }

    static func XCTAssertSchemaParity(_ db: Database) throws {
        let tables = try String.fetchAll(
            db,
            sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'grdb_migrations'
                ORDER BY name
                """
        )
        let poseInfo = try tableColumns(db, table: "Pose")
        let photoInfo = try tableColumns(db, table: "Photo")
        let cameraSnapshotInfo = try tableColumns(db, table: "CameraSnapshot")
        precondition(tables == ["CameraSnapshot", "Photo", "Pose"])
        precondition(poseInfo == poseColumns)
        precondition(photoInfo == photoColumns)
        precondition(cameraSnapshotInfo == cameraSnapshotColumns)

        let indexes = try String.fetchAll(
            db,
            sql: "SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'idx_%' ORDER BY name"
        )
        precondition(indexes == allIndexes)

        let fkCount = try Int.fetchOne(
            db,
            sql: """
                SELECT COUNT(*) FROM pragma_foreign_key_list('Photo')
                WHERE "table" = 'Pose' AND "from" = 'poseId' AND on_delete = 'SET NULL'
                """
        )
        precondition(fkCount == 1)
        let userVersion = try Int.fetchOne(db, sql: "PRAGMA user_version")
        precondition(userVersion == currentUserVersion)
    }

    private static func tableColumns(_ db: Database, table: String) throws -> [String] {
        try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info(?) ORDER BY cid", arguments: [table])
    }

    private static func inspectionDescription(_ result: InspectionResult) -> String {
        switch result {
        case .valid(let userVersion):
            return "valid(user_version: \(userVersion))"
        case .malformed(let reason):
            return "malformed(\(reason))"
        case .unknownSchema(let reason):
            return "unknown(\(reason))"
        }
    }
}
