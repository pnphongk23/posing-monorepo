import SwiftUI
import UIKit
import XCTest
@testable import iosApp

/// The Saved surface (packet S4): F6 paging on the row list, and the F4 empty / signed-out panels as
/// the Saved screen mounts them.
///
/// Everything asserted about what a screen *draws* goes through `APViewProbe`, which renders the view
/// into a real window and reads its pixels — the accessibility tree of a hosted SwiftUI view is empty,
/// so a pixel band is the only honest evidence that a control or a glyph was painted.
final class APSavedListTests: XCTestCase {
    // MARK: - F6: one paging ask per page

    @MainActor func testNearEndFiresOncePerPage() {
        // The rule first: the last four rows are one opportunity, not four.
        XCTAssertTrue(APNearEndRule.isNearEnd(index: 16, count: 20))
        XCTAssertFalse(APNearEndRule.isNearEnd(index: 15, count: 20))
        XCTAssertFalse(APNearEndRule.isNearEnd(index: 0, count: 0), "an empty list has no end to reach")

        let firstPage = APNearEndRule.opportunity(nextOffset: 20, completedAttempts: 0)
        XCTAssertTrue(APNearEndRule.shouldTrigger(
            index: 19, count: 20, opportunity: firstPage, lastOpportunity: nil, canPage: true
        ))
        for index in 16...19 {
            XCTAssertFalse(
                APNearEndRule.shouldTrigger(
                    index: index, count: 20, opportunity: firstPage, lastOpportunity: firstPage, canPage: true
                ),
                "row \(index) of the same page must not be a second ask"
            )
        }
        let secondPage = APNearEndRule.opportunity(nextOffset: 40, completedAttempts: 1)
        XCTAssertNotEqual(firstPage, secondPage, "a settled page moves the opportunity")
        XCTAssertTrue(
            APNearEndRule.shouldTrigger(
                index: 18, count: 20, opportunity: secondPage, lastOpportunity: firstPage, canPage: true
            ),
            "a page that settled re-arms the trigger for the next one"
        )
        XCTAssertFalse(
            APNearEndRule.shouldTrigger(
                index: 19, count: 20, opportunity: secondPage, lastOpportunity: firstPage, canPage: false
            ),
            "a failed page belongs to the footer's Retry, not to a row re-appearing"
        )

        // Then the wiring: five rows, four of them inside the near-end band. The bug this replaces
        // asked once per row (four asks for one page).
        let firstPageRows = (1...3).map { savedPose("s\($0)") }
        let model = PosesViewModel(service: SavedListPoseService(rows: firstPageRows))
        model.state = .loaded(firstPageRows)
        // Nothing owed, so the shared footer stays quiet and the rows own the trigger.
        model.setPagingForTesting(hasMore: false)

        let asks = AskCounter()
        let probe = APViewProbe(
            APSavedList(poses: firstPageRows, model: model, onNearEnd: { asks.count += 1 }),
            size: CGSize(width: 393, height: 620)
        )
        defer { probe.tearDown() }
        probe.settle()
        XCTAssertEqual(asks.count, 1, "three near-end rows are one page, not three asks")

        // The next window lands: its rows appear under a new cursor and the gate asks exactly once
        // more — once per page, not once per list.
        let withSecondPage = firstPageRows + (4...6).map { savedPose("s\($0)") }
        model.state = .loaded(withSecondPage)
        model.setPagingForTesting(hasMore: false, nextOffset: 3)
        probe.render(APSavedList(poses: withSecondPage, model: model, onNearEnd: { asks.count += 1 }))
        XCTAssertEqual(asks.count, 2, "the page that landed is a new opportunity, and only one")
    }

    // MARK: - F6: a failed page is a compact retry

