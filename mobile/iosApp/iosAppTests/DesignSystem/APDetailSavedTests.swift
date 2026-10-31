import SwiftUI
import XCTest
@testable import iosApp

/// S2 surfaces: the Saved row list, the detail's tags/copy, and the rendered proof that an empty
/// Search page keeps its paging footer (the Sol Low from S1).
final class APDetailSavedTests: XCTestCase {
    private func pose(_ id: String, category: String, saved: Bool = true) -> NativePose {
        NativePose(
            id: id,
            name: "Pose \(id)",
            category: category,
            imageURL: nil,
            instructions: ["Stand a step away from the window."],
            isSaved: saved
        )
    }

    // MARK: - Pure copy / tags

    func testSavedCountCopyIsSingularAndPlural() {
        XCTAssertEqual(SavedCountCopy.label(0), "0 poses")
        XCTAssertEqual(SavedCountCopy.label(1), "1 pose")
        XCTAssertEqual(SavedCountCopy.label(5), "5 poses")
    }

    func testSavedRowKeepsTheGridIdentifiersItReplaced() {
        // The list used to be the shared grid; the E2E lane still targets those two ids.
        let rows = APGridLayout.columns(for: .large)
        XCTAssertEqual(rows, 2, "the grid stays 2-up elsewhere; this only pins the identifier contract")
        XCTAssertEqual(APSavedIdentifiers.row(index: 0, poseID: "abc"), "poses.first-card")
        XCTAssertEqual(APSavedIdentifiers.row(index: 3, poseID: "abc"), "poses.card.abc")
    }

    func testDetailTagsUseThePoseCategoryAndDropBlankOnes() {
        XCTAssertEqual(PoseDetailTags.chips(for: pose("1", category: "Standing")), ["Standing"])
        XCTAssertEqual(PoseDetailTags.chips(for: pose("2", category: "  Indoor  ")), ["Indoor"])
        XCTAssertEqual(PoseDetailTags.chips(for: pose("3", category: "   ")), [])
        XCTAssertEqual(PoseDetailTags.stepText("  Turn your shoulders.  "), "Turn your shoulders.")
    }

    // MARK: - Rendered: Saved rows

    @MainActor func testSavedRowPaintsItsUnsaveTargetAsASelectedSurface() {
        let probe = APViewProbe(
            savedRowCanvas(pose: pose("1", category: "Standing")),
            size: CGSize(width: 393, height: 140)
        )
        defer { probe.tearDown() }
        let painted = probe.capture()

        // The unsave control is a 44 pt `selectedBackground` square on the row's trailing edge.
        guard let control = largestRegion(of: 0xFAE0E7, in: painted) else {
            return XCTFail("the unsave control was not painted in selectedBackground")
        }
        XCTAssertGreaterThanOrEqual(control.height, 40, "the unsave target must be ~44 pt tall")
        XCTAssertGreaterThanOrEqual(control.width, 40, "the unsave target must be ~44 pt wide")
        XCTAssertGreaterThan(control.minX, painted.width / 2, "the unsave control sits on the trailing edge")
    }

    @MainActor private func savedRowCanvas(pose: NativePose) -> some View {
        ZStack {
            Color(hex: 0xFFFFFF)
            APSavedPoseRow(pose: pose, isEnabled: true)
        }
        .frame(width: 393, height: 140)
    }

    // MARK: - Rendered: the empty Search page keeps its footer (Sol Low)

    @MainActor func testEmptySearchPageKeepsItsPagingFooter() {
        let model = PosesViewModel(service: APEmptyPoseService())
        model.state = .empty
        // An empty page with a failed next window: the footer must still offer Retry.
        model.setPagingForTesting(error: "offline", hasMore: true, remainingAutoFetches: 0)

        // Render the real panel (empty state + footer) the screen mounts.
        let panel = APViewProbe(
            APSearchStatePanel(
                model: model,
                presentation: .empty,
                emptyTitle: "No poses match",
                emptyMessage: "Try a different pose name.",
                emptyActionTitle: "Clear search",
                emptyIdentifier: "search-empty-banner"
            ),
            size: CGSize(width: 393, height: 560)
        )
        defer { panel.tearDown() }
        let painted = panel.capture()

        // The paging footer's failed row is a full-width `errorSurface` band under the panel copy.
        let footerRows = rowsSpanned(by: 0xFFF4F5, in: painted, minimumWidth: 200)
        XCTAssertFalse(
            footerRows.isEmpty,
            "an empty page with more rows behind it must keep the footer's retry row on screen"
        )
    }

