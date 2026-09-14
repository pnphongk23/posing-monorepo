import XCTest
import UIKit
@testable import iosApp

final class GalleryFeatureTests: XCTestCase {
    func testRelativeCapturePathResolvesAgainstStorageDirectory() {
        let storage = CaptureImageStorage()
        let filename = "capture_test-123.jpg"
        let url = GalleryMediaPath.fileURL(for: filename, captureStorage: storage)
        XCTAssertEqual(url.lastPathComponent, filename)
        XCTAssertTrue(url.path.contains("aipose"))
    }

    func testAbsolutePathIsPreserved() {
        let absolute = "/tmp/photo.jpg"
        let url = GalleryMediaPath.fileURL(for: absolute)
        XCTAssertEqual(url.path, absolute)
    }

    func testGalleryDateParserSupportsEpochMillisecondsAndRejectsInvalidValue() throws {
        let date = try XCTUnwrap(GalleryDateParser.date(from: "1700000000123"))
        XCTAssertEqual(date.timeIntervalSince1970, 1_700_000_000.123, accuracy: 0.001)
        XCTAssertNil(GalleryDateParser.date(from: "not-a-date"))
    }

    @MainActor func testGalleryLoadMapsRecordsToFileURLs() async {
        let fileURL = URL(fileURLWithPath: "/tmp/gallery-test.jpg")
        let store = StubGalleryFeatureStore(items: [
            GalleryItem(id: 1, fileURL: fileURL, createdAt: .now),
        ])
        let model = GalleryViewModel(store: store)
        await model.load()
        guard case .loaded(let items) = model.state else { return XCTFail("Expected loaded") }
        XCTAssertEqual(items.first?.fileURL, fileURL)
    }

    @MainActor func testGalleryLoadFailureSurfacesError() async {
        let model = GalleryViewModel(store: FailingGalleryStore())
        await model.load()
        guard case .failed(let message) = model.state else { return XCTFail("Expected failed") }
        XCTAssertFalse(message.isEmpty)
    }

    @MainActor func testGalleryIntegrationBlockedErrorMessage() async {
        let model = GalleryViewModel(store: IntegrationBlockedGalleryStore(reason: "simulator-db"))
        await model.load()
        guard case .failed(let message) = model.state else { return XCTFail("Expected failed") }
        XCTAssertTrue(message.contains("simulator-db"))
    }

    func testGalleryGridContractUsesDenseThreeColumnLayout() {
        XCTAssertEqual(GalleryGridContract.columnCount, 3)
        XCTAssertEqual(GalleryGridContract.spacing, 3)
        XCTAssertTrue((6...8).contains(GalleryGridContract.cornerRadius))
        XCTAssertGreaterThan(GalleryGridContract.dockInset, 0)
    }

