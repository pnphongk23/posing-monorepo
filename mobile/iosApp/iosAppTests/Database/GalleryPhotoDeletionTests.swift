import XCTest
import GRDB
@testable import iosApp

/// Deleting a gallery photo has to remove both halves of it: the `Photo` row and the jpeg that row
/// points at. These tests run against a real GRDB database in a temporary directory and a real
/// capture directory, so they see the same filesystem the app sees.
final class GalleryPhotoDeletionTests: XCTestCase {
    private var root: URL!
    private var captureDirectory: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("gallery-delete-\(UUID().uuidString)", isDirectory: true)
        captureDirectory = root.appendingPathComponent("captures", isDirectory: true)
        try FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testDeletingPhotoRemovesRowAndJpegFile() async throws {
        let database = try makeDatabase()
        let store = DatabaseGalleryStore(database: database, imageStore: makeImageStore())
        let filename = try writeCapture(named: "capture_delete-me.jpg")
        let id = try await insertPhoto(imagePath: filename, into: database)

        try await store.delete(id: id)

        let remaining = try await PhotoRepository(database: database).all()
        XCTAssertTrue(remaining.isEmpty, "row should be gone")
        XCTAssertFalse(fileExists(filename), "jpeg should be gone with its row")
    }

    /// The delete can be interrupted between the two steps (row committed, file not yet removed).
    /// The next gallery read must not leave that file behind forever, and the gallery must still
    /// load — a missing file is never allowed to break a row that is still there.
    func testInterruptedDeleteIsSweptOnNextGalleryRead() async throws {
        let database = try makeDatabase()
        let store = DatabaseGalleryStore(database: database, imageStore: makeImageStore())
        let filename = try writeCapture(named: "capture_interrupted.jpg")
        let id = try await insertPhoto(imagePath: filename, into: database)

        // Simulate the crash: the row commit landed, the file removal never ran.
        try await database.pool.write { db in
            try db.execute(sql: "DELETE FROM Photo WHERE id = ?", arguments: [id])
        }
        XCTAssertTrue(fileExists(filename), "precondition: the crash left the file")

        let items = try await store.photos()

        XCTAssertTrue(items.isEmpty)
        XCTAssertFalse(fileExists(filename), "the orphaned jpeg should be reclaimed on the next read")
    }

    // MARK: - more delete-path behaviour

    func testDeletingMissingPhotoIsANoOp() async throws {
        let database = try makeDatabase()
        let store = DatabaseGalleryStore(database: database, imageStore: makeImageStore())
        let filename = try writeCapture(named: "capture_untouched.jpg")
        _ = try await insertPhoto(imagePath: filename, into: database)

        try await store.delete(id: 9_999)

        let count = try await remainingCount(database)
        XCTAssertEqual(count, 1)
        XCTAssertTrue(fileExists(filename), "deleting a row that does not exist must not touch files")
    }

    func testSharedImagePathKeepsFileUntilLastRowIsDeleted() async throws {
        let database = try makeDatabase()
        let store = DatabaseGalleryStore(database: database, imageStore: makeImageStore())
        let filename = try writeCapture(named: "capture_shared.jpg")
        let first = try await insertPhoto(imagePath: filename, into: database)
        let second = try await insertPhoto(imagePath: filename, into: database)

        try await store.delete(id: first)

        XCTAssertTrue(fileExists(filename), "a second row still points at this file")
        let afterFirst = try await PhotoRepository(database: database).all().map(\.id)
        XCTAssertEqual(afterFirst, [second])

        try await store.delete(id: second)

        XCTAssertFalse(fileExists(filename), "the last reference removes the file")
    }

