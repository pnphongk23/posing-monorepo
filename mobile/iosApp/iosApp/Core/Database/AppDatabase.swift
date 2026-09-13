import Foundation
import GRDB

enum AppDatabaseError: Error, Equatable {
    case ambiguousLegacyDatabases([String])
    case malformedLegacyDatabase(String)
    case unknownLegacySchema(String)
    case unexpectedDatabaseAtTarget(String)
}

struct AppDatabaseLocation: Sendable, Equatable {
    enum Kind: Sendable, Equatable { case existingLegacy, freshInstall }
    let url: URL
    let kind: Kind
}

enum LegacyDatabaseFileName: String, CaseIterable, Sendable {
    case aipose = "aipose.db"
    case aiPoseDatabase = "AiPoseDatabase.db"
}

enum AppDatabaseLocator {
    static let freshInstallFileName = LegacyDatabaseFileName.aipose.rawValue

    static let searchDirectorySuffixes = [
        "Library/Application Support/databases",
        "Library/Application Support",
        "Documents",
    ]

    struct ProbeCandidate: Sendable, Equatable {
        let url: URL
        let fileName: LegacyDatabaseFileName
        let directorySuffix: String
    }

    enum DiscoveryResult: Sendable, Equatable {
        case freshInstall(URL)
        case existingLegacy(URL)
        case ambiguous([String])
        case malformed(String)
        case unknownSchema(String)
    }

    static func probe(
        fileManager: FileManager = .default,
        homeDirectory: URL? = nil
    ) -> DiscoveryResult {
        let home = homeDirectory ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let existing = probeCandidates(fileManager: fileManager, homeDirectory: home)
            .filter { fileManager.fileExists(atPath: $0.url.path) }

        guard !existing.isEmpty else {
            return .freshInstall(freshInstallURL(homeDirectory: home))
        }

        var valid: [URL] = []
        var malformedMessages: [String] = []
        var unknownMessages: [String] = []

        for candidate in existing {
            switch AppDatabaseSchema.inspectFile(at: candidate.url, fileManager: fileManager) {
            case .valid:
                valid.append(candidate.url)
            case .malformed(let reason):
                malformedMessages.append("\(candidate.url.path): \(reason)")
            case .unknownSchema(let reason):
                unknownMessages.append("\(candidate.url.path): \(reason)")
            }
        }

        switch valid.count {
        case 0:
            if !unknownMessages.isEmpty {
                return .unknownSchema(unknownMessages.joined(separator: "; "))
            }
            return .malformed(malformedMessages.joined(separator: "; "))
        case 1:
            return .existingLegacy(valid[0])
        default:
            return .ambiguous(valid.map(\.path).sorted())
        }
    }

    static func locate(
        fileManager: FileManager = .default,
        homeDirectory: URL? = nil
    ) throws -> AppDatabaseLocation {
        switch probe(fileManager: fileManager, homeDirectory: homeDirectory) {
        case .freshInstall(let url):
            return AppDatabaseLocation(url: url, kind: .freshInstall)
        case .existingLegacy(let url):
            return AppDatabaseLocation(url: url, kind: .existingLegacy)
        case .ambiguous(let paths):
            throw AppDatabaseError.ambiguousLegacyDatabases(paths)
        case .malformed(let reason):
            throw AppDatabaseError.malformedLegacyDatabase(reason)
        case .unknownSchema(let reason):
            throw AppDatabaseError.unknownLegacySchema(reason)
        }
    }

    static func probeCandidates(
        fileManager: FileManager = .default,
        homeDirectory: URL
    ) -> [ProbeCandidate] {
        searchDirectorySuffixes.flatMap { suffix in
            let directory = homeDirectory.appendingPathComponent(suffix, isDirectory: true)
            return LegacyDatabaseFileName.allCases.map { fileName in
                ProbeCandidate(
                    url: directory.appendingPathComponent(fileName.rawValue),
                    fileName: fileName,
                    directorySuffix: suffix
                )
            }
        }
    }

    static func freshInstallURL(homeDirectory: URL) -> URL {
        homeDirectory
            .appendingPathComponent("Library/Application Support/databases", isDirectory: true)
            .appendingPathComponent(freshInstallFileName)
    }
}

final class AppDatabase: @unchecked Sendable {
    static let schemaVersion = AppDatabaseSchema.currentUserVersion
    let pool: DatabasePool
    let location: AppDatabaseLocation

    init(location: AppDatabaseLocation? = nil, fileManager: FileManager = .default) throws {
        let resolved = try location ?? AppDatabaseLocator.locate(fileManager: fileManager)
        self.location = resolved

        if resolved.kind == .existingLegacy,
           !fileManager.fileExists(atPath: resolved.url.path) {
            throw AppDatabaseError.unexpectedDatabaseAtTarget(resolved.url.path)
        }
        if resolved.kind == .freshInstall {
            try fileManager.createDirectory(
                at: resolved.url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }

        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        pool = try DatabasePool(path: resolved.url.path, configuration: configuration)
        try Self.migrator.migrate(pool)
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.eraseDatabaseOnSchemaChange = false

        migrator.registerMigration("v1_sqlDelight_base") { db in
            // DatabaseMigrator already wraps each migration in a transaction.
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS Pose (
                    poseId TEXT PRIMARY KEY,
                    ownerAccountId TEXT NOT NULL,
                    name TEXT NOT NULL,
                    description TEXT,
                    tags TEXT NOT NULL DEFAULT '[]',
                    difficulty TEXT,
                    bodyParts TEXT NOT NULL DEFAULT '[]',
                    status TEXT NOT NULL DEFAULT 'local' CHECK(status IN ('local', 'published')),
                    originalPath TEXT NOT NULL,
                    skeletonPath TEXT NOT NULL,
                    thumbnailPath TEXT NOT NULL,
                    currentJobId TEXT,
                    createdAt TEXT NOT NULL,
                    updatedAt TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_pose_createdAt ON Pose(createdAt);
                CREATE INDEX IF NOT EXISTS idx_pose_ownerAccountId ON Pose(ownerAccountId);
                CREATE INDEX IF NOT EXISTS idx_pose_status ON Pose(status);
                CREATE TABLE IF NOT EXISTS Photo (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    imagePath TEXT NOT NULL,
                    poseId TEXT,
                    poseName TEXT NOT NULL DEFAULT '',
                    createdAt TEXT NOT NULL,
                    isFavorite INTEGER NOT NULL DEFAULT 0,
                    FOREIGN KEY (poseId) REFERENCES Pose(poseId) ON DELETE SET NULL
                );
                CREATE INDEX IF NOT EXISTS idx_photo_createdAt ON Photo(createdAt);
                CREATE INDEX IF NOT EXISTS idx_photo_poseId ON Photo(poseId);
                CREATE INDEX IF NOT EXISTS idx_photo_isFavorite ON Photo(isFavorite);
                """)
            if try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0 < 1 {
                try db.execute(sql: "PRAGMA user_version = 1")
            }
        }

        migrator.registerMigration("v2_sqlDelight_camera_snapshot") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS CameraSnapshot (
                    id INTEGER NOT NULL PRIMARY KEY CHECK (id = 1),
                    schemaVersion INTEGER NOT NULL,
                    settings_json TEXT NOT NULL,
                    pose_json TEXT
                );
                """)
            if try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0 < 2 {
                try db.execute(sql: "PRAGMA user_version = 2")
            }
        }

        return migrator
    }
}