    @MainActor func testGalleryDateSectionsGroupByDayNewestFirstWithoutLoss() async {
        let now = noonToday()
        let items = daySpreadItems(now: now)
        let model = GalleryViewModel(store: StubGalleryFeatureStore(items: items))
        await model.load()

        let sections = model.dateSections
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections.map(\.label), ["TODAY", "YESTERDAY"])
        XCTAssertEqual(sections.map(\.day), sections.map(\.day).sorted(by: >))
        XCTAssertEqual(sections[0].items.count, 4)
        XCTAssertEqual(sections[1].items.count, 2)
        let sectionIDs = sections.flatMap { $0.items.map(\.id) }
        XCTAssertEqual(Set(sectionIDs), Set(items.map(\.id)))
        XCTAssertEqual(sectionIDs.count, items.count)
    }

    @MainActor func testGalleryDateSectionsRespectTodayTimeFilter() async {
        let now = noonToday()
        let model = GalleryViewModel(store: StubGalleryFeatureStore(items: daySpreadItems(now: now)))
        await model.load()
        model.timeFilter = .today
        model.applyFilter()

        let sections = model.dateSections
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections.first?.label, "TODAY")
        XCTAssertEqual(sections.first?.items.count, 4)
    }

    /// 4 items on the current day + 2 items on the previous day, anchored at noon so the
    /// TODAY/YESTERDAY buckets stay stable across a midnight run boundary.
    private func daySpreadItems(now: Date? = nil) -> [GalleryItem] {
        let anchor = now ?? self.noonToday()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: anchor) ?? anchor
        let todayItems = (0..<4).map { offset in
            GalleryItem(
                id: Int64(offset),
                fileURL: URL(fileURLWithPath: "/tmp/gallery-today-\(offset).jpg"),
                createdAt: anchor.addingTimeInterval(Double(-600 * offset))
            )
        }
        let yesterdayItems = (0..<2).map { offset in
            GalleryItem(
                id: Int64(100 + offset),
                fileURL: URL(fileURLWithPath: "/tmp/gallery-yesterday-\(offset).jpg"),
                createdAt: yesterday.addingTimeInterval(Double(-600 * offset))
            )
        }
        return todayItems + yesterdayItems
    }

    private func noonToday() -> Date {
        let calendar = Calendar.current
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
    }

    func testGalleryDetailPresentationUsesCreamV2Contract() {
        XCTAssertEqual(GalleryDetailPresentation.styleVersion, 2)
    }

    /// The sheet must never be handed the Application Support path (see `GallerySharePreparation`).
    func testGallerySharePreparationCopiesIntoSystemTemporaryDirectory() throws {
        let sourceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GalleryShareTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceDirectory) }

        // Stands in for `Library/Application Support/aipose/capture_937783548-1.jpg`.
        let source = sourceDirectory.appendingPathComponent("capture_937783548-1.jpg")
        let bytes = Data((0..<4096).map { UInt8($0 % 251) })
        try bytes.write(to: source)

        let prepared = try GallerySharePreparation.prepare(source: source)
        defer { GallerySharePreparation.discard(prepared) }

        XCTAssertEqual(
            prepared.deletingLastPathComponent().resolvingSymlinksInPath(),
            FileManager.default.temporaryDirectory.resolvingSymlinksInPath(),
            "the share sheet must receive a URL in the system temporary directory"
        )
        XCTAssertEqual(prepared.lastPathComponent, "aipose-share-capture_937783548-1.jpg")
        XCTAssertEqual(try Data(contentsOf: prepared), bytes)
        XCTAssertNotEqual(prepared, source)
    }

    func testGallerySharePreparationReportsMissingSource() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("aipose-share-missing-\(UUID().uuidString).jpg")
        XCTAssertThrowsError(try GallerySharePreparation.prepare(source: missing)) { error in
            XCTAssertTrue(error is GallerySharePreparation.Failure)
        }
    }

    /// A grid cell draws ~117pt, i.e. ~352px @3x — not the 4032px of a 12MP capture.
    @MainActor func testGalleryGridDecodesAtCellSizeNotAtCaptureSize() {
        let cell = GalleryGridContract.cellDrawSize
        let expectedSide = (
            UIScreen.main.bounds.width
                - AIPoseSpacing.lg * 2
                - GalleryGridContract.spacing * CGFloat(GalleryGridContract.columnCount - 1)
        ) / CGFloat(GalleryGridContract.columnCount)
        XCTAssertEqual(cell.width, expectedSide, accuracy: 0.5)
        XCTAssertEqual(cell.width, cell.height, accuracy: 0.5)

        let cellPixels = AppImage.pixelSize(for: cell, scale: 3, contentMode: .fill)
        let processor = AppImage.downsample(points: cell, contentMode: .fill)
        XCTAssertGreaterThan(cellPixels.width, 200)
        XCTAssertLessThan(cellPixels.width, 600)
        XCTAssertTrue(processor.identifier.contains("Downsampling"), processor.identifier)

        // The full-screen viewer may decode larger, but still far below the source resolution.
        let viewerPixels = AppImage.pixelSize(for: FullScreenImageTarget.drawSize, scale: 3, contentMode: .fit)
        XCTAssertGreaterThan(viewerPixels.width, cellPixels.width)
        XCTAssertLessThan(viewerPixels.width, 4032)
    }

    /// The database open used to run in `GalleryStoreBootstrap.make()` on the main thread during
    /// `didFinishLaunching`. It must now happen once, off the main thread, on first use.
    @MainActor func testDeferredGalleryStoreResolvesBackendOnceOffMainThread() async throws {
        XCTAssertTrue(Thread.isMainThread, "the caller is the main thread; resolution must still not be")
        let observations = ThreadObservations()
        let store = DeferredGalleryStore(resolveBackend: {
            observations.record(isMainThread: Thread.isMainThread)
            return EmptyGalleryStore()
        })

        _ = try await store.photos()
        _ = try await store.photos()
        try await store.delete(id: 1)

        XCTAssertEqual(observations.callCount, 1, "the backend must be resolved exactly once")
        XCTAssertEqual(observations.mainThreadFlags, [false], "resolution must not block the main thread")
    }

    /// `make()` runs inside `didFinishLaunching` on the main thread, so it must no longer touch the
    /// filesystem at all (database open + migrations + fixture materialisation moved to first use).
    @MainActor func testGalleryStoreBootstrapMakeDoesNoBlockingWork() {
        let start = CFAbsoluteTimeGetCurrent()
        let bootstrap = GalleryStoreBootstrap.make()
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000

        XCTAssertTrue(bootstrap.store is DeferredGalleryStore)
        XCTAssertLessThan(elapsedMs, 5, "make() must not open the database or write fixture images")
        print("PERF galleryStoreBootstrap.make(ms) = \(String(format: "%.3f", elapsedMs)) (was: db open 3.1-9.3ms on main)")
    }
}

/// Lock-protected recorder for the off-main-thread assertion above.
private final class ThreadObservations: @unchecked Sendable {
    private let lock = NSLock()
    private var flags: [Bool] = []

    func record(isMainThread: Bool) {
        lock.lock()
        flags.append(isMainThread)
        lock.unlock()
    }

    var mainThreadFlags: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return flags
    }

    var callCount: Int { mainThreadFlags.count }
}

private final class StubGalleryFeatureStore: GalleryStoring, @unchecked Sendable {
    let items: [GalleryItem]
    init(items: [GalleryItem]) { self.items = items }
    func photos() async throws -> [GalleryItem] { items }
    func delete(id: Int64) async throws {}
}

private struct FailingGalleryStore: GalleryStoring {
    func photos() async throws -> [GalleryItem] { throw NSError(domain: "test", code: 2) }
    func delete(id: Int64) async throws {}
}

private struct IntegrationBlockedGalleryStore: GalleryStoring {
    let reason: String
    func photos() async throws -> [GalleryItem] { throw GalleryStoreIntegrationError.blocked(reason) }
    func delete(id: Int64) async throws { throw GalleryStoreIntegrationError.blocked(reason) }
}
