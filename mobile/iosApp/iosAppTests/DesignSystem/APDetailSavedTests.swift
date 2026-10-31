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

    // MARK: - Saved lifecycle

    @MainActor func testEnteringSavedSelectsTheSavedFilterAndLoadsIt() async {
        // The S2 defect: with an empty Community model the screen never selected `.saved` nor loaded,
        // so it showed "no saved poses" without ever asking the server.
        let service = SavedFilterSpyService(rows: [])
        let model = PosesViewModel(service: service, bookmarkService: StubSavedBookmarkService())
        model.filter = .community
        await model.load()
        XCTAssertEqual(model.state.rows.count, 0)

        await APSavedEntry.prepare(model: model)

        XCTAssertEqual(model.filter, .saved, "entering Saved must select the saved collection")
        XCTAssertEqual(
            service.posesCalls, 2,
            "entering Saved must load the saved collection, not just switch the chip"
        )
    }

    func testUnsaveFailureBannerIsOnlyShownForARealError() {
        XCTAssertNil(APSavedChrome.unsaveFailure(nil))
        XCTAssertNil(APSavedChrome.unsaveFailure("   "))
        let banner = APSavedChrome.unsaveFailure("You're offline. Try again.")
        XCTAssertEqual(banner?.title, "Couldn't update this pose")
        XCTAssertEqual(banner?.message, "You're offline. Try again.")
        XCTAssertEqual(banner?.actionTitle, "Dismiss")
    }

    // MARK: - Rendered: the illustrated gate

    @MainActor func testIllustratedGatePaintsAnAccentCircleAndAConstrainedAction() {
        let probe = APViewProbe(
            APIllustratedStatePanel(
                title: "Sign in to view your saved poses",
                message: "Your saved poses are tied to your account.",
                glyph: "bookmark",
                actionTitle: "Sign in",
                actionKind: .primary,
                action: {}
            ),
            size: CGSize(width: 393, height: 560)
        )
        defer { probe.tearDown() }
        let painted = probe.capture()

        // The circle is the first accent artwork down the panel; the action button comes after it.
        let firstAccentRow = (0..<painted.height).first { y in
            (0..<painted.width).contains { x in
                guard let pixel = painted.color(x: x, y: y) else { return false }
                return abs(pixel.red - 232) <= 6 && abs(pixel.green - 156) <= 6 && abs(pixel.blue - 174) <= 6
            }
        }
        guard let top = firstAccentRow,
              let circle = largestRegion(of: 0xE89CAE, in: painted, rows: top..<(top + 140)) else {
            return XCTFail("the illustrated panel must paint its accent circle")
        }
        XCTAssertGreaterThanOrEqual(circle.width, 90, "the accent circle is the illustration")
        XCTAssertEqual(circle.width, circle.height, accuracy: 3, "the illustration is a circle")
        XCTAssertEqual(CGFloat(circle.minX) + CGFloat(circle.width) / 2, 393 / 2, accuracy: 6,
                       "the illustration is centred")

        // The action is a real button of constrained width, not a chip hugging its label.
        let narrowestAction = painted.width / 2
        XCTAssertLessThanOrEqual(
            circle.width, narrowestAction,
            "sanity: the illustration is narrower than half the panel"
        )
        let buttonRows = rowsSpanned(by: 0xE89CAE, in: painted, minimumWidth: 150)
        XCTAssertFalse(buttonRows.isEmpty, "the panel's action must paint a wide accent button")
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
    private func largestRegion(
        of hex: UInt32,
        in bitmap: APBitmap,
        rows: Range<Int>? = nil,
        tolerance: Int = 6
    ) -> Region? {
        let target = (red: Int((hex >> 16) & 0xFF), green: Int((hex >> 8) & 0xFF), blue: Int(hex & 0xFF))
        var minX = Int.max
        var maxX = Int.min
        var minY = Int.max
        var maxY = Int.min
        let band = rows ?? 0..<bitmap.height
        for y in band where y < bitmap.height {
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

/// Counts catalogue reads, so "entering Saved loads the saved collection" is observable rather than
/// assumed.
private final class SavedFilterSpyService: PoseServing, @unchecked Sendable {
    let rows: [NativePose]
    private(set) var posesCalls = 0

    init(rows: [NativePose]) {
        self.rows = rows
    }

    func poses(query: String?) async throws -> [NativePose] {
        posesCalls += 1
        return rows
    }

    func pose(id: String) async throws -> NativePose {
        guard let match = rows.first(where: { $0.id == id }) else { throw PoseAdapterError.poseNotFound(id) }
        return match
    }
}

/// A bookmark service that always succeeds: the entry test only cares which collection was read.
private struct StubSavedBookmarkService: PoseBookmarkServing {
    func savePose(poseId: String) async throws {}
    func unsavePose(poseId: String) async throws {}
}
