import SwiftUI
import XCTest
@testable import iosApp

/// S1.5 shell rules: the shared page header, the home header composition, the More menu rows, the
/// infinite-scroll footer, and the appearance preference. Each assertion can fail.
final class APShellTests: XCTestCase {
    // MARK: - Page header (F1)

    @MainActor func testPageHeaderIsOneRowWithACentredTitle() throws {
        let probe = APViewProbe(
            APPageHeader(title: "Saved", onBack: {}),
            size: CGSize(width: 393, height: 120)
        )
        defer { probe.tearDown() }
        let painted = probe.capture()

        // The back control (controlFill) and the title (dark ink) share one horizontal band: their
        // vertical centres sit within a few points of each other.
        let controlRows = rowsPainted(with: 0xECE5D8, in: painted)
        let inkRows = darkRows(in: painted)
        let controlTop = try XCTUnwrap(controlRows.first, "the header must paint its back control")
        let controlBottom = try XCTUnwrap(controlRows.last)
        let inkTop = try XCTUnwrap(inkRows.first, "the header must paint its title")
        let inkBottom = try XCTUnwrap(inkRows.last)

        let inkCentre = (Double(inkTop) + Double(inkBottom)) / 2
        let controlCentre = (Double(controlTop) + Double(controlBottom)) / 2
        XCTAssertEqual(inkCentre, controlCentre, accuracy: 8, "the title is vertically centred with the back button")
        XCTAssertLessThanOrEqual(
            inkBottom, controlBottom + 12,
            "the title stays on the back control's row instead of dropping below it"
        )
    }

    // MARK: - Home header (F7)

    func testAddPoseIsShownOnlyWhileExtractionIsEnabled() {
        XCTAssertTrue(APHomeHeader.showsAddPose(isExtractPoseEnabled: true))
        XCTAssertFalse(APHomeHeader.showsAddPose(isExtractPoseEnabled: false))
    }

    // MARK: - More menu (F8)

    func testMoreMenuRowsCarryNoSubtitleCounts() {
        let rows = APMoreMenuSpec.rows(showsSaved: true, showsSettings: true)
        XCTAssertEqual(rows.map(\.title), ["Jobs", "Saved", "Settings"])
        XCTAssertEqual(rows.last?.systemImage, "gearshape", "Settings is the gear row")

        // Only the Jobs badge may carry a number: no row title carries one.
        for row in rows {
            XCTAssertFalse(
                row.title.contains(where: \.isNumber),
                "\(row.title) must not carry a count"
            )
        }
        XCTAssertEqual(
            APMoreMenuSpec.rows(showsSaved: false, showsSettings: true).map(\.title),
            ["Jobs", "Settings"],
            "Saved is gated by the account flag"
        )
    }

    // MARK: - Infinite scroll (F6)

    func testFooterAutoLoadsInsteadOfAskingForATap() {
        XCTAssertTrue(APPagingFooterRule.autoLoads(.loading))
        XCTAssertTrue(APPagingFooterRule.autoLoads(.loadMore), "a list with rows behind it keeps loading")
        XCTAssertFalse(APPagingFooterRule.autoLoads(.failed), "a failure waits for the retry row")
        XCTAssertFalse(APPagingFooterRule.autoLoads(.end))
        XCTAssertFalse(APPagingFooterRule.autoLoads(.hidden))
    }

    // MARK: - Footer lifecycle (Sol P1)

