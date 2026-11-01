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

    // MARK: - Undo (06-board04)

    @MainActor func testConfirmedUnsaveOffersUndoThatReSavesThroughTheService() async {
        let service = UndoBookmarkService()
        let rows = [savedPose("a"), savedPose("b"), savedPose("c")]
        let model = PosesViewModel(service: SavedListPoseService(rows: rows), bookmarkService: service)
        model.filter = .saved
        model.state = .loaded(rows)

        // The row leaves the collection, and only because the server said so.
        let unsave = await model.toggleSaved(for: rows[1])
        XCTAssertEqual(unsave, .saved(false))
        XCTAssertEqual(service.unsaveCallCount, 1)
        XCTAssertEqual(model.state.rows.map(\.id), ["a", "c"], "a confirmed unsave removes the row")
        XCTAssertTrue(APSavedUndoRule.offersUndo(for: unsave), "a confirmed removal is what earns an Undo")

        let undo = APSavedUndo()
        undo.offer(rows[1], at: 1)

        // The board's snackbar: what left, and the one action that puts it back.
        let offered = APSavedSnackbarRule.resolve(
            removedPoseName: rows[1].name,
            canUndo: model.canSave(rows[1]),
            failure: model.bookmarkError
        )
        XCTAssertEqual(offered?.message, "Removed Pose b")
        XCTAssertEqual(offered?.actionTitle, "Undo")
        XCTAssertEqual(offered?.tone, .success)
        XCTAssertEqual(offered?.kind, .undo)

        let restored = await undo.undo(in: model)
        XCTAssertTrue(restored)
        XCTAssertEqual(service.saveCallCount, 1, "Undo sends the save to the server; it never flips the row locally")
        XCTAssertTrue(model.savedState(for: rows[1]), "the pose is saved again, as the server confirmed")
        XCTAssertEqual(
            model.state.rows.map(\.id), ["a", "b", "c"],
            "the row comes back where it was, not appended"
        )
        XCTAssertNil(undo.removal, "a restored row is no longer on offer")
        XCTAssertNil(model.bookmarkError)
    }

    @MainActor func testFailedUndoStaysTruthfulAndKeepsTheRetryOffer() async {
        let service = UndoBookmarkService()
        let rows = [savedPose("a"), savedPose("b")]
        let model = PosesViewModel(service: SavedListPoseService(rows: rows), bookmarkService: service)
        model.filter = .saved
        model.state = .loaded(rows)
        await model.toggleSaved(for: rows[1])

        let undo = APSavedUndo()
        undo.offer(rows[1], at: 1)
        service.saveError = URLError(.notConnectedToInternet)

        let restored = await undo.undo(in: model)
        XCTAssertFalse(restored)
        XCTAssertEqual(service.saveCallCount, 1)
        XCTAssertFalse(model.savedState(for: rows[1]), "nothing is shown as saved that the server did not confirm")
        XCTAssertEqual(
            model.state.rows.map(\.id), ["a"],
            "a failed undo adds no row: the collection still matches the server"
        )
        XCTAssertEqual(
            model.bookmarkError, SavedMutationCopy.offline,
            "the reason is the real one, not a generic line"
        )
        XCTAssertNotNil(undo.removal, "the copy says try again, so the action that can try again stays")

        let failed = APSavedSnackbarRule.resolve(
            removedPoseName: rows[1].name,
            canUndo: model.canSave(rows[1]),
            failure: model.bookmarkError
        )
        XCTAssertEqual(failed?.message, SavedMutationCopy.offline)
        XCTAssertEqual(failed?.tone, .error)
        XCTAssertEqual(failed?.actionTitle, "Undo")
        XCTAssertEqual(failed?.kind, .undo)

        // The retry the copy asks for actually works once the connection is back.
        service.saveError = nil
        model.bookmarkError = nil
        let retried = await undo.undo(in: model)
        XCTAssertTrue(retried)
        XCTAssertEqual(service.saveCallCount, 2)
        XCTAssertEqual(model.state.rows.map(\.id), ["a", "b"])
    }

    @MainActor func testFailedUnsaveOffersNoUndoAndKeepsThePlainFailureBar() async {
        let service = UndoBookmarkService()
        let rows = [savedPose("a")]
        let model = PosesViewModel(service: SavedListPoseService(rows: rows), bookmarkService: service)
        model.filter = .saved
        model.state = .loaded(rows)
        service.unsaveError = URLError(.notConnectedToInternet)

        let outcome = await model.toggleSaved(for: rows[0])
        XCTAssertEqual(outcome, .failed(SavedMutationCopy.offline))
        XCTAssertFalse(
            APSavedUndoRule.offersUndo(for: outcome),
            "an unsave that never happened has nothing to undo"
        )
        XCTAssertEqual(model.state.rows.map(\.id), ["a"], "the row stays: nothing left the collection")

        let spec = APSavedSnackbarRule.resolve(
            removedPoseName: nil,
            canUndo: false,
            failure: model.bookmarkError
        )
        XCTAssertEqual(spec?.message, SavedMutationCopy.offline)
        XCTAssertEqual(spec?.actionTitle, "Dismiss", "a failure with nothing to undo just goes away")
        XCTAssertEqual(spec?.kind, .dismiss)
    }

    // MARK: - Offline (06-board07)

    @MainActor func testOfflineAvailabilityComesFromTheCachedRows() {
        let cached = savedPose("a")
        let uncached = savedPose("b")

        XCTAssertTrue(
            APSavedOfflineMode.online.isAvailableOffline(uncached),
            "online every saved pose is available"
        )
        let offline = APSavedOfflineMode(isOffline: true, cachedPoseIDs: [cached.id])
        XCTAssertTrue(offline.isAvailableOffline(cached), "a row the cache holds is available offline")
        XCTAssertFalse(offline.isAvailableOffline(uncached), "a row the cache does not hold is not")
        XCTAssertFalse(
            APSavedOfflineMode(isOffline: true).isAvailableOffline(cached),
            "an offline screen with no catalog answer claims nothing"
        )

        // The label replaces the category line, and the category still shows when the row is fine.
        XCTAssertEqual(APSavedRowCopy.subtitle(for: uncached, isAvailableOffline: false), "Not saved offline")
        XCTAssertEqual(APSavedRowCopy.subtitle(for: cached, isAvailableOffline: true), "Standing")
        XCTAssertEqual(APSavedStateCopy.notSavedOffline, "Not saved offline")
        XCTAssertEqual(
            APSavedStateCopy.offlineBanner,
            "You're offline. Changes will sync when you're back online."
        )

        // What the real index reads: the catalog rows the offline saved read is built from.
        let index = StubOfflineIndex(ids: [cached.id])
        let offlineModel = APSavedOfflineModel(index: index, monitorsConnectivity: false)
        XCTAssertFalse(offlineModel.mode.isOffline, "reachability starts from the live path, not from a guess")
    }

    @MainActor func testOfflineRowDimsAndDropsItsUnsaveControl() {
        let tileColumn = (393 - 80)..<(393 - 20)
        let probe = APViewProbe(
            APSavedPoseRow(pose: savedPose("a")),
            size: CGSize(width: 393, height: 160)
        )
        defer { probe.tearDown() }
        let available = bands(of: 0xFAE0E7, in: probe.capture(), xRange: tileColumn)
        XCTAssertEqual(available.count, 1, "a pose the device holds keeps its unsave control")

        let unavailable = probe.render(APSavedPoseRow(pose: savedPose("b"), isAvailableOffline: false))
        XCTAssertTrue(
            bands(of: 0xFAE0E7, in: unavailable, xRange: tileColumn).isEmpty,
            "a pose that is not on the device offers no unsave: the request could not be sent"
        )
        let drawn = inkedBands(in: unavailable, xRange: tileColumn).filter { $0.height >= 20 }
        XCTAssertEqual(drawn.count, 1, "the tile is still drawn, in the muted fill the board uses")
        XCTAssertEqual(Double(drawn.first?.height ?? 0), 44, accuracy: 2, "same 44 pt tile, disabled")
    }

    @MainActor func testOfflineSurfaceBannersAboveTheRowsAndDimsWhatTheCacheLacks() {
        let rows = [savedPose("a"), savedPose("b"), savedPose("c")]
        let model = PosesViewModel(service: SavedListPoseService(rows: rows), bookmarkService: UndoBookmarkService())
        model.filter = .saved
        model.state = .loaded(rows)
        let offline = APSavedOfflineModel(
            index: StubOfflineIndex(ids: ["a"]),
            mode: APSavedOfflineMode(isOffline: true, cachedPoseIDs: ["a"]),
            monitorsConnectivity: false
        )

        // A navigation container on purpose: a `NavigationLink` outside one is drawn disabled, which
        // would wash out every colour this test measures.
        let probe = APViewProbe(
            NavigationView {
                APSavedSurface(model: model, offline: offline) {
                    APSavedList(poses: rows, model: model)
                }
            },
            size: CGSize(width: 393, height: 620)
        )
        defer { probe.tearDown() }
        let painted = probe.capture()

        // The banner: one full-width warning band at the top of the surface.
        let bannerBands = bands(of: 0xFED766, in: painted)
        guard let banner = bannerBands.first else {
            return XCTFail("an offline Saved surface must say so")
        }
        XCTAssertEqual(bannerBands.count, 1, "one banner, not one per row")
        XCTAssertGreaterThan(banner.widestRun, 300, "the banner is a full-width band, not a chip")
        XCTAssertLessThan(banner.minY, 160, "the banner sits at the top of the surface")

        // The rows, in the trailing-tile column: only the cached pose keeps its unsave control.
        let tileColumn = (painted.width - 80)..<(painted.width - 20)
        let offered = bands(of: 0xFAE0E7, in: painted, xRange: tileColumn).filter { $0.height >= 20 }
        XCTAssertEqual(offered.count, 1, "only the pose that is on the device offers an unsave")
        XCTAssertGreaterThan(offered.first?.minY ?? 0, banner.maxY, "the rows come under the banner")

        // Everything under the banner: each of the three rows still draws its tile (one accent, two
        // muted), and the banner itself carries none.
        let rowTiles = inkedBands(in: painted, xRange: tileColumn)
            .filter { $0.height >= 20 && $0.minY > banner.maxY }
        XCTAssertEqual(rowTiles.count, 3, "every row under the banner still draws its tile")
        XCTAssertEqual(
            bands(of: 0xFED766, in: painted, xRange: tileColumn).count, 1,
            "the banner is the only warning band; the rows below it are not part of it"
        )
    }

    // MARK: - The unsave tile scales with Dynamic Type (06-board03)

    @MainActor func testUnsaveTileGrowsAtAccessibilitySizes() {
        XCTAssertEqual(APSavedRowMetrics.unsaveTileSide(for: .large), 44, "the default tile is the 44 pt target")
        XCTAssertEqual(APSavedRowMetrics.unsaveTileSide(for: .accessibility3), 64, "AX3 grows the tile")
        XCTAssertGreaterThan(
            APSavedRowMetrics.unsaveGlyphSize(for: .accessibility3),
            APSavedRowMetrics.unsaveGlyphSize(for: .large),
            "the glyph grows with its tile"
        )

        let probe = APViewProbe(
            APSavedPoseRow(pose: savedPose("ax")),
            size: CGSize(width: 393, height: 160)
        )
        defer { probe.tearDown() }
        let tileColumn = (393 - 80)..<(393 - 20)
        let plain = bands(of: 0xFAE0E7, in: probe.capture(), xRange: tileColumn)
        guard let plainTile = plain.first else { return XCTFail("the row must draw its unsave tile") }
        XCTAssertEqual(Double(plainTile.height), 44, accuracy: 2, "44 pt at the default sizes")

        let scaled = probe.render(
            APSavedPoseRow(pose: savedPose("ax")).environment(\.dynamicTypeSize, .accessibility3)
        )
        let axTiles = bands(of: 0xFAE0E7, in: scaled, xRange: tileColumn)
        guard let axTile = axTiles.first else { return XCTFail("the AX row must still draw its tile") }
        XCTAssertEqual(Double(axTile.height), 64, accuracy: 2, "the board's ~64 pt tile at AX3")
        XCTAssertGreaterThan(
            Double(axTile.width), Double(plainTile.width) + 8,
            "the tile grows in both directions, not just taller"
        )
    }

    // MARK: - The unsave tile is its own hit area (BUG-SAVED-18-01)

    /// A `Button` inside a `NavigationLink` label never receives the tap: the link owns the whole
    /// label's hit area. The list wrapped the entire row — tile included — in the link, so a tap on the
    /// bookmark-slash tile unsaved nothing, offered no Undo, and did not open the pose either.
    ///
    /// Source-level, for the same reason `JobRowAccessibilityTests` reads its view instead of tapping it:
    /// a hosted SwiftUI view exposes neither hit testing nor an accessibility tree to a unit test. What a
    /// tap can reach is decided by this composition, so that is what is pinned.
    ///
    /// Mutation target: mount `APSavedPoseRow` as the `NavigationLink`'s label again and this goes red —
    /// the tile carries the button, so the label would carry a control.
    func testRowLinkDoesNotContainTheUnsaveTile() throws {
        let source = try savedListSource()

        let row = try XCTUnwrap(
            Self.braceMatchedBlock("private func row(for pose: NativePose, index: Int)", in: source),
            "APSavedList.row(for:index:) is where the list composes one saved row"
        )
        XCTAssertTrue(row.contains("NavigationLink("), "the row still opens the pose detail")
        XCTAssertTrue(row.contains("APSavedUnsaveTile("), "the row still mounts its unsave control")
        XCTAssertTrue(row.contains("APSavedPoseRowContent("), "the link's label is the content-only view")
        XCTAssertFalse(
            row.contains("APSavedPoseRow("),
            "APSavedPoseRow carries the tile: as the link's label it nests the control inside the link"
        )

        // The invariant behind that: whatever the link's label is, it carries no control.
        let label = try XCTUnwrap(Self.braceMatchedBlock("struct APSavedPoseRowContent", in: source))
        XCTAssertFalse(label.contains("Button("), "a tap inside the link's label must always open the pose")
        XCTAssertFalse(label.contains("APSavedUnsaveTile"), "the unsave control is not part of the label")

        // And the control is still a real button, with the label the QA flows tap.
        let tile = try XCTUnwrap(Self.braceMatchedBlock("struct APSavedUnsaveTile", in: source))
        XCTAssertTrue(tile.contains("Button(action: onUnsave)"), "the tile sends its own unsave request")
        XCTAssertTrue(tile.contains("\"Remove from saved\""), "the tile keeps the label its flows target")
    }

    /// The list's own row — link and tile as neighbours — still paints both, in the places the tap now
    /// lands: the tile on the trailing edge at its 44 pt target, the pose copy to its left.
    @MainActor func testListRowDrawsTheContentAndItsTileSideBySide() {
        let rows = [savedPose("a")]
        let model = PosesViewModel(service: SavedListPoseService(rows: rows), bookmarkService: UndoBookmarkService())
        model.filter = .saved
        model.state = .loaded(rows)
        model.setPagingForTesting(hasMore: false)

        // A navigation container on purpose, as in the offline-surface test: a link outside one draws
        // disabled, which would wash out the accent fill this measures.
        let probe = APViewProbe(
            NavigationView { APSavedList(poses: rows, model: model) },
            size: CGSize(width: 393, height: 300)
        )
        defer { probe.tearDown() }
        let painted = probe.capture()

        let tileColumn = (painted.width - 80)..<(painted.width - 20)
        let tiles = bands(of: 0xFAE0E7, in: painted, xRange: tileColumn).filter { $0.height >= 20 }
        XCTAssertEqual(tiles.count, 1, "one saved row, one unsave tile")
        guard let tile = tiles.first else { return XCTFail("the list row must draw its unsave tile") }
        XCTAssertGreaterThan(tile.minX, painted.width / 2, "the tile sits on the trailing edge, beside the copy")
        XCTAssertEqual(Double(tile.height), 44, accuracy: 2, "the tile keeps its 44 pt target")

        // The link's own label keeps the pose copy (artwork + name) on the row it opens.
        XCTAssertFalse(
            inkedBands(in: painted, xRange: 12..<(painted.width / 2)).isEmpty,
            "the row's copy is still painted left of the tile, inside the link"
        )
    }

    // MARK: - Fixtures and helpers

    /// Reads the Saved list's own source: the composition a tap depends on is not observable at runtime
    /// in this test host.
    private func savedListSource() throws -> String {
        try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // Features
                .deletingLastPathComponent() // iosAppTests
                .deletingLastPathComponent() // iosApp (project dir)
                .appendingPathComponent("iosApp/Features/Poses/APSavedList.swift"),
            encoding: .utf8
        )
    }

    /// The brace-matched body of the first declaration after `marker`, so a test can read one function or
    /// one struct without caring how long the file around it is.
    private static func braceMatchedBlock(_ marker: String, in source: String) -> String? {
        guard let markerRange = source.range(of: marker),
              let open = source.range(of: "{", range: markerRange.upperBound..<source.endIndex) else { return nil }
        var depth = 0
        var index = open.lowerBound
        while index < source.endIndex {
            switch source[index] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return String(source[open.lowerBound...index]) }
            default: break
            }
            index = source.index(after: index)
        }
        return nil
    }

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

    /// Consecutive rows that paint `hex` at least once, merged into one band each. The `xRange`
    /// variant locates a control in one column (the trailing unsave tile) instead of anywhere.
    private func bands(
        of hex: UInt32,
        in bitmap: APBitmap,
        xRange: Range<Int>,
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
            for x in xRange.clamped(to: 0..<bitmap.width) {
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

    /// Row bands inside one column that paint anything but the card's white surface: how a drawn
    /// control is located when its own fill is a *blended* colour (a disabled control is painted at
    /// reduced opacity, so its token colour never appears verbatim).
    private func inkedBands(
        in bitmap: APBitmap,
        xRange: Range<Int>,
        tolerance: Int = 6
    ) -> [PaintBand] {
        func isInk(_ x: Int, _ y: Int) -> Bool {
            guard let pixel = bitmap.color(x: x, y: y), pixel.alpha > 200 else { return false }
            return abs(pixel.red - 255) > tolerance
                || abs(pixel.green - 255) > tolerance
                || abs(pixel.blue - 255) > tolerance
        }

        var result: [PaintBand] = []
        var current: (minY: Int, maxY: Int, minX: Int, maxX: Int, widestRun: Int)?
        for y in 0..<bitmap.height {
            var run = 0
            var widestRun = 0
            var minX = Int.max
            var maxX = Int.min
            for x in xRange.clamped(to: 0..<bitmap.width) {
                guard isInk(x, y) else {
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

/// A bookmark service a test can fail on one side only, and count: the proof that Undo really goes
/// back to the server instead of flipping a flag.
private final class UndoBookmarkService: PoseBookmarkServing, @unchecked Sendable {
    private let lock = NSLock()
    private var saves = 0
    private var unsaves = 0
    private var _saveError: Error?
    private var _unsaveError: Error?

    var saveError: Error? {
        get { locked { _saveError } }
        set { locked { _saveError = newValue } }
    }

    var unsaveError: Error? {
        get { locked { _unsaveError } }
        set { locked { _unsaveError = newValue } }
    }

    var saveCallCount: Int { locked { saves } }
    var unsaveCallCount: Int { locked { unsaves } }

    func savePose(poseId: String) async throws {
        let error = locked { () -> Error? in
            saves += 1
            return _saveError
        }
        if let error { throw error }
    }

    func unsavePose(poseId: String) async throws {
        let error = locked { () -> Error? in
            unsaves += 1
            return _unsaveError
        }
        if let error { throw error }
    }

    /// iOS 15 target: `NSLock.withLock` is 16+, so the tests do their own.
    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

/// Stands in for the offline catalog: the ids the device holds. A test that mounts the offline board
/// passes the ids it wants reported, so the rendered state is driven by data, not by faking the view.
private struct StubOfflineIndex: APSavedOfflineIndex {
    let ids: Set<String>

    init(ids: Set<String>) { self.ids = ids }

    func cachedPoseIDs() async -> Set<String> { ids }
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

