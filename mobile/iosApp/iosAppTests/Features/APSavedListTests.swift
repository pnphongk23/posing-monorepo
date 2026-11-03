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

    // MARK: - Ids the flows address (TC-SAV-003 / TC-SAV-010 / TC-SAV-014)

    /// The row control's only other handle is the label "Remove from saved", which every row shares: a
    /// flow that taps it cannot say which row it removed, so a wrong-row tap and a dead tap read the
    /// same. The id carries the pose's stable id, so it survives a reload or a reorder.
    ///
    /// Mutation target: drop the pose id from `APSavedIdentifiers.unsave(poseID:)` (or return the row
    /// id) and this goes red.
    func testUnsaveIdentifierKeepsThePoseId() {
        XCTAssertEqual(APSavedIdentifiers.unsave(poseID: "pose_1"), "saved.unsave.pose_1")
        XCTAssertEqual(
            APSavedIdentifiers.unsave(poseID: "b067ba28-5aa5-4a70-8f0c-8e892e1d978f"),
            "saved.unsave.b067ba28-5aa5-4a70-8f0c-8e892e1d978f",
            "the pose's own id is the suffix, not a row index"
        )

        // The ids the E2E lane already uses on a saved row are unchanged: the new one is additive.
        XCTAssertEqual(APSavedIdentifiers.row(index: 0, poseID: "pose_1"), "poses.first-card")
        XCTAssertEqual(APSavedIdentifiers.row(index: 3, poseID: "pose_1"), "poses.card.pose_1")
        XCTAssertNotEqual(
            APSavedIdentifiers.unsave(poseID: "pose_1"),
            APSavedIdentifiers.row(index: 3, poseID: "pose_1"),
            "the control and the link that opens the pose are separate elements, not one id"
        )
    }

    /// The removal bar is found by id, so "the snackbar never appeared" stops being a guess about a
    /// four-second window (`APSnackbar.autoDismissDelay`) and the pose name inside the copy.
    @MainActor func testRemovalSnackbarCarriesTheFlowsIds() {
        let offer = APSavedSnackbarRule.resolve(removedPoseName: "Pose a", canUndo: true, failure: nil)
        XCTAssertEqual(offer?.identifiers.bar, "saved.snackbar")
        XCTAssertEqual(offer?.identifiers.action, "saved.snackbar.undo")
        XCTAssertEqual(APSnackbarIdentifiers.saved.bar, "saved.snackbar")
        XCTAssertEqual(APSnackbarIdentifiers.saved.action, "saved.snackbar.undo")

        // A failure bar is not the reversible offer: its action is a Dismiss, so it must never answer
        // to the Undo id — a flow tapping it through `saved.snackbar.undo` would be exercising the
        // wrong control.
        let failure = APSavedSnackbarRule.resolve(
            removedPoseName: nil,
            canUndo: false,
            failure: SavedMutationCopy.offline
        )
        XCTAssertEqual(failure?.kind, .dismiss)
        XCTAssertEqual(failure?.identifiers.bar, "saved.snackbar", "the bar keeps its id on a failure")
        XCTAssertNil(failure?.identifiers.action, "no Undo offer, no Undo id")

        // A failed Undo keeps its retry offer, so it keeps the action id as well.
        let retry = APSavedSnackbarRule.resolve(
            removedPoseName: "Pose a",
            canUndo: true,
            failure: SavedMutationCopy.offline
        )
        XCTAssertEqual(retry?.kind, .undo)
        XCTAssertEqual(retry?.identifiers.action, "saved.snackbar.undo")
    }

    /// Source-level, like the composition pin above: a hosted SwiftUI view materialises no
    /// accessibility tree in this test host, so the wiring that puts the ids on the elements is what
    /// is checked — the rows mount the per-pose id, the surface hands the bar its ids, and both
    /// components actually apply them.
    ///
    /// Mutation target: remove `.apIdentifier(identifier)` from the tile, `.apIdentifier(identifiers?.bar)`
    /// from the bar, `.apIdentifier(identifiers?.action)` from its action, or stop passing
    /// `identifiers:` from `APSavedSurface` — each turns exactly one assertion below red.
    func testIdsAreWiredFromTheRowAndTheBarToTheElements() throws {
        let saved = try savedListSource()

        let row = try XCTUnwrap(
            Self.braceMatchedBlock("private func row(for pose: NativePose, index: Int)", in: saved)
        )
        XCTAssertTrue(
            row.contains("identifier: APSavedIdentifiers.unsave(poseID: pose.id)"),
            "the row's unsave control is addressed per pose, not by its shared label"
        )

        let tile = try XCTUnwrap(Self.braceMatchedBlock("struct APSavedUnsaveTile", in: saved))
        XCTAssertTrue(tile.contains(".apIdentifier(identifier)"), "the tile applies the id it is given")
        XCTAssertTrue(
            tile.contains(".accessibilityLabel(\"Remove from saved\")"),
            "the id is additive: the accessible name the flows read by text stays"
        )

        let surface = try XCTUnwrap(Self.braceMatchedBlock("struct APSavedSurface", in: saved))
        XCTAssertTrue(
            surface.contains("identifiers: snackbar?.identifiers"),
            "the surface hands the bar the ids of the bar it is actually showing"
        )

        let snackbar = try snackbarSource()
        let bar = try XCTUnwrap(Self.braceMatchedBlock("struct APSnackbar: View", in: snackbar))
        XCTAssertTrue(bar.contains(".apIdentifier(identifiers?.bar)"), "the bar carries `saved.snackbar`")
        XCTAssertTrue(
            bar.contains(".apIdentifier(identifiers?.action)"),
            "the action carries `saved.snackbar.undo`"
        )
    }

    /// The row's tap and the tests that check it run the same code, and the control only offers a
    /// removal for a pose the model holds as saved.
    ///
    /// Why source-level: a hosted SwiftUI view in this test host is painted, not hit-tested, so the
    /// composition is the only thing a unit test can hold still. The behaviour behind it is driven for
    /// real in `testTheTilesOwnActionUnsavesThroughTheSavedRoute`.
    ///
    /// Mutation target: bind the tile to a private copy of the tap again (as `onUnsave: { Task { … } }`)
    /// and the first assertion goes red; drop `model.savedState(for: pose)` from `isEnabled` and the
    /// second does — with that term gone, a row that is not actually saved offers "Remove from saved"
    /// and the request it sends is a **save**, which the surface has nothing to report (the silent tap
    /// of TC-SAV-010).
    func testTheRowsTapRunsTheSharedUnsaveRuleForASavedPoseOnly() throws {
        let saved = try savedListSource()

        let row = try XCTUnwrap(
            Self.braceMatchedBlock("private func row(for pose: NativePose, index: Int)", in: saved)
        )
        XCTAssertTrue(
            row.contains("onUnsave: APSavedRowUnsave.action(pose, at: index, in: model, undo: undo)"),
            "the tile's action is the shared rule, not a second copy of the logic"
        )
        XCTAssertFalse(row.contains("Task {"), "the row spawns no request of its own")
        XCTAssertTrue(
            row.contains("model.savedState(for: pose)"),
            "a row the model does not hold as saved cannot offer a removal"
        )

        let rule = try XCTUnwrap(Self.braceMatchedBlock("enum APSavedRowUnsave", in: saved))
        XCTAssertTrue(
            rule.contains("APSavedUndoRule.offersUndo(for: outcome)"),
            "a confirmed removal offers Undo"
        )
        XCTAssertTrue(
            rule.contains("model.bookmarkError = APSavedStateCopy.removeFailed"),
            "an outcome that removed nothing still says so instead of going silent"
        )
        XCTAssertTrue(
            rule.contains("Task { await perform("),
            "the action is the closure the tile's Button runs, and it awaits the same rule"
        )

        // The surface puts the library filter back on the way out: the filter is the route the shared
        // pose service reads by, so leaving it on `.saved` would route the next catalogue read to the
        // saved collection.
        let surface = try XCTUnwrap(Self.braceMatchedBlock("struct APSavedSurface", in: saved))
        XCTAssertTrue(
            surface.contains("entryFilter = model.filter"),
            "the surface remembers the collection it replaced"
        )
        XCTAssertTrue(
            surface.contains("if let entryFilter, model.filter == .saved { model.filter = entryFilter }"),
            "leaving Saved restores the collection the Poses tab was showing"
        )
    }

    // MARK: - A tap that is waiting on the server (pending unsave)

    /// The tile's one rule: which state it is in, whether it takes a tap, and what it says.
    ///
    /// Mutation target: make `state(isUnsaving:…)` ignore `isUnsaving` and the in-flight case goes red;
    /// drop the `isAvailableOffline` term and the offline row offers a request it cannot send.
    func testUnsaveTileStateRule() {
        XCTAssertEqual(
            APSavedUnsaveTileRule.state(isUnsaving: false, isEnabled: true, isAvailableOffline: true),
            .idle
        )
        XCTAssertEqual(
            APSavedUnsaveTileRule.state(isUnsaving: true, isEnabled: true, isAvailableOffline: true),
            .inFlight,
            "the request the person already sent is the state that has to be shown"
        )
        XCTAssertEqual(
            APSavedUnsaveTileRule.state(isUnsaving: true, isEnabled: false, isAvailableOffline: false),
            .inFlight,
            "in flight outranks the row's other flags: a sent tap never silently disappears"
        )
        XCTAssertEqual(
            APSavedUnsaveTileRule.state(isUnsaving: false, isEnabled: false, isAvailableOffline: true),
            .unavailable,
            "a pose the server reported gone offers nothing"
        )
        XCTAssertEqual(
            APSavedUnsaveTileRule.state(isUnsaving: false, isEnabled: true, isAvailableOffline: false),
            .unavailable,
            "so does a pose the device cannot send for offline"
        )

        // The tap gate: only the resting tile takes a tap, so the ignored second tap is a state, not a
        // no-op the user cannot explain.
        XCTAssertTrue(APSavedUnsaveTileRule.acceptsTap(.idle))
        XCTAssertFalse(APSavedUnsaveTileRule.acceptsTap(.inFlight))
        XCTAssertFalse(APSavedUnsaveTileRule.acceptsTap(.unavailable))

        // And the same state is what assistive technology hears, next to the disabled control.
        XCTAssertEqual(APSavedUnsaveTileRule.accessibilityValue(for: .inFlight), "In progress")
        XCTAssertEqual(APSavedUnsaveTileRule.accessibilityValue(for: .idle), "")
        XCTAssertEqual(APSavedUnsaveTileRule.accessibilityValue(for: .unavailable), "")
        XCTAssertEqual(APSavedStateCopy.unsaveInFlight, "In progress")

        // Reduce Motion keeps the tile still: the fill, the disabled control and the value carry it.
        XCTAssertTrue(APSavedUnsaveTileRule.showsSpinner(.inFlight, reduceMotion: false))
        XCTAssertFalse(APSavedUnsaveTileRule.showsSpinner(.inFlight, reduceMotion: true))
        XCTAssertFalse(APSavedUnsaveTileRule.showsSpinner(.idle, reduceMotion: false))
    }

    /// The whole transition the user sees: the row is still there and its tile is busy while the
    /// request is out, and only the server's confirmation removes it.
    ///
    /// Mutation target: paint the in-flight tile with `selectedBackground` (the old behaviour) and the
    /// pixel assertions go red while everything else stays green — which is exactly the bug.
    @MainActor func testUnsavingShowsThePendingTileThenRemovesTheRow() async {
        let rows = [savedPose("a")]
        let service = HeldBookmarkService()
        let model = PosesViewModel(service: SavedListPoseService(rows: rows), bookmarkService: service)
        model.filter = .saved
        model.state = .loaded(rows)
        model.setPagingForTesting(hasMore: false)

        // A navigation container on purpose, as in the other list tests: a link outside one draws
        // disabled, which would wash out the accent fill this measures.
        let probe = APViewProbe(
            NavigationView { APSavedList(poses: rows, model: model) },
            size: CGSize(width: 393, height: 300)
        )
        defer { probe.tearDown() }
        let tileColumn = (393 - 80)..<(393 - 20)

        let idle = probe.capture()
        XCTAssertEqual(
            bands(of: 0xFAE0E7, in: idle, xRange: tileColumn).filter { $0.height >= 20 }.count, 1,
            "a resting row offers the accent unsave tile"
        )

        // One tap: the request leaves, and the model has not touched the list.
        let request = Task { await model.toggleSaved(for: rows[0]) }
        await service.waitUntilUnsaving()
        await waitUntil("the bookmark claim to be published") { model.isBookmarkInFlight("a") }

        XCTAssertEqual(
            APSavedUnsaveTileRule.state(
                isUnsaving: model.isBookmarkInFlight("a"),
                isEnabled: model.canSave(rows[0]) && model.bookmarkService != nil,
                isAvailableOffline: true
            ),
            .inFlight,
            "while the request is out the tile is the in-flight one, not the enabled-looking one"
        )
        XCTAssertEqual(
            model.state.rows.map(\.id), ["a"],
            "nothing leaves the collection before the server confirms it"
        )

        let pending = probe.render(NavigationView { APSavedList(poses: rows, model: model) })
        XCTAssertTrue(
            bands(of: 0xFAE0E7, in: pending, xRange: tileColumn).filter { $0.height >= 20 }.isEmpty,
            "the pending tile is no longer painted as the enabled one: the tap is visibly taken"
        )
        let pendingTile = inkedBands(in: pending, xRange: tileColumn).filter { $0.height >= 20 }
        XCTAssertEqual(pendingTile.count, 1, "the pending tile is still drawn, in the muted fill")
        XCTAssertEqual(
            Double(pendingTile.first?.height ?? 0), 44, accuracy: 2,
            "the pending tile keeps the 44 pt hit target"
        )

        // The server answers: the claim is released and the row goes.
        service.releaseUnsaving()
        let outcome = await request.value
        XCTAssertEqual(outcome, .saved(false))
        XCTAssertFalse(model.isBookmarkInFlight("a"), "a settled request releases its claim")
        XCTAssertTrue(model.state.rows.isEmpty, "the confirmed removal takes the row with it")

        let removed = probe.render(NavigationView { APSavedList(poses: model.state.rows, model: model) })
        XCTAssertTrue(
            inkedBands(in: removed, xRange: tileColumn).filter { $0.height >= 20 }.isEmpty,
            "no row, no tile"
        )
    }

    /// A failed unsave puts the tile back to the resting one and leaves the existing failure copy in
    /// `bookmarkError` — the same snackbar it shows today, now with a state that returned to idle.
    @MainActor func testFailedUnsaveRevertsTheTileAndKeepsTheFailureCopy() async {
        let rows = [savedPose("a")]
        let service = HeldBookmarkService(unsaveFailure: URLError(.notConnectedToInternet))
        let model = PosesViewModel(service: SavedListPoseService(rows: rows), bookmarkService: service)
        model.filter = .saved
        model.state = .loaded(rows)
        model.setPagingForTesting(hasMore: false)

        let probe = APViewProbe(
            NavigationView { APSavedList(poses: rows, model: model) },
            size: CGSize(width: 393, height: 300)
        )
        defer { probe.tearDown() }
        let tileColumn = (393 - 80)..<(393 - 20)

        let request = Task { await model.toggleSaved(for: rows[0]) }
        await service.waitUntilUnsaving()
        await waitUntil("the bookmark claim to be published") { model.isBookmarkInFlight("a") }
        XCTAssertTrue(model.isBookmarkInFlight("a"))

        service.releaseUnsaving()
        let outcome = await request.value

        XCTAssertEqual(outcome, .failed(SavedMutationCopy.offline))
        XCTAssertFalse(model.isBookmarkInFlight("a"), "a failed request releases its claim")
        XCTAssertEqual(
            model.bookmarkError, SavedMutationCopy.offline,
            "the user still gets the real reason, from the same place as today"
        )
        XCTAssertEqual(model.state.rows.map(\.id), ["a"], "a failed unsave leaves the row in place")
        XCTAssertEqual(
            APSavedUnsaveTileRule.state(
                isUnsaving: model.isBookmarkInFlight("a"),
                isEnabled: model.canSave(rows[0]) && model.bookmarkService != nil,
                isAvailableOffline: true
            ),
            .idle,
            "the tile reverts with the collection"
        )

        let reverted = probe.render(NavigationView { APSavedList(poses: rows, model: model) })
        XCTAssertEqual(
            bands(of: 0xFAE0E7, in: reverted, xRange: tileColumn).filter { $0.height >= 20 }.count, 1,
            "after the failure the tile is the accent one again, ready for the retry"
        )
    }

    /// Source-level, like the ids pin above: a hosted SwiftUI view exposes no accessibility tree, so the
    /// wiring that turns the rule into pixels and an announced value is what is checked.
    ///
    /// Mutation target: drop `.accessibilityValue(...)`, drop the rule from `.disabled(...)`, or screen
    /// the spinner on something other than `showsSpinner` — each turns one assertion below red.
    func testUnsaveTileWiresThePendingStateToItsPixelsAndAccessibility() throws {
        let saved = try savedListSource()
        let tile = try XCTUnwrap(Self.braceMatchedBlock("struct APSavedUnsaveTile", in: saved))

        XCTAssertTrue(tile.contains("APSavedUnsaveTileRule.state("), "the tile has one source of truth")
        XCTAssertTrue(
            tile.contains(".disabled(!APSavedUnsaveTileRule.acceptsTap(state))"),
            "a second tap while the request is out is refused by the control itself"
        )
        XCTAssertTrue(
            tile.contains(".accessibilityValue(APSavedUnsaveTileRule.accessibilityValue(for: state))"),
            "the pending state is announced, not only painted"
        )
        XCTAssertTrue(
            tile.contains("APSavedUnsaveTileRule.showsSpinner(state, reduceMotion: reduceMotion)"),
            "the only motion is the spinner, and Reduce Motion removes it"
        )
        XCTAssertTrue(tile.contains("ProgressView()"), "the pending tile shows it is working")
        XCTAssertTrue(tile.contains("AP.Color.controlFill"), "the muted state is a token, not a literal")
        XCTAssertTrue(tile.contains(".apIdentifier(identifier)"), "the flows' id is untouched")
        XCTAssertTrue(
            tile.contains(".accessibilityLabel(\"Remove from saved\")"),
            "so is the accessible name the flows read by text"
        )
        XCTAssertFalse(tile.contains("Color(hex"), "no hard-coded colour in the tile")
        XCTAssertFalse(tile.contains("stroke"), "the tile takes no resting border")

        // The row hands the tile the model's claim, which is what makes the state real.
        let list = try XCTUnwrap(
            Self.braceMatchedBlock("private func row(for pose: NativePose, index: Int)", in: saved)
        )
        XCTAssertTrue(
            list.contains("isUnsaving: model.isBookmarkInFlight(pose.id)"),
            "the row's pending state is the model's in-flight claim, not a local guess"
        )
    }

    /// The whole path a finger starts, without a finger: the action bound to the row's tile, a model
    /// whose rows came from the saved collection, and a fake bookmark service.
    ///
    /// This is the assertion the device evidence could not make: it proves the request this control
    /// sends on a Saved row is `unsavePose`, not `savePose`, and that its outcome reaches the bar the
    /// flows look for. Before the route fix the same tap called `savePose` and no bar followed, which
    /// is exactly "the unsave never fires" as the device saw it.
    ///
    /// Mutation target: make the tile send `pose.withSavedValue(false)` (a save from the Saved surface)
    /// or drop the saved route from `PosesViewModel.selectRoute(_:)` — the service counts swap and the
    /// bar assertion goes red.
    @MainActor func testTheTilesOwnActionUnsavesThroughTheSavedRoute() async throws {
        let remote = RecordingPoseRemote()
        let savedPoseID = "mine-1"
        remote.savedItems = [try savedRouteRemotePose(savedPoseID, name: "Mine")]
        // The app's wiring: the adapter holds the route slot, the model is handed only the service.
        let adapter = PoseAPIServiceAdapter(
            remote: remote,
            baseURL: "https://api.example.com",
            filterState: PoseFilterState()
        )
        let bookmarks = UndoBookmarkService()
        let model = PosesViewModel(service: adapter, bookmarkService: bookmarks)

        // Entering Saved is what makes the rows the saved collection.
        await APSavedEntry.prepare(model: model)
        XCTAssertEqual(remote.savedCallCount, 1)
        guard case .loaded(let rows) = model.state, let row = rows.first else {
            return XCTFail("the saved collection must load a row for the tile to act on")
        }
        XCTAssertEqual(row.id, savedPoseID)
        XCTAssertTrue(model.savedState(for: row), "the row the tile offers to remove is saved")

        let undo = APSavedUndo()
        let remove = APSavedRowUnsave.action(row, at: 0, in: model, undo: undo)
        // Built the way the list builds it, so the closure under test is the one its Button carries.
        let tile = APSavedUnsaveTile(
            isUnsaving: model.isBookmarkInFlight(row.id),
            isEnabled: model.canSave(row) && model.savedState(for: row) && model.bookmarkService != nil,
            isAvailableOffline: true,
            identifier: APSavedIdentifiers.unsave(poseID: row.id),
            onUnsave: remove
        )

        // Exactly what the Button runs.
        tile.onUnsave()
        await waitUntil("the removal to be confirmed and offered back") { undo.removal != nil }

        XCTAssertEqual(bookmarks.unsaveCallCount, 1, "one tap, one unsavePose")
        XCTAssertEqual(bookmarks.saveCallCount, 0, "and never the opposite request")
        XCTAssertTrue(model.state.rows.isEmpty, "the confirmed removal takes the row out of the Saved list")
        XCTAssertNil(model.bookmarkError)

        let spec = APSavedSnackbarRule.resolve(
            removedPoseName: undo.removal?.pose.name,
            canUndo: undo.removal.map { model.canSave($0.pose) } ?? false,
            failure: model.bookmarkError
        )
        XCTAssertEqual(spec?.identifiers.bar, "saved.snackbar", "the bar the flows wait for")
        XCTAssertEqual(spec?.identifiers.action, "saved.snackbar.undo", "with its Undo action")
        XCTAssertEqual(spec?.message, "Removed Mine")
    }

    // MARK: - Left the collection and came back (persistence)

    /// An unsave has to survive leaving Saved and coming back, and a relaunch: the request is a real
    /// deletion on the server, and re-entering reads the collection again instead of redrawing what the
    /// screen had before.
    ///
    /// The fake here is a *server*, not a spy: `posesPage` answers from the same id list the bookmark
    /// calls mutate, which is what makes "the row came back" observable at all. The re-entry is exactly
    /// what the surface's `.task` runs (`APSavedEntry.prepare` → `load()`), and the relaunch is a second
    /// model over the same server state.
    ///
    /// Mutation target: make `APSavedEntry.prepare` reuse the loaded state instead of reloading (or make
    /// `unsavePose` a local-only flip) and the re-entry assertions go red.
    @MainActor func testAnUnsaveSurvivesLeavingAndReEnteringSaved() async {
        let server = SavedCollectionServer(ids: ["a", "b"])
        let model = PosesViewModel(service: server, bookmarkService: server)
        await APSavedEntry.prepare(model: model)
        XCTAssertEqual(model.state.rows.map(\.id), ["a", "b"], "the saved collection, in server order")

        let undo = APSavedUndo()
        await APSavedRowUnsave.perform(model.state.rows[0], at: 0, in: model, undo: undo)

        XCTAssertEqual(server.unsaveCallCount, 1, "one tap, one unsave request")
        XCTAssertEqual(server.saveCallCount, 0, "and not the opposite request")
        XCTAssertEqual(server.unsavedPoseID, "a", "the row's own pose id is what the server was told")
        XCTAssertEqual(server.savedIDs, ["b"], "the server no longer has it")
        XCTAssertEqual(model.state.rows.map(\.id), ["b"])

        // Leave Saved and come back: the surface's `.task` prepares and reloads the collection.
        await APSavedEntry.prepare(model: model)
        XCTAssertEqual(model.state.rows.map(\.id), ["b"], "the removed row does not come back")

        // A relaunch: a fresh model (and a fresh undo offer) over the same server state.
        let relaunched = PosesViewModel(service: server, bookmarkService: server)
        await APSavedEntry.prepare(model: relaunched)
        XCTAssertEqual(relaunched.state.rows.map(\.id), ["b"], "and it stays gone after a relaunch")
        XCTAssertEqual(relaunched.bookmarkError, nil)
    }

    /// The other half of the same requirement: when the request fails, the row must not disappear (the
    /// server still has it) and must not be silently "restored" later either — the recovery is the error
    /// bar, and re-entering reads the same, still-saved collection.
    ///
    /// Mutation target: remove the row optimistically before the request settles and every assertion
    /// about the row staying in place goes red.
    @MainActor func testAFailedUnsaveLeavesTheRowOnTheServerAndOnTheNextEntry() async {
        let server = SavedCollectionServer(ids: ["a"])
        server.unsaveError = URLError(.notConnectedToInternet)
        let model = PosesViewModel(service: server, bookmarkService: server)
        await APSavedEntry.prepare(model: model)

        let outcome = await APSavedRowUnsave.perform(model.state.rows[0], at: 0, in: model, undo: APSavedUndo())

        XCTAssertEqual(outcome, .failed(SavedMutationCopy.offline))
        XCTAssertEqual(server.savedIDs, ["a"], "a failed request changed nothing on the server")
        XCTAssertEqual(model.state.rows.map(\.id), ["a"], "and nothing on the screen")
        XCTAssertEqual(model.bookmarkError, SavedMutationCopy.offline, "the error bar states the reason")

        await APSavedEntry.prepare(model: model)
        XCTAssertEqual(model.state.rows.map(\.id), ["a"], "re-entry shows what the server still has")
    }

    // MARK: - The tap path (TC-SAV-010 on 1.1 (20))

    /// The app's own wiring, one line short of the fix: the adapter holds a filter slot the model is
    /// never given. Entering Saved has to read the saved collection anyway.
    ///
    /// The defect this pins: `AppFeatureRoot` builds
    /// `PosesViewModel(service:bookmarkService:boundary:)` without the bundle's `PoseFilterState`, and
    /// that slot was the only thing telling `PoseAPIServiceAdapter` which feed to read. So the Saved
    /// screen asked for `/api/community/poses` and drew the community rows as saved rows; tapping
    /// "Remove from saved" on one of them was a *save* (the model's saved state for that pose was
    /// `false`), which this surface reports nowhere — the tap looked dead.
    ///
    /// Mutation target: keep only `filterState?.filter` in `PosesViewModel.selectRoute(_:)` and this
    /// test reads `fetchCommunity` with zero saved reads and no rows.
    @MainActor func testSavedEntryReadsTheSavedCollectionWithoutTheBundleSlot() async throws {
        let remote = RecordingPoseRemote()
        remote.savedItems = [try savedRouteRemotePose("mine-1", name: "Mine")]
        // The bundle's slot, exactly as `PoseServiceBootstrap.make` builds it. The model is built the
        // way `AppFeatureRoot` builds it: without it.
        let slot = PoseFilterState()
        let adapter = PoseAPIServiceAdapter(remote: remote, baseURL: "https://api.example.com", filterState: slot)
        let model = PosesViewModel(service: adapter, bookmarkService: UndoBookmarkService())

        await APSavedEntry.prepare(model: model)

        XCTAssertEqual(remote.savedCallCount, 1, "Saved must read /api/me/saved")
        XCTAssertEqual(remote.communityCallCount, 0, "the community feed is not the saved collection")
        XCTAssertEqual(slot.filter, .saved, "the route follows the list the screen shows")
        XCTAssertEqual(model.state.rows.map(\.id), ["mine-1"], "and the rows are the saved ones")
        XCTAssertTrue(model.savedState(for: savedPose("mine-1")), "so the row's tile removes, never saves")
    }

    /// The filter is the route, and it is process-wide: leaving Saved has to put back the collection the
    /// Poses tab (and the camera's picker, which reads the same catalogue service) was showing.
    ///
    /// Mutation target: drop `filter`'s `didSet` (route only written inside `load()`) and the slot stays
    /// `.saved` after the restore — a Saved visit would then route the next catalogue read to the saved
    /// collection.
    @MainActor func testLeavingSavedPutsTheLibraryFilterAndItsRouteBack() async throws {
        let remote = RecordingPoseRemote()
        remote.savedItems = [try savedRouteRemotePose("mine-1", name: "Mine")]
        let slot = PoseFilterState()
        let adapter = PoseAPIServiceAdapter(remote: remote, baseURL: "https://api.example.com", filterState: slot)
        let model = PosesViewModel(service: adapter, bookmarkService: UndoBookmarkService())

        let replaced = await APSavedEntry.prepare(model: model)
        XCTAssertEqual(replaced, .community, "entering Saved replaced the community collection")
        XCTAssertEqual(slot.filter, .saved)

        // What `APSavedSurface.onDisappear` does with the value `prepare` returned.
        model.filter = replaced
        XCTAssertEqual(model.filter, .community)
        XCTAssertEqual(slot.filter, .community, "the route the catalogue is read by is restored")
    }

    /// A tap on a saved row: one unsave, no save, the row leaves, and the bar that offers it back is
    /// the one the flows address. Driven through `APSavedRowUnsave`, which is the code the row's
    /// closure runs — a hosted SwiftUI view cannot be tapped in this test host, so the behaviour is
    /// driven here and the composition is pinned at source level above.
    @MainActor func testTapUnsavesOnceRemovesTheRowAndOffersUndoUnderItsIds() async {
        let bookmarks = UndoBookmarkService()
        let rows = [savedPose("a"), savedPose("b"), savedPose("c")]
        let model = PosesViewModel(service: SavedListPoseService(rows: rows), bookmarkService: bookmarks)
        model.filter = .saved
        model.state = .loaded(rows)
        let undo = APSavedUndo()

        let outcome = await APSavedRowUnsave.perform(rows[1], at: 1, in: model, undo: undo)

        XCTAssertEqual(outcome, .saved(false))
        XCTAssertEqual(bookmarks.unsaveCallCount, 1, "the tap sends the removal exactly once")
        XCTAssertEqual(bookmarks.saveCallCount, 0, "and never the opposite request")
        XCTAssertEqual(model.state.rows.map(\.id), ["a", "c"], "the confirmed removal takes the row")
        XCTAssertEqual(undo.removal?.pose.id, "b")
        XCTAssertEqual(undo.removal?.index, 1, "where it was, not appended")

        let spec = APSavedSnackbarRule.resolve(
            removedPoseName: undo.removal?.pose.name,
            canUndo: undo.removal.map { model.canSave($0.pose) } ?? false,
            failure: model.bookmarkError
        )
        XCTAssertEqual(spec?.message, "Removed Pose b")
        XCTAssertEqual(spec?.tone, .success)
        XCTAssertEqual(spec?.actionTitle, "Undo")
        XCTAssertEqual(spec?.identifiers.bar, "saved.snackbar", "the flows find the bar by this id")
        XCTAssertEqual(spec?.identifiers.action, "saved.snackbar.undo", "and its action by this one")
    }

    /// A failed removal is the error bar, and that bar has no Undo id: a flow must never tap the Undo
    /// id of a bar that cannot undo.
    @MainActor func testTapFailureIsTheErrorBarAndKeepsTheRow() async {
        let bookmarks = UndoBookmarkService()
        bookmarks.unsaveError = URLError(.notConnectedToInternet)
        let rows = [savedPose("a")]
        let model = PosesViewModel(service: SavedListPoseService(rows: rows), bookmarkService: bookmarks)
        model.filter = .saved
        model.state = .loaded(rows)
        let undo = APSavedUndo()

        let outcome = await APSavedRowUnsave.perform(rows[0], at: 0, in: model, undo: undo)

        XCTAssertEqual(outcome, .failed(SavedMutationCopy.offline))
        XCTAssertNil(undo.removal, "nothing left the collection, so there is nothing to undo")
        XCTAssertEqual(model.state.rows.map(\.id), ["a"], "the row stays")
        let spec = APSavedSnackbarRule.resolve(
            removedPoseName: nil,
            canUndo: false,
            failure: model.bookmarkError
        )
        XCTAssertEqual(spec?.message, SavedMutationCopy.offline)
        XCTAssertEqual(spec?.tone, .error)
        XCTAssertEqual(spec?.identifiers.bar, "saved.snackbar")
        XCTAssertNil(spec?.identifiers.action, "a failure bar's action is Dismiss, not Undo")
    }

    /// The silent outcome the device report ended on: the row was not saved after all, so the tap
    /// saved it. The collection keeps the row and, without this line, the tap reported nothing at all.
    @MainActor func testTapOnARowThatWasNotSavedSaysSoInsteadOfGoingSilent() async {
        let bookmarks = UndoBookmarkService()
        let unsaved = savedPose("community-1").withSavedValue(false)
        let model = PosesViewModel(service: SavedListPoseService(rows: [unsaved]), bookmarkService: bookmarks)
        model.filter = .saved
        model.state = .loaded([unsaved])
        let undo = APSavedUndo()

        // Before the tap the row is not saved, so the control offers no removal at all: the wrong
        // request cannot be sent from a resting tile in the first place.
        XCTAssertFalse(model.savedState(for: unsaved), "the row is not saved")
        XCTAssertEqual(
            APSavedUnsaveTileRule.state(
                isUnsaving: false,
                isEnabled: model.canSave(unsaved)
                    && model.savedState(for: unsaved)
                    && model.bookmarkService != nil,
                isAvailableOffline: true
            ),
            .unavailable,
            "an unsaved row's tile is unavailable, not a removal that saves"
        )

        // Driving the advice anyway (a stale row, or a second screen): the outcome still has to be
        // visible instead of silent.
        let outcome = await APSavedRowUnsave.perform(unsaved, at: 0, in: model, undo: undo)

        XCTAssertEqual(outcome, .saved(true), "the request the model actually sent was a save")
        XCTAssertEqual(bookmarks.saveCallCount, 1)
        XCTAssertEqual(bookmarks.unsaveCallCount, 0)
        XCTAssertNil(undo.removal, "nothing was removed")
        XCTAssertEqual(
            model.bookmarkError, APSavedStateCopy.removeFailed,
            "the tap has to say that the removal did not happen"
        )
        let spec = APSavedSnackbarRule.resolve(
            removedPoseName: nil,
            canUndo: false,
            failure: model.bookmarkError
        )
        XCTAssertEqual(spec?.message, "Couldn't remove this pose.")
        XCTAssertEqual(spec?.identifiers.bar, "saved.snackbar", "it is still a bar the flows can find")
        XCTAssertEqual(spec?.kind, .dismiss)
        XCTAssertTrue(model.savedState(for: unsaved), "the pose the server confirmed is saved from now on")
    }

    /// A second tap while the first request is out is refused by the model and shows no second bar:
    /// the attempt already out owns the visible outcome.
    @MainActor func testSecondTapWhileTheRequestIsOutIsIgnoredAndTheFirstOwnsTheBar() async {
        let bookmarks = HeldBookmarkService()
        let rows = [savedPose("a")]
        let model = PosesViewModel(service: SavedListPoseService(rows: rows), bookmarkService: bookmarks)
        model.filter = .saved
        model.state = .loaded(rows)
        let undo = APSavedUndo()

        let first = Task { await APSavedRowUnsave.perform(rows[0], at: 0, in: model, undo: undo) }
        await bookmarks.waitUntilUnsaving()
        await waitUntil("the model to publish the claim") { model.isBookmarkInFlight("a") }

        XCTAssertEqual(
            APSavedUnsaveTileRule.state(
                isUnsaving: model.isBookmarkInFlight("a"),
                isEnabled: model.canSave(rows[0]) && model.savedState(for: rows[0]),
                isAvailableOffline: true
            ),
            .inFlight
        )
        XCTAssertFalse(APSavedUnsaveTileRule.acceptsTap(.inFlight), "a resting tile cannot produce this")

        let second = await APSavedRowUnsave.perform(rows[0], at: 0, in: model, undo: undo)
        XCTAssertEqual(second, .inFlight)
        XCTAssertEqual(bookmarks.unsaveCallCount, 1, "the refused tap sends nothing")
        XCTAssertNil(undo.removal, "and shows nothing of its own")

        bookmarks.releaseUnsaving()
        let firstOutcome = await first.value
        XCTAssertEqual(firstOutcome, .saved(false), "the attempt already out settles visibly")
        XCTAssertEqual(undo.removal?.pose.id, "a")
    }

    /// A session change under the tap: the request is discarded and the screen itself is what changes
    /// (the gate, or a fresh load), so no bar is added on top of it.
    @MainActor func testSessionChangeUnderTheTapIsDiscardedAndTheCollectionIsDropped() async {
        let boundary = SessionBoundary(tokenStorage: SignedInTokenStorage())
        let bookmarks = HeldBookmarkService()
        let rows = [savedPose("a")]
        let server = SavedCollectionServer(ids: ["a"])
        let model = PosesViewModel(
            service: server,
            bookmarkService: bookmarks,
            boundary: boundary
        )
        model.filter = .saved
        model.state = .loaded(rows)
        let undo = APSavedUndo(boundary: boundary)

        let tap = Task { await APSavedRowUnsave.perform(rows[0], at: 0, in: model, undo: undo) }
        await bookmarks.waitUntilUnsaving()
        await waitUntil("the model to publish the claim") { model.isBookmarkInFlight("a") }

        let readsBeforeSignOut = server.posesPageCallCount
        await boundary.signOut()
        // The reset drops the collection and re-reads it, so the screen cannot keep the previous Account's
        // rows: the re-read is the observable consequence.
        await waitUntil("the saved collection to be re-read for the new session") {
            server.posesPageCallCount > readsBeforeSignOut
        }

        bookmarks.releaseUnsaving()
        let outcome = await tap.value
        XCTAssertEqual(outcome, .discarded, "the answer belongs to the previous session")
        XCTAssertNil(undo.removal, "an offer for the previous Account's row would be a lie")
        XCTAssertNil(model.bookmarkError, "and so would an error about it")
        XCTAssertFalse(
            model.isBookmarkInFlight("a"),
            "the claim from the previous session is gone with the collection"
        )
    }

    /// With no bookmark service the tile is unavailable and takes no tap, so `.unavailable` cannot be
    /// produced by a person pressing a resting control.
    @MainActor func testTapWithoutABookmarkServiceIsNotReachableFromTheTile() async {
        let rows = [savedPose("a")]
        let model = PosesViewModel(service: SavedListPoseService(rows: rows), bookmarkService: nil)
        model.filter = .saved
        model.state = .loaded(rows)

        XCTAssertEqual(
            APSavedUnsaveTileRule.state(
                isUnsaving: false,
                isEnabled: model.canSave(rows[0])
                    && model.savedState(for: rows[0])
                    && model.bookmarkService != nil,
                isAvailableOffline: true
            ),
            .unavailable
        )
        XCTAssertFalse(APSavedUnsaveTileRule.acceptsTap(.unavailable), "the tile is disabled, not silent")
        let outcome = await APSavedRowUnsave.perform(rows[0], at: 0, in: model, undo: APSavedUndo())
        XCTAssertEqual(outcome, .unavailable, "and the model agrees nothing was sent")
        XCTAssertNil(model.bookmarkError)
    }

    // MARK: - Fixtures and helpers

    /// Pumps the main actor until `condition` holds: the model publishes the claim, so a test waits on
    /// that state instead of on a guessed sleep.
    @MainActor private func waitUntil(
        _ what: String,
        timeout: TimeInterval = 3,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTFail("timed out waiting for \(what)")
    }

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

    /// The bar's own source: its ids are applied inside `APSnackbar`, which a unit test cannot mount
    /// into an accessibility tree.
    private func snackbarSource() throws -> String {
        try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // Features
                .deletingLastPathComponent() // iosAppTests
                .deletingLastPathComponent() // iosApp (project dir)
                .appendingPathComponent("iosApp/Core/DesignSystem/APSnackbar.swift"),
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

/// A pose service a test can fail on one side only, and count: the proof that Undo really goes back
/// to the server instead of flipping a flag.
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

/// A bookmark service whose unsave stays open until the test releases it. The only honest way to look
/// at the screen while the request is genuinely in flight — a fast fake would hide the very state this
/// behaviour is about.
private final class HeldBookmarkService: PoseBookmarkServing, @unchecked Sendable {
    private let lock = NSLock()
    private let unsaveFailure: Error?
    private var hasStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private var isReleased = false
    private var unsaves = 0

    init(unsaveFailure: Error? = nil) { self.unsaveFailure = unsaveFailure }

    /// How many unsaves really reached the service: a refused second tap must not add one.
    var unsaveCallCount: Int { locked { unsaves } }

    func savePose(poseId: String) async throws {}

    func unsavePose(poseId: String) async throws {
        let waiters: [CheckedContinuation<Void, Never>] = locked {
            unsaves += 1
            hasStarted = true
            let waiters = startWaiters
            startWaiters = []
            return waiters
        }
        waiters.forEach { $0.resume() }

        await withCheckedContinuation { (pending: CheckedContinuation<Void, Never>) in
            let alreadyReleased: Bool = locked {
                guard !isReleased else { return true }
                releaseWaiter = pending
                return false
            }
            if alreadyReleased { pending.resume() }
        }
        if let unsaveFailure { throw unsaveFailure }
    }

    /// Waits until the model actually called the service, so the assertions run against a real request
    /// and not against a race.
    func waitUntilUnsaving() async {
        let alreadyStarted: Bool = locked { hasStarted }
        guard !alreadyStarted else { return }
        await withCheckedContinuation { (pending: CheckedContinuation<Void, Never>) in
            let alreadyStarted: Bool = locked {
                guard !hasStarted else { return true }
                startWaiters.append(pending)
                return false
            }
            if alreadyStarted { pending.resume() }
        }
    }

    /// Lets the held request answer.
    func releaseUnsaving() {
        let pending: CheckedContinuation<Void, Never>? = locked {
            isReleased = true
            let pending = releaseWaiter
            releaseWaiter = nil
            return pending
        }
        pending?.resume()
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


/// A pose remote that records which feed the adapter asked for. The Saved screen's whole defect was a
/// right-looking list read from the wrong collection, so the feed is the assertion, not the rows.
private final class RecordingPoseRemote: PoseRemoteFetching, @unchecked Sendable {
    var communityItems: [CommunityPose] = []
    var savedItems: [CommunityPose] = []
    private(set) var communityCallCount = 0
    private(set) var savedCallCount = 0

    func fetchCommunity(page: Int, limit: Int, query: String?) async throws -> PoseRemotePage {
        communityCallCount += 1
        return PoseRemotePage(poses: communityItems, total: communityItems.count)
    }

    func fetchSaved(page: Int, limit: Int) async throws -> PoseRemotePage {
        savedCallCount += 1
        return PoseRemotePage(poses: savedItems, total: savedItems.count)
    }
}

/// One wire-shaped pose, the way the server answers the saved route.
private func savedRouteRemotePose(_ id: String, name: String) throws -> CommunityPose {
    try JSONDecoder().decode(CommunityPose.self, from: Data("""
    {"poseId":"\(id)","name":"\(name)","skeletonUrl":"/s.png","thumbnailUrl":"/t.jpg","status":"published"}
    """.utf8))
}

/// A boundary that starts signed in, for the "the session changed under the tap" case.
private final class SignedInTokenStorage: TokenStoring, @unchecked Sendable {
    private var credentials: SessionCredentials? = SessionCredentials(
        accessToken: "access",
        refreshToken: "refresh"
    )

    func saveCredentials(_ credentials: SessionCredentials) { self.credentials = credentials }
    func loadCredentials() -> SessionCredentials? { credentials }
    func clearCredentials() { credentials = nil }
}

/// A stand-in for the account's saved collection **as a server**: the read answers from the same id list
/// the bookmark calls mutate, so "unsave → leave Saved → come back" is asserted against the server's own
/// state instead of against one model instance's memory.
private final class SavedCollectionServer: PoseServing, PoseBookmarkServing, @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [String]
    private var unsaves = 0
    private var saves = 0
    private var reads = 0
    private var _unsavedPoseID: String?
    private var _unsaveError: Error?

    init(ids: [String]) { self.ids = ids }

    var savedIDs: [String] { locked { ids } }
    /// How many window reads this "server" answered: a session reset re-reads the collection.
    var posesPageCallCount: Int { locked { reads } }
    var unsaveCallCount: Int { locked { unsaves } }
    var saveCallCount: Int { locked { saves } }
    var unsavedPoseID: String? { locked { _unsavedPoseID } }

    var unsaveError: Error? {
        get { locked { _unsaveError } }
        set { locked { _unsaveError = newValue } }
    }

    private func pose(_ id: String) -> NativePose {
        NativePose(
            id: id,
            name: "Pose \(id)",
            category: "Standing",
            imageURL: nil,
            instructions: ["Stand a step away from the window."],
            isSaved: true
        )
    }

    // MARK: PoseServing — the saved route's answer

    func poses(query: String?) async throws -> [NativePose] { savedIDs.map(pose) }

    func posesPage(query: String?, offset: Int, limit: Int) async throws -> PosePage {
        locked { reads += 1 }
        let rows = savedIDs.map(pose)
        let start = min(max(0, offset), rows.count)
        let window = Array(rows[start..<min(rows.count, start + limit)])
        return PosePage(poses: window, hasMore: start + window.count < rows.count, consumed: window.count)
    }

    func pose(id: String) async throws -> NativePose {
        guard savedIDs.contains(id) else { throw PoseAdapterError.poseNotFound(id) }
        return pose(id)
    }

    // MARK: PoseBookmarkServing — what the tap does to the server

    func savePose(poseId: String) async throws {
        locked {
            saves += 1
            if !ids.contains(poseId) { ids.append(poseId) }
        }
    }

    func unsavePose(poseId: String) async throws {
        let error: Error? = locked {
            unsaves += 1
            _unsavedPoseID = poseId
            return _unsaveError
        }
        if let error { throw error }
        locked { ids.removeAll { $0 == poseId } }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