    @MainActor func testPagingFailureShowsCompactRetry() {
        let rows = (1...3).map { savedPose("p\($0)") }
        let model = PosesViewModel(service: SavedListPoseService(rows: rows))
        model.state = .loaded(rows)
        model.setPagingForTesting(
            error: SavedMutationCopy.offline,
            hasMore: true,
            remainingAutoFetches: 0
        )

        let asks = AskCounter()
        let probe = APViewProbe(
            APSavedList(poses: rows, model: model, onNearEnd: { asks.count += 1 }),
            size: CGSize(width: 393, height: 560)
        )
        defer { probe.tearDown() }
        let painted = probe.capture()

        // The footer's failed row is a full-width `errorSurface` band under the card. The tolerance is
        // tight on purpose: the screen `background` is only a few steps away from `errorSurface`.
        let retryBands = bands(of: 0xFFF4F5, in: painted, tolerance: 3).filter { $0.widestRun >= 200 }
        guard let retry = retryBands.first else {
            return XCTFail("a failed page must keep its retry on screen while the rows stay visible")
        }
        XCTAssertEqual(retryBands.count, 1, "one failed page is one retry row")
        XCTAssertLessThanOrEqual(
            retry.height, 96,
            "the failed page is a compact retry row, not a full-screen state panel"
        )
        XCTAssertGreaterThan(
            retry.minY, painted.height / 3,
            "the retry belongs under the rows it failed to extend"
        )
        XCTAssertEqual(
            asks.count, 0,
            "a failed page waits for the footer's Retry; a row re-appearing must not re-ask on its own"
        )
    }

    // MARK: - F4: the saved-empty panel is one accent circle

    @MainActor func testSavedEmptyUsesSingleCircleGlyph() {
        // The panel SavedPosesScreen mounts on an empty collection, with its real copy.
        let panel = APEmptyStateView(
            title: PoseResultsStateCopy.savedEmptyTitle,
            message: PoseResultsStateCopy.savedEmptyMessage,
            actionTitle: PoseResultsStateCopy.browseCommunityActionTitle,
            action: {},
            style: .plain,
            glyph: "bookmark"
        )
        let probe = APViewProbe(panel, size: CGSize(width: 393, height: 560))
        defer { probe.tearDown() }
        let painted = probe.capture()

        let circles = bands(of: 0xFAE0E7, in: painted)
        XCTAssertEqual(
            circles.count, 1,
            "F4 is one clean icon: a stacked or offset second tile would paint a second band"
        )
        guard let circle = circles.first else { return }
        XCTAssertEqual(Double(circle.height), 72, accuracy: 5, "the empty glyph sits on the shared 72 pt circle")
        XCTAssertEqual(
            Double(circle.width), 72, accuracy: 5,
            "a 72 pt circle, not a wide tile (its own glyph splits the middle row, so the band's extent is the measure)"
        )
        XCTAssertEqual(
            Double(circle.minX + circle.maxX) / 2, Double(painted.width) / 2, accuracy: 3,
            "the glyph circle is centred"
        )

        // The glyph itself is painted in the accent ink inside that one circle.
        XCTAssertTrue(
            bands(of: 0x8C3350, in: painted, rows: circle.minY..<(circle.maxY + 1)).isEmpty == false,
            "the circle must carry its glyph"
        )
    }

    // MARK: - The signed-out gate

    @MainActor func testSignedOutShowsSignInGate() async {
        let previous = AppConfig.shared.isAccountFeatureEnabled
        AppConfig.shared.applyAccountFeatureEnabled(true)
        await ServiceLocator.sessionBoundary.signOut()
        defer { AppConfig.shared.applyAccountFeatureEnabled(previous) }

        XCTAssertTrue(AppConfig.shared.isAccountFeatureEnabled, "the Saved surface is flag-gated")
        let hasSession = await ServiceLocator.sessionBoundary.hasStoredSession()
        XCTAssertFalse(hasSession, "the gate is the signed-out branch")

        // Rows in the model on purpose: if the screen fell through to the list, the gate's panel is
        // what would be missing from the render.
        let rows = (1...2).map { savedPose("g\($0)") }
        let model = PosesViewModel(service: SavedListPoseService(rows: rows))
        model.state = .loaded(rows)

        let probe = APViewProbe(SavedPosesScreen(model: model), size: CGSize(width: 393, height: 700))
        defer { probe.tearDown() }
        var painted = probe.capture()
        // `SessionPresenceModel` starts on the screen's `.task`, so wait for the gate instead of
        // assuming one settle is enough.
        var circles = bands(of: 0xFAE0E7, in: painted)
        for _ in 0..<60 where circles.isEmpty {
            try? await Task.sleep(nanoseconds: 20_000_000)
            probe.settle()
            painted = probe.capture()
            circles = bands(of: 0xFAE0E7, in: painted)
        }

        XCTAssertEqual(circles.count, 1, "the signed-out Saved screen shows the one shared state panel")
        guard let circle = circles.first else { return }
        XCTAssertEqual(Double(circle.height), 72, accuracy: 5, "the sign-in gate uses the F4 circle")

        // The gate's action is the panel's wide secondary control under the copy.
        let actions = bands(of: 0xECE5D8, in: painted)
            .filter { $0.minY > circle.maxY && $0.widestRun >= 200 }
        guard let action = actions.first else {
            return XCTFail("the sign-in gate must offer its Sign in action")
        }
        XCTAssertLessThanOrEqual(action.height, 60, "the gate's action is one control, not a second panel")
    }