    func testDeletingPhotoWithAbsoluteLegacyPathRemovesThatFile() async throws {
        let database = try makeDatabase()
        let store = DatabaseGalleryStore(database: database, imageStore: makeImageStore())
        let absolute = root.appendingPathComponent("legacy/photo.jpg")
        try FileManager.default.createDirectory(at: absolute.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x22, count: 64).write(to: absolute)
        let id = try await insertPhoto(imagePath: absolute.path, into: database)

        try await store.delete(id: id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: absolute.path))
    }

    func testSweepKeepsReferencedAndFreshFilesAndReclaimsOldOrphans() async throws {
        let database = try makeDatabase()
        let store = DatabaseGalleryStore(database: database, imageStore: makeImageStore())
        let referenced = try writeCapture(named: "capture_referenced.jpg")
        let freshOrphan = try writeCapture(named: "capture_in-flight.jpg", age: 0)
        let oldOrphan = try writeCapture(named: "capture_abandoned.jpg")
        let id = try await insertPhoto(imagePath: referenced, into: database)
        XCTAssertEqual(id > 0, true)

        let items = try await store.photos()

        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(fileExists(referenced), "a live row keeps its file")
        XCTAssertTrue(fileExists(freshOrphan), "a capture whose row is still being written is not swept")
        XCTAssertFalse(fileExists(oldOrphan), "an orphan from an interrupted delete is reclaimed")
    }

    /// Deleting a `Pose` is not a photo delete: the row survives via `ON DELETE SET NULL`, so the
    /// pair (row, file) stays consistent either way — there is nothing to reclaim here.
    func testDeletingPoseKeepsPhotoRowAndItsFile() async throws {
        let database = try makeDatabase()
        let store = DatabaseGalleryStore(database: database, imageStore: makeImageStore())
        let poses = PoseRepository(database: database)
        try await poses.save(
            PoseRecord(
                poseId: "pose-1",
                ownerAccountId: PoseCatalogBucket.community.rawValue,
                name: "Pose",
                description: nil,
                tags: "[]",
                difficulty: nil,
                bodyParts: "[]",
                status: "published",
                originalPath: "",
                skeletonPath: "",
                thumbnailPath: "",
                currentJobId: nil,
                createdAt: "1700000000000",
                updatedAt: "1700000000000"
            )
        )
        let photo = PhotoRecord(
            id: nil,
            imagePath: try writeCapture(named: "capture_with-pose.jpg"),
            poseId: "pose-1",
            poseName: "Pose",
            createdAt: "1700000000000",
            isFavorite: 0
        )
        let id = try await PhotoRepository(database: database).insert(photo)

        try await poses.delete(ids: ["pose-1"])

        let items = try await store.photos()
        let surviving = try await PhotoRepository(database: database).all()
        XCTAssertEqual(items.map(\.id), [id])
        XCTAssertNil(surviving.first?.poseId)
        XCTAssertTrue(fileExists(photo.imagePath))
    }

    /// The same file, spelled two ways: a legacy row stores the absolute path, today's rows store the
    /// bare capture name. String comparison would drop the file the absolute row still needs.
    func testSharedFileSpelledAbsolutelyAndRelativelyKeepsFileUntilLastRowIsDeleted() async throws {
        let database = try makeDatabase()
        let store = DatabaseGalleryStore(database: database, imageStore: makeImageStore())
        let filename = try writeCapture(named: "capture_mixed-path.jpg")
        let absolute = captureDirectory.appendingPathComponent(filename).path
        let legacy = try await insertPhoto(imagePath: absolute, into: database)
        let current = try await insertPhoto(imagePath: filename, into: database)

        try await store.delete(id: current)

        XCTAssertTrue(fileExists(filename), "the legacy row's absolute path still points at this file")

        try await store.delete(id: legacy)

        XCTAssertFalse(fileExists(filename), "the last reference removes the file")
    }

    func testSweepKeepsFileReferencedOnlyThroughAbsolutePath() async throws {
        let database = try makeDatabase()
        let store = DatabaseGalleryStore(database: database, imageStore: makeImageStore())
        let filename = try writeCapture(named: "capture_absolute-only.jpg")
        _ = try await insertPhoto(
            imagePath: captureDirectory.appendingPathComponent(filename).path,
            into: database
        )

        let items = try await store.photos()

        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(fileExists(filename), "the row's absolute path owns this file")
    }

    // MARK: - in-flight captures

    /// A capture that has written its jpeg but not its row yet must survive the sweep, even if the
    /// file is already older than the orphan guard (a slow or backgrounded capture).
    func testSweepKeepsFileThatACaptureIsStillWriting() throws {
        let storage = CaptureImageStorage(directoryURL: captureDirectory)
        let filename = try XCTUnwrap(storage.writeJpeg(Data(repeating: 0x33, count: 64), captureId: "in-flight"))
        try backdate(filename, by: 25 * 60 * 60, in: captureDirectory)
        XCTAssertTrue(fileExists(filename))

        let removed = makeImageStore().sweepOrphans(referencing: [])

        XCTAssertEqual(removed, 0)
        XCTAssertTrue(fileExists(filename), "a claimed capture is never swept")
    }

    /// Once the row exists the file is ordinary: protected by reference, and the claim is released.
    func testCommittedCaptureIsProtectedAsARegularRow() async throws {
        let database = try makeDatabase()
        let storage = CaptureImageStorage(directoryURL: captureDirectory)
        let filename = try XCTUnwrap(storage.writeJpeg(Data(repeating: 0x34, count: 64), captureId: "committed"))
        _ = try await insertPhoto(imagePath: filename, into: database)

        let marker = makeImageStore().inFlightMarkerURL(for: filename)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "commit releases the claim")

        try backdate(filename, by: 25 * 60 * 60, in: captureDirectory)
        let items = try await DatabaseGalleryStore(database: database, imageStore: makeImageStore()).photos()

        XCTAssertEqual(items.map(\.fileURL.lastPathComponent), [filename])
        XCTAssertTrue(fileExists(filename), "the row protects the file as before")
    }

    /// A capture that was killed mid-write leaves a claim nothing will ever release. The claim is
    /// bounded, so the sweep still reclaims the orphan — otherwise the file would leak forever.
    func testStaleMarkerLetsSweepReclaimTheAbandonedFile() throws {
        let storage = CaptureImageStorage(directoryURL: captureDirectory)
        let filename = try XCTUnwrap(storage.writeJpeg(Data(repeating: 0x35, count: 64), captureId: "killed"))
        let imageStore = makeImageStore()
        let marker = imageStore.inFlightMarkerURL(for: filename)
        try backdate(filename, by: 25 * 60 * 60, in: captureDirectory)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-2 * 60 * 60)],
            ofItemAtPath: marker.path
        )

        let removed = imageStore.sweepOrphans(referencing: [])

        XCTAssertGreaterThan(removed, 0)
        XCTAssertFalse(fileExists(filename), "a bounded claim lets the orphan go")
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "the dead claim is reaped too")
    }

    /// The rollback path (verify failed, insert failed) leaves neither file nor claim.
    func testFailedCaptureCleanupRemovesFileAndMarker() throws {
        let storage = CaptureImageStorage(directoryURL: captureDirectory)
        let filename = try XCTUnwrap(storage.writeJpeg(Data(repeating: 0x36, count: 64), captureId: "failed"))
        let marker = makeImageStore().inFlightMarkerURL(for: filename)
        XCTAssertTrue(fileExists(filename))
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))

        storage.delete(filename: filename)

        XCTAssertFalse(fileExists(filename))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "a rolled back capture keeps no claim")
    }

    // MARK: helpers

    private func makeDatabase() throws -> AppDatabase {
        let url = root.appendingPathComponent("db/aipose.db")
        return try AppDatabase(location: AppDatabaseLocation(url: url, kind: .freshInstall))
    }

    private func makeImageStore() -> PhotoImageStore {
        PhotoImageStore(directoryURL: captureDirectory)
    }

    /// Writes a real jpeg-sized file and backdates it past the sweep's in-flight guard.
    @discardableResult
    private func writeCapture(named filename: String, age: TimeInterval = 25 * 60 * 60) throws -> String {
        let url = captureDirectory.appendingPathComponent(filename)
        try Data(repeating: 0x11, count: 64).write(to: url)
        try backdate(url.lastPathComponent, by: age, in: captureDirectory)
        return filename
    }

    private func backdate(_ filename: String, by age: TimeInterval, in directory: URL) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-age)],
            ofItemAtPath: directory.appendingPathComponent(filename).path
        )
    }

    private func fileExists(_ imagePath: String) -> Bool {
        let url = imagePath.hasPrefix("/")
            ? URL(fileURLWithPath: imagePath)
            : captureDirectory.appendingPathComponent(imagePath)
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func remainingCount(_ database: AppDatabase) async throws -> Int {
        try await PhotoRepository(database: database).all().count
    }

    private func insertPhoto(imagePath: String, into database: AppDatabase) async throws -> Int64 {
        try await PhotoRepository(database: database, imageStore: makeImageStore()).insert(
            PhotoRecord(
                id: nil,
                imagePath: imagePath,
                poseId: nil,
                poseName: "Photo",
                createdAt: "1700000000000",
                isFavorite: 0
            )
        )
    }
}
