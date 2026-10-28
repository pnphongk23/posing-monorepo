import XCTest
import GRDB
@testable import iosApp

final class LegacyDatabaseCompatibilityTests: XCTestCase {
    func testV1FixtureUpgradesWithoutDataLossAndIsIdempotent() async throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "legacy-aipose-v1", withExtension: "sqlite"))
        let root = makeHome()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Documents/aipose.db")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture, to: target)

        try assertPreMigrationState(at: target, expectsCameraSnapshot: false)
        let first = try AppDatabase(location: AppDatabaseLocation(url: target, kind: .existingLegacy))
        try await assertGoldenContents(first)
        let second = try AppDatabase(location: AppDatabaseLocation(url: target, kind: .existingLegacy))
        try await assertGoldenContents(second)
        try assertPostMigrationState(at: target)
    }

    /// FEAT-012 rides on the `settings_json` column that v2 already created, so a device that is
    /// still on a v1 file gets working camera settings after the ordinary upgrade — no new
    /// migration, no schema change, and the legacy pose/photo rows are untouched.
    func testV1FixtureUpgradePersistsCameraSettingsWithoutASchemaChange() async throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "legacy-aipose-v1", withExtension: "sqlite"))
        let root = makeHome()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Documents/aipose.db")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture, to: target)
        try assertPreMigrationState(at: target, expectsCameraSnapshot: false)

        let database = try AppDatabase(location: AppDatabaseLocation(url: target, kind: .existingLegacy))
        let store = GRDBCameraSettingsStore(database: database)
        try await store.save(CameraSettings(revision: 2, guideOpacity: 0.42, flash: .on, zoom: .two))

        let restored = try await store.load()
        XCTAssertEqual(restored?.guideOpacity ?? 0, 0.42, accuracy: 0.001)
        XCTAssertEqual(restored?.flash, .on)
        XCTAssertEqual(restored?.zoom, .two)

        try await database.pool.read { db in
            try AppDatabaseSchema.XCTAssertSchemaParity(db)
            let row = try XCTUnwrap(CameraSnapshotRecord.fetchOne(db, key: 1))
            XCTAssertEqual(row.schemaVersion, Int64(CameraSettings.currentVersion))
            XCTAssertNil(row.poseJSON, "a settings save never invents a pose")
            let pose = try XCTUnwrap(PoseRecord.fetchOne(db, key: "pose-legacy-01"))
            XCTAssertEqual(pose.tags, "[\"portrait\",\"legacy\"]")
            XCTAssertEqual(try PhotoRecord.fetchCount(db), 2)
        }
        try assertPostMigrationState(at: target)
    }

    func testAiPoseDatabaseFilenameInDatabasesDirectory() async throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "legacy-aipose-database-v1", withExtension: "sqlite"))
        let home = makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let target = home.appendingPathComponent("Library/Application Support/databases/AiPoseDatabase.db")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture, to: target)

        let located = try AppDatabaseLocator.locate(fileManager: .default, homeDirectory: home)
        XCTAssertEqual(located.kind, .existingLegacy)
        XCTAssertEqual(located.url, target)
        _ = try AppDatabase(location: located)
        try assertPostMigrationState(at: target)
    }

    func testFreshInstallUsesCanonicalDatabasesPath() throws {
        let home = makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let located = try AppDatabaseLocator.locate(fileManager: .default, homeDirectory: home)
        XCTAssertEqual(located.kind, .freshInstall)
        XCTAssertEqual(
            located.url,
            home.appendingPathComponent("Library/Application Support/databases/aipose.db")
        )
        _ = try AppDatabase(location: located)
        XCTAssertTrue(FileManager.default.fileExists(atPath: located.url.path))
    }

    func testExistingLegacyWinsOverFreshInstallPath() throws {
        let home = makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let legacy = home.appendingPathComponent("Documents/aipose.db")
        try copyFixture(named: "legacy-aipose-v1", to: legacy)
        let located = try AppDatabaseLocator.locate(fileManager: .default, homeDirectory: home)
        XCTAssertEqual(located.kind, .existingLegacy)
        XCTAssertEqual(located.url, legacy)
    }

    func testAmbiguousValidCandidatesFailSafe() throws {
        let home = makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try copyFixture(
            named: "legacy-aipose-v1",
            to: home.appendingPathComponent("Documents/aipose.db")
        )
        try copyFixture(
            named: "legacy-aipose-v1",
            to: home.appendingPathComponent("Library/Application Support/AiPoseDatabase.db")
        )
        let result = AppDatabaseLocator.probe(fileManager: .default, homeDirectory: home)
        guard case .ambiguous(let paths) = result else {
            return XCTFail("expected ambiguous, got \(result)")
        }
        XCTAssertEqual(paths.count, 2)
        XCTAssertThrowsError(try AppDatabaseLocator.locate(fileManager: .default, homeDirectory: home)) { error in
            guard case AppDatabaseError.ambiguousLegacyDatabases = error else {
                return XCTFail("unexpected error \(error)")
            }
        }
    }

    func testMalformedCandidateBlocksStartup() throws {
        let home = makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let malformed = home.appendingPathComponent("Documents/aipose.db")
        try FileManager.default.createDirectory(at: malformed.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: malformed.path, contents: Data("not sqlite".utf8))
        let result = AppDatabaseLocator.probe(fileManager: .default, homeDirectory: home)
        guard case .malformed = result else {
            return XCTFail("expected malformed, got \(result)")
        }
        XCTAssertThrowsError(try AppDatabaseLocator.locate(fileManager: .default, homeDirectory: home)) { error in
            guard case AppDatabaseError.malformedLegacyDatabase = error else {
                return XCTFail("unexpected error \(error)")
            }
        }
    }

    func testUnknownSchemaBlocksStartup() throws {
        let home = makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let target = home.appendingPathComponent("Documents/aipose.db")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        let queue = try DatabaseQueue(path: target.path, configuration: configuration)
        try queue.write { db in
            try db.execute(sql: "CREATE TABLE Mystery (id INTEGER PRIMARY KEY)")
            try db.execute(sql: "PRAGMA user_version = 1")
        }
        let result = AppDatabaseLocator.probe(fileManager: .default, homeDirectory: home)
        guard case .unknownSchema = result else {
            return XCTFail("expected unknown schema, got \(result)")
        }
        XCTAssertThrowsError(try AppDatabaseLocator.locate(fileManager: .default, homeDirectory: home)) { error in
            guard case AppDatabaseError.unknownLegacySchema = error else {
                return XCTFail("unexpected error \(error)")
            }
        }
    }

    func testResolverMatrixCoversAllProbePaths() {
        let home = makeHome()
        let candidates = AppDatabaseLocator.probeCandidates(fileManager: .default, homeDirectory: home)
        XCTAssertEqual(candidates.count, 6)
        XCTAssertEqual(
            Set(candidates.map(\.directorySuffix)),
            Set(AppDatabaseLocator.searchDirectorySuffixes)
        )
        XCTAssertEqual(Set(candidates.map(\.fileName)), Set(LegacyDatabaseFileName.allCases))
    }

    /// The offline pose catalog shares the `Pose` table with legacy local poses. It must never read,
    /// rewrite or prune a row it does not own (bucket marker absent).
    func testPoseCatalogLeavesLegacyLocalPosesUntouched() async throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "legacy-aipose-v1", withExtension: "sqlite"))
        let root = makeHome()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Documents/aipose.db")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture, to: target)
        let database = try AppDatabase(location: AppDatabaseLocation(url: target, kind: .existingLegacy))
        let repository = PoseRepository(database: database)
        let legacyRow = try await repository.pose(id: "pose-legacy-01")
        let legacyBefore = try XCTUnwrap(legacyRow)
        XCTAssertEqual(legacyBefore.status, "local")

        let remote = CatalogPoseRemote()
        let adapter = PoseAPIServiceAdapter(
            remote: remote,
            baseURL: "https://api.example.com",
            filterState: PoseFilterState(),
            cache: PoseCatalogCacheStore(repository: repository)
        )
        let cachedPoses = try await adapter.poses(query: nil)
        XCTAssertEqual(cachedPoses.map(\.id), ["cache-pose-1"])

        let catalogRow = try await repository.pose(id: "cache-pose-1")
        XCTAssertEqual(catalogRow?.ownerAccountId, PoseCatalogBucket.community.rawValue)
        let legacyAfter = try await repository.pose(id: "pose-legacy-01")
        XCTAssertEqual(legacyAfter, legacyBefore)

        let catalog = try await repository.cached()
        XCTAssertEqual(catalog.map(\.poseId), ["cache-pose-1"], "a legacy local pose is not a catalog row")
        let all = try await repository.all()
        XCTAssertEqual(all.map(\.poseId).sorted(), ["cache-pose-1", "pose-legacy-01"])
    }

    private func makeHome() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func copyFixture(named name: String, to target: URL) throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "sqlite"))
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture, to: target)
    }

    private func assertPreMigrationState(at url: URL, expectsCameraSnapshot: Bool) throws {
        var configuration = Configuration()
        configuration.readonly = true
        let queue = try DatabaseQueue(path: url.path, configuration: configuration)
        try queue.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "PRAGMA user_version"), 1)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM Pose"), 1)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM Photo"), 2)
            let tables = try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
            )
            XCTAssertEqual(tables, expectsCameraSnapshot ? ["CameraSnapshot", "Photo", "Pose"] : ["Photo", "Pose"])
        }
    }

    private func assertPostMigrationState(at url: URL) throws {
        var configuration = Configuration()
        configuration.readonly = true
        let queue = try DatabaseQueue(path: url.path, configuration: configuration)
        try queue.read { db in
            try AppDatabaseSchema.assertPostMigrationSchema(db)
        }
    }

    private func assertGoldenContents(_ app: AppDatabase) async throws {
        try await app.pool.write { db in
            try AppDatabaseSchema.assertPostMigrationSchema(db)
            let pose = try XCTUnwrap(PoseRecord.fetchOne(db, key: "pose-legacy-01"))
            XCTAssertEqual(pose.tags, "[\"portrait\",\"legacy\"]")
            XCTAssertEqual(pose.bodyParts, "[\"arms\",\"torso\"]")
            XCTAssertEqual(pose.originalPath, "Documents/original legacy.jpg")
            let photos = try PhotoRecord.order(Column("id")).fetchAll(db)
            XCTAssertEqual(photos.map(\.id), [41, 42])
            XCTAssertEqual(photos.first?.poseId, pose.poseId)
            XCTAssertEqual(photos.first?.imagePath, "Documents/capture legacy.jpg")
            try CameraSnapshotRecord(schemaVersion: 7, settingsJSON: "{\"flash\":true}", poseJSON: "{\"poseId\":\"pose-legacy-01\"}").save(db)
            XCTAssertEqual(try CameraSnapshotRecord.fetchOne(db, key: 1)?.poseJSON, "{\"poseId\":\"pose-legacy-01\"}")
        }
    }
}

/// Minimal community feed used by the catalog/legacy-table isolation test.
private struct CatalogPoseRemote: PoseRemoteFetching {
    func fetchCommunity(page: Int, limit: Int, query: String?) async throws -> PoseRemotePage {
        let poses = try [JSONDecoder().decode(CommunityPose.self, from: Data("""
        {"poseId":"cache-pose-1","name":"Cache Pose","skeletonUrl":"/skeleton.png","thumbnailUrl":"/thumb.jpg","status":"published"}
        """.utf8))]
        return PoseRemotePage(poses: poses, total: poses.count)
    }

    func fetchSaved(page: Int, limit: Int) async throws -> PoseRemotePage { .empty }
}