    // MARK: - Fixtures and helpers

    private func savedPose(_ id: String) -> NativePose {
        NativePose(
            id: id,
            name: "Pose \(id)",
            category: "Standing",
            imageURL: nil,
            instructions: ["Stand a step away from the window."],
            isSaved: true
        )
    }

    private final class AskCounter: @unchecked Sendable {
        var count = 0
    }

    /// One contiguous row band painting a colour: how a circle differs from a tile, and how a compact
    /// row differs from a panel.
    private struct PaintBand {
        let minY: Int
        let maxY: Int
        let minX: Int
        let maxX: Int
        let widestRun: Int

        var height: Int { maxY - minY + 1 }
        var width: Int { maxX - minX + 1 }
    }

    /// Consecutive rows that paint `hex` at least once, merged into one band each.
    private func bands(
        of hex: UInt32,
        in bitmap: APBitmap,
        rows: Range<Int>? = nil,
        tolerance: Int = 6
    ) -> [PaintBand] {
        let target = (red: Int((hex >> 16) & 0xFF), green: Int((hex >> 8) & 0xFF), blue: Int(hex & 0xFF))
        func matches(_ x: Int, _ y: Int) -> Bool {
            guard let pixel = bitmap.color(x: x, y: y), pixel.alpha > 200 else { return false }
            return abs(pixel.red - target.red) <= tolerance
                && abs(pixel.green - target.green) <= tolerance
                && abs(pixel.blue - target.blue) <= tolerance
        }

        var result: [PaintBand] = []
        var current: (minY: Int, maxY: Int, minX: Int, maxX: Int, widestRun: Int)?
        for y in (rows ?? 0..<bitmap.height) where y >= 0 && y < bitmap.height {
            var run = 0
            var widestRun = 0
            var minX = Int.max
            var maxX = Int.min
            for x in 0..<bitmap.width {
                guard matches(x, y) else {
                    run = 0
                    continue
                }
                run += 1
                widestRun = max(widestRun, run)
                minX = min(minX, x)
                maxX = max(maxX, x)
            }
            guard widestRun > 0 else {
                if let finished = current { result.append(PaintBand(
                    minY: finished.minY, maxY: finished.maxY,
                    minX: finished.minX, maxX: finished.maxX, widestRun: finished.widestRun
                )) }
                current = nil
                continue
            }
            if var open = current {
                open.maxY = y
                open.minX = min(open.minX, minX)
                open.maxX = max(open.maxX, maxX)
                open.widestRun = max(open.widestRun, widestRun)
                current = open
            } else {
                current = (minY: y, maxY: y, minX: minX, maxX: maxX, widestRun: widestRun)
            }
        }
        if let finished = current {
            result.append(PaintBand(
                minY: finished.minY, maxY: finished.maxY,
                minX: finished.minX, maxX: finished.maxX, widestRun: finished.widestRun
            ))
        }
        return result
    }
}

/// The catalogue the Saved list is drawn from. The rows are handed to the view directly, so the
/// fixture only has to answer the model's first-window read.
private struct SavedListPoseService: PoseServing {
    let rows: [NativePose]

    func poses(query: String?) async throws -> [NativePose] { rows }

    func posesPage(query: String?, offset: Int, limit: Int) async throws -> PosePage {
        let start = min(max(0, offset), rows.count)
        let window = Array(rows[start..<min(rows.count, start + limit)])
        return PosePage(poses: window, hasMore: start + window.count < rows.count, consumed: window.count)
    }

    func pose(id: String) async throws -> NativePose {
        guard let match = rows.first(where: { $0.id == id }) else {
            throw PoseAdapterError.poseNotFound(id)
        }
        return match
    }
}