    @MainActor func testSlowPageIsNotCancelledByItsOwnTrigger() async {
        // The regression: keying the trigger on `isLoading` cancelled the in-flight request as soon as
        // it set the flag, so a slow page turned into a retry error.
        let service = SuspendedPageSpy()
        let model = PosesViewModel(service: service)
        model.state = .loaded([Self.row("1")])
        model.setPagingForTesting(error: nil, hasMore: true, remainingAutoFetches: 0)

        let probe = APViewProbe(APPagingFooter(model: model), size: CGSize(width: 393, height: 220))
        defer { probe.tearDown() }

        for _ in 0..<50 {
            await Task.yield()
            if service.pageCalls == 1 { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(service.pageCalls, 1, "the footer starts one page request")
        XCTAssertFalse(service.wasCancelled, "the trigger must not cancel the request it started")

        service.release()
        for _ in 0..<50 {
            await Task.yield()
            if model.state.rows.count == 2 { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(model.state.rows.count, 2, "the slow page still completes and appends its rows")
        XCTAssertFalse(service.wasCancelled, "the request survives to completion")
    }

    @MainActor func testPageDiscardedByACursorMoveIsRequestedAgainAtTheCorrectedOffset() async {
        // Unsaving a visible row while the next page is in flight moves the cursor: the pending window
        // is discarded, so the footer must ask again for the corrected offset instead of stalling.
        let service = OffsetRecordingSpy()
        let model = PosesViewModel(service: service)
        model.state = .loaded([Self.row("1"), Self.row("2")])
        // Budget left, so the phase stays `.loading` across the discard: nothing but the completion
        // token can re-fire the trigger then.
        model.setPagingForTesting(error: nil, hasMore: true, remainingAutoFetches: 3, nextOffset: 20)

        let probe = APViewProbe(APPagingFooter(model: model), size: CGSize(width: 393, height: 220))
        defer { probe.tearDown() }
        for _ in 0..<50 {
            await Task.yield()
            if service.offsets.count == 1 { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(service.offsets, [20], "the first page starts at the cursor")

        // The removal lands while the page is still in flight.
        model.setPagingForTesting(error: nil, hasMore: true, remainingAutoFetches: 3, isLoading: true, cursorMoved: true)
        service.release()
        for _ in 0..<60 {
            await Task.yield()
            if service.offsets.count >= 2 { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(
            service.offsets, [20, 19],
            "after a discarded page the footer re-asks for the corrected offset (one row up)"
        )
    }

    private static func row(_ id: String) -> NativePose {
        NativePose(id: id, name: "Pose \(id)", category: "Standing", imageURL: nil, instructions: [], isSaved: false)
    }

    // MARK: - Applied appearance + pinned bar geometry    // MARK: - Applied appearance + pinned bar geometry

    @MainActor func testChosenAppearanceResolvesTheSchemeItNames() {
        func backgroundLuminance(_ appearance: APAppearance) -> Int {
            let probe = APViewProbe(
                AP.Color.background
                    .ignoresSafeArea()
                    .preferredColorScheme(appearance.colorScheme)
                    .environment(\.colorScheme, appearance.colorScheme ?? .light),
                size: CGSize(width: 60, height: 60)
            )
            let painted = probe.capture()
            probe.tearDown()
            return painted.color(x: 30, y: 30)?.red ?? -1
        }
        XCTAssertGreaterThan(backgroundLuminance(.light), 200, "Light resolves the light canvas")
        XCTAssertLessThan(backgroundLuminance(.dark), 60, "Dark resolves the dark canvas")
    }

    func testPinnedBarUsesOneHeightForBothControls() {
        // Both the square Save and the primary action take their height from this one number.
        XCTAssertEqual(APBarMetrics.controlHeight(for: .large), 52)
        XCTAssertEqual(APBarMetrics.controlHeight(for: .xxxLarge), 52)
        XCTAssertEqual(APBarMetrics.controlHeight(for: .accessibility3), 72)
        XCTAssertEqual(APBarMetrics.controlHeight(for: .accessibility5), 72)
    }

    @MainActor func testPinnedBarFillsAreEqualHeightAtDefaultAndAX3() {
        let previous = AppConfig.shared.isAccountFeatureEnabled
        AppConfig.shared.applyAccountFeatureEnabled(true)
        defer { AppConfig.shared.applyAccountFeatureEnabled(previous) }

        for (size, expected) in [(DynamicTypeSize.large, APBarMetrics.controlHeight(for: .large)),
                                 (DynamicTypeSize.accessibility3, APBarMetrics.controlHeight(for: .accessibility3))] {
            let pose = Self.row("bar-pose")
            let model = PosesViewModel(service: ShellPoseService(pose: pose), bookmarkService: ShellBookmarkStub())
            model.state = .loaded([pose])
            let probe = APViewProbe(
                PoseDetailScreen(pose: pose, model: model, onTryPose: { _ in })
                    .environment(\.dynamicTypeSize, size),
                size: CGSize(width: 393, height: 852)
            )
            let painted = probe.capture()
            probe.tearDown()

            // The bar is the only place the two control fills appear in the bottom band; the pink
            // artwork is above it.
            let barBand = (painted.height - 170)..<painted.height
            let saveRows = rowsPainted(with: 0xECE5D8, in: painted).filter { barBand.contains($0) }
            let ctaRows = rowsPainted(with: 0xE89CAE, in: painted).filter { barBand.contains($0) }
            guard let saveTop = saveRows.first, let saveBottom = saveRows.last,
                  let ctaTop = ctaRows.first, let ctaBottom = ctaRows.last else {
                return XCTFail("both pinned controls must be painted at \(size)")
            }
            let saveHeight = Double(saveBottom - saveTop + 1)
            let ctaHeight = Double(ctaBottom - ctaTop + 1)
            XCTAssertEqual(saveHeight, ctaHeight, accuracy: 4, "the two fills are the same height at \(size)")
            XCTAssertEqual(saveHeight, Double(expected), accuracy: 6, "the fills are the shared bar height at \(size)")
        }
    }

    func testFooterTriggerChangesWhenADiscardedAttemptSettles() {
        // The stall: an unsave mid-flight moves the cursor, the pending window is discarded, and
        // nothing about phase/offset/rows changes at completion. Only the attempt token differs, so
        // only the token can re-fire the trigger.
        let before = APPagingFooterRule.triggerKey(phase: .loading, nextOffset: 19, rowCount: 2, completedAttempts: 4)
        let after = APPagingFooterRule.triggerKey(phase: .loading, nextOffset: 19, rowCount: 2, completedAttempts: 5)
        XCTAssertNotEqual(before, after, "a settled attempt must change the trigger identity")
        XCTAssertEqual(
            before,
            APPagingFooterRule.triggerKey(phase: .loading, nextOffset: 19, rowCount: 2, completedAttempts: 4),
            "the identity is stable while nothing settles"
        )
    }

    // MARK: - Pose detail: one Save, its gate and its visibility (S3)

    func testDetailExposesSingleSaveIdentifier() throws {
        // Two views carrying `poseDetail.saveButton` make Maestro tap an arbitrary one, so the source
        // itself is the contract: exactly one occurrence in the detail screen.
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("iosApp/Features/Poses/PosesFeature.swift"),
            encoding: .utf8
        )
        let occurrences = source.components(separatedBy: "\"poseDetail.saveButton\"").count - 1
        XCTAssertEqual(occurrences, 1, "exactly one view may carry poseDetail.saveButton")
        XCTAssertFalse(
            source.contains("private var saveControl"),
            "the dead inline Save control must not come back"
        )
    }

    func testSignedOutSaveAsksToSignInInsteadOfDoingNothing() {
        // NEW-21: the signed-out tap is a sign-in request, not a silent no-op.
        XCTAssertEqual(
            PoseDetailSaveGate.intent(hasStoredSession: false, hasBookmarkService: true, canSave: true, isSaving: false),
            .signIn
        )
        XCTAssertEqual(
            PoseDetailSaveGate.intent(hasStoredSession: true, hasBookmarkService: true, canSave: true, isSaving: false),
            .toggle
        )
        XCTAssertEqual(
            PoseDetailSaveGate.intent(hasStoredSession: true, hasBookmarkService: true, canSave: true, isSaving: true),
            .ignore,
            "a tap while a save is in flight is ignored, not queued"
        )
        XCTAssertEqual(
            PoseDetailSaveGate.intent(hasStoredSession: true, hasBookmarkService: false, canSave: true, isSaving: false),
            .ignore,
            "no bookmark service: nothing could confirm the save"
        )
        XCTAssertEqual(
            PoseDetailSaveGate.intent(hasStoredSession: true, hasBookmarkService: true, canSave: false, isSaving: false),
            .ignore,
            "a pose the server says is gone is not offered again"
        )
    }

    func testPrivateDetailOffersNoSaveControl() {
        // NEW-13: a private (Jobs / Add-pose) detail has no bookmark semantics, so no Save control.
        XCTAssertTrue(PoseDetailSaveVisibility.showsSaveControl(isAccountEnabled: true, isPrivate: false))
        XCTAssertFalse(PoseDetailSaveVisibility.showsSaveControl(isAccountEnabled: true, isPrivate: true))
        XCTAssertFalse(PoseDetailSaveVisibility.showsSaveControl(isAccountEnabled: false, isPrivate: false))
    }

    @MainActor func testPrivateDetailPaintsOnlyThePrimaryAction() {
        let previous = AppConfig.shared.isAccountFeatureEnabled
        AppConfig.shared.applyAccountFeatureEnabled(true)
        defer { AppConfig.shared.applyAccountFeatureEnabled(previous) }

        let pose = Self.row("private-pose")
        let model = PosesViewModel(service: ShellPoseService(pose: pose), bookmarkService: ShellBookmarkStub())
        model.state = .loaded([pose])
        let probe = APViewProbe(
            PoseDetailScreen(pose: pose, model: model, onTryPose: { _ in }, isPrivate: true),
            size: CGSize(width: 393, height: 852)
        )
        defer { probe.tearDown() }
        let painted = probe.capture()

        // Geometry, not colour: with a Save square beside it the CTA starts ~68 pt in; on a private
        // pose the primary action owns the bar and starts at the 16 pt inset.
        let barBand = (painted.height - 170)..<painted.height
        let ctaRows = rowsPainted(with: 0xE89CAE, in: painted).filter { barBand.contains($0) }
        guard let ctaTop = ctaRows.first, let ctaBottom = ctaRows.last else {
            return XCTFail("the primary action must be painted in the bar")
        }
        var leftEdge = Int.max
        for y in ctaTop...ctaBottom {
            for x in 0..<painted.width {
                guard let pixel = painted.color(x: x, y: y) else { continue }
                if abs(pixel.red - 232) <= 8 && abs(pixel.green - 156) <= 8 && abs(pixel.blue - 174) <= 8 {
                    leftEdge = min(leftEdge, x)
                }
            }
        }
        XCTAssertLessThanOrEqual(
            Double(leftEdge), 22,
            "a private pose must not paint a Save control: the primary action starts at the bar's inset"
        )
    }

    // MARK: - Saved failure copy (401 / 404 / offline)

    func testSavedFailuresKeepTheirActionableCopy() {
        XCTAssertEqual(
            SavedMutationCopy.text(for: PoseAPIError(code: "401", message: "Server error: 401")),
            "Please sign in again."
        )
        XCTAssertEqual(
            SavedMutationCopy.text(for: PoseAPIError(code: "NOT_FOUND", message: "Pose not found")),
            "This pose is no longer available."
        )
        XCTAssertEqual(
            SavedMutationCopy.text(for: URLError(.notConnectedToInternet)),
            "You're offline. Try again when connected."
        )
        XCTAssertEqual(
            SavedMutationCopy.text(for: APIClientError.httpStatus(401)),
            "Please sign in again."
        )
        XCTAssertEqual(
            SavedMutationCopy.text(for: APIClientError.httpStatus(404)),
            "This pose is no longer available."
        )
    }

    // MARK: - Shared-file requests from the Gallery lane

    @MainActor func testEmptyStateCarriesTheActionIdentifierItIsGiven() {
        // The identifier is what Maestro taps (`gallery.empty.openCameraButton`); the panel must keep
        // it on the action it renders, not swallow it.
        let panel = APEmptyStateView(
            title: "No photos yet",
            message: "Opening your photo library…",
            actionTitle: "Open Camera",
            action: {},
            style: .plain,
            glyph: "photo",
            actionIdentifier: "gallery.empty.openCameraButton"
        )
        XCTAssertEqual(panel.actionIdentifier, "gallery.empty.openCameraButton")
        let errorPanel = APErrorStateView(
            title: "Couldn't load",
            message: "Try again.",
            retry: {},
            style: .plain,
            actionIdentifier: "gallery.empty.retry"
        )
        XCTAssertEqual(errorPanel.actionIdentifier, "gallery.empty.retry")

        // And the panel still paints its action.
        let probe = APViewProbe(panel, size: CGSize(width: 393, height: 480))
        defer { probe.tearDown() }
        XCTAssertFalse(rowsPainted(with: 0xECE5D8, in: probe.capture()).isEmpty, "the action must paint")
    }

    func testAddPoseRequestOnlyOpensWhenNothingElseIsPresented() {
        XCTAssertTrue(APAddPoseSignal.shouldOpen(canExtract: true, isRouteOpen: false, isSearchOpen: false))
        XCTAssertFalse(APAddPoseSignal.shouldOpen(canExtract: false, isRouteOpen: false, isSearchOpen: false))
        XCTAssertFalse(APAddPoseSignal.shouldOpen(canExtract: true, isRouteOpen: true, isSearchOpen: false))
        XCTAssertFalse(APAddPoseSignal.shouldOpen(canExtract: true, isRouteOpen: false, isSearchOpen: true))
    }

    // MARK: - Helpers

    private func rowsPainted(with hex: UInt32, in bitmap: APBitmap, tolerance: Int = 6) -> [Int] {
        let target = (red: Int((hex >> 16) & 0xFF), green: Int((hex >> 8) & 0xFF), blue: Int(hex & 0xFF))
        return (0..<bitmap.height).filter { y in
            (0..<bitmap.width).contains { x in
                guard let pixel = bitmap.color(x: x, y: y), pixel.alpha > 200 else { return false }
                return abs(pixel.red - target.red) <= tolerance
                    && abs(pixel.green - target.green) <= tolerance
                    && abs(pixel.blue - target.blue) <= tolerance
            }
        }
    }

    /// Rows painting the title's dark ink on the right of the back control.
    private func darkRows(in bitmap: APBitmap) -> [Int] {
        (0..<bitmap.height).filter { y in
            (80..<bitmap.width).contains { x in
                guard let pixel = bitmap.color(x: x, y: y), pixel.alpha > 200 else { return false }
                return pixel.red < 80 && pixel.green < 80 && pixel.blue < 80
            }
        }
    }
}

/// A page request that only completes when the test releases it, and remembers cancellation.
private final class SuspendedPageSpy: PoseServing, @unchecked Sendable {
    private(set) var pageCalls = 0
    private(set) var wasCancelled = false
    private var continuation: CheckedContinuation<Void, Never>?
    private let lock = NSLock()

    func poses(query: String?) async throws -> [NativePose] { [] }

    func pose(id: String) async throws -> NativePose { throw PoseAdapterError.poseNotFound(id) }

    func posesPage(query: String?, offset: Int, limit: Int) async throws -> PosePage {
        pageCalls += 1
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                store(continuation)
            }
        } onCancel: {
            markCancelled()
        }
        let row = NativePose(id: "slow-\(pageCalls)", name: "Slow", category: "Standing", imageURL: nil, instructions: [], isSaved: false)
        return PosePage(poses: [row], hasMore: false, consumed: 1)
    }

    // Locking lives in synchronous helpers: `NSLock.lock()` is unavailable from an async context and
    // a lock must never be held across an `await`.
    private func store(_ continuation: CheckedContinuation<Void, Never>) {
        lock.withLock { self.continuation = continuation }
    }

    private func markCancelled() {
        lock.withLock { wasCancelled = true }
    }

    func release() {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            let pending = self.continuation
            self.continuation = nil
            return pending
        }
        continuation?.resume()
    }
}

/// Serves one pose from the catalogue *and* from `pose(id:)`, so the detail's availability check
/// passes and the pinned bar renders.
private struct ShellPoseService: PoseServing {
    let pose: NativePose
    func poses(query: String?) async throws -> [NativePose] { [pose] }
    func pose(id: String) async throws -> NativePose { pose }
}

/// A bookmark service that always succeeds (the bar geometry test only needs the control to render).
private struct ShellBookmarkStub: PoseBookmarkServing {
    func savePose(poseId: String) async throws {}
    func unsavePose(poseId: String) async throws {}
}

/// Records the offset of every page request and completes only when released.
private final class OffsetRecordingSpy: PoseServing, @unchecked Sendable {
    private(set) var offsets: [Int] = []
    private var continuation: CheckedContinuation<Void, Never>?
    private let lock = NSLock()

    func poses(query: String?) async throws -> [NativePose] { [] }

    func pose(id: String) async throws -> NativePose { throw PoseAdapterError.poseNotFound(id) }

    func posesPage(query: String?, offset: Int, limit: Int) async throws -> PosePage {
        record(offset)
        await withCheckedContinuation { continuation in
            store(continuation)
        }
        return PosePage(poses: [], hasMore: false, consumed: 0)
    }

    private func record(_ offset: Int) {
        lock.withLock { offsets.append(offset) }
    }

    private func store(_ continuation: CheckedContinuation<Void, Never>) {
        lock.withLock { self.continuation = continuation }
    }

    func release() {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            let pending = self.continuation
            self.continuation = nil
            return pending
        }
        continuation?.resume()
    }
}