    @MainActor func testEmptySearchPageKeepsItsLoadMoreWhenAutoFetchesAreSpent() {
        let model = PosesViewModel(service: APEmptyPoseService())
        model.state = .empty
        model.setPagingForTesting(error: nil, hasMore: true, remainingAutoFetches: 0)

        let panel = APViewProbe(
            APSearchStatePanel(
                model: model,
                presentation: .empty,
                emptyTitle: "No poses match",
                emptyMessage: "Try a different pose name.",
                emptyActionTitle: "Clear search"
            ),
            size: CGSize(width: 393, height: 620)
        )
        defer { panel.tearDown() }
        let painted = panel.capture()

        // The Load more button is a wide `controlFill` pill below the empty copy.
        XCTAssertFalse(
            rowsSpanned(by: 0xECE5D8, in: painted, minimumWidth: 200).isEmpty,
            "with the automatic fetches spent, the empty page must offer the explicit Load more"
        )
    }

    // MARK: - Helpers

    private struct Region {
        let minX: Int
        let maxX: Int
        let minY: Int
        let maxY: Int
        var width: Int { maxX - minX + 1 }
        var height: Int { maxY - minY + 1 }
    }

    /// The bounding box of every pixel painting `hex` (tolerance absorbs the renderer's rounding).
    private func largestRegion(of hex: UInt32, in bitmap: APBitmap, tolerance: Int = 6) -> Region? {
        let target = (red: Int((hex >> 16) & 0xFF), green: Int((hex >> 8) & 0xFF), blue: Int(hex & 0xFF))
        var minX = Int.max
        var maxX = Int.min
        var minY = Int.max
        var maxY = Int.min
        for y in 0..<bitmap.height {
            for x in 0..<bitmap.width {
                guard let pixel = bitmap.color(x: x, y: y), pixel.alpha > 200 else { continue }
                let matches = abs(pixel.red - target.red) <= tolerance
                    && abs(pixel.green - target.green) <= tolerance
                    && abs(pixel.blue - target.blue) <= tolerance
                guard matches else { continue }
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard minX <= maxX else { return nil }
        return Region(minX: minX, maxX: maxX, minY: minY, maxY: maxY)
    }

    /// Rows where `hex` paints a run at least `minimumWidth` wide — how a full-width band differs from
    /// a small tile of the same colour.
    private func rowsSpanned(by hex: UInt32, in bitmap: APBitmap, minimumWidth: Int, tolerance: Int = 8) -> [Int] {
        let target = (red: Int((hex >> 16) & 0xFF), green: Int((hex >> 8) & 0xFF), blue: Int(hex & 0xFF))
        var rows: [Int] = []
        for y in 0..<bitmap.height {
            var left: Int?
            var right: Int?
            for x in 0..<bitmap.width {
                guard let pixel = bitmap.color(x: x, y: y), pixel.alpha > 200 else { continue }
                let matches = abs(pixel.red - target.red) <= tolerance
                    && abs(pixel.green - target.green) <= tolerance
                    && abs(pixel.blue - target.blue) <= tolerance
                guard matches else { continue }
                left = min(left ?? x, x)
                right = max(right ?? x, x)
            }
            if let left, let right, right - left + 1 >= minimumWidth {
                rows.append(y)
            }
        }
        return rows
    }
}

/// A catalogue with no rows: the empty page the footer test drives.
private struct APEmptyPoseService: PoseServing {
    func poses(query: String?) async throws -> [NativePose] { [] }
    func pose(id: String) async throws -> NativePose { throw PoseAdapterError.poseNotFound(id) }
}
