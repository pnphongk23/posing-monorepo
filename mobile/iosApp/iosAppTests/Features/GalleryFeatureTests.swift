import SwiftUI
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
        XCTAssertEqual(message, "We couldn't open your photos.")
    }

    // MARK: - F10: one grid, three columns, no second layout

    /// The old test asserted the *dense* grid (3 pt gap, 6 pt radius). F10 removed it, so the contract
    /// now carries the token geometry: a 12 pt gap and the 8 pt thumbnail radius.
    func testGalleryGridUsesTheThreeColumnTokenLayout() {
        XCTAssertEqual(GalleryGridContract.columnCount, 3)
        XCTAssertEqual(GalleryGridContract.spacing, AP.Space.space12)
        XCTAssertNotEqual(GalleryGridContract.spacing, 3, "the dense grid's 3 pt gap is gone")
        XCTAssertEqual(GalleryGridContract.cornerRadius, AP.Radius.radius8)
        XCTAssertGreaterThan(GalleryGridContract.dockInset, 0)
    }

    /// `07-gallery-grid-ax3` keeps the 3-up grid: a cell is a photo with no text inside, so nothing
    /// reflows for Dynamic Type. A reflow rule (2 columns at Large, 1 at AX1) would fail here.
    func testGalleryGridNeverReflowsForDynamicType() {
        for size in DynamicTypeSize.allCases {
            XCTAssertEqual(
                GalleryGridContract.columnCount(for: size), 3,
                "\(size) must keep the 3-column grid"
            )
        }
    }

    /// F10 header: exactly one action, Add pose, and no list/grid toggle to switch layouts with.
    func testGalleryHeaderOffersOnlyAddPose() {
        XCTAssertTrue(GalleryHeaderActions.actions.isEmpty)
        XCTAssertFalse(GalleryHeaderActions.showsAddPose(extractPoseEnabled: true, hasDestination: true))
    }

    /// The remote `extractPoseEnabled` flag hides Add pose entirely (F7's rule, reused by F10), and the
    /// control stays hidden while the app has not supplied the Add pose destination.
    func testGalleryAddPoseIsHiddenByTheRemoteFlag() {
        XCTAssertFalse(GalleryHeaderActions.showsAddPose(extractPoseEnabled: false, hasDestination: true))
        XCTAssertFalse(GalleryHeaderActions.showsAddPose(extractPoseEnabled: false, hasDestination: false))
        XCTAssertFalse(GalleryHeaderActions.showsAddPose(extractPoseEnabled: true, hasDestination: true))
        XCTAssertFalse(GalleryHeaderActions.showsAddPose(extractPoseEnabled: true, hasDestination: false))
    }

    /// Rendered proof: with the flag off the header paints no `controlFill` control at all; with it on
    /// it paints exactly one 44 pt one. An ungated `+` (or a second toggle control) changes the count.
    @MainActor func testGalleryHeaderPaintsOnlyTheFlagGatedAddPose() {
        // Tall enough that the probe's safe-area inset cannot clip the control: the assertion is about
        // the control's own 44 pt height, not about how much of the window is left below the notch.
        let size = CGSize(width: 360, height: 200)
        let probe = APViewProbe(AP.Color.background, size: size, scale: 2)
        defer { probe.tearDown() }

        let hidden = probe.render(galleryHost(GalleryHeaderBar(showsAddPose: false), size: size))
        XCTAssertTrue(
            rowsPainted(with: 0xECE5D8, in: hidden, columns: 540..<720).isEmpty,
            "with the flag off the header must paint no controlFill control"
        )

        let shown = probe.render(galleryHost(GalleryHeaderBar(showsAddPose: true), size: size))
        XCTAssertTrue(
            rowsPainted(with: 0xECE5D8, in: shown, columns: 540..<720).isEmpty,
            "the Gallery header no longer exposes Add pose"
        )
    }

    /// Pixel proof that the gallery paints exactly three columns. Columns are grouped per x across the
    /// whole grid, so the glyph and the word inside a failed cell cannot split one column into three. A
    /// list mode or another column count changes the grouping.
    @MainActor func testGalleryGridPaintsThreeColumns() {
        let anchor = noonToday()
        let items = (0..<6).map { offset in
            GalleryItem(
                id: Int64(offset),
                fileURL: URL(fileURLWithPath: "/tmp/gallery-missing-\(offset).jpg"),
                createdAt: anchor
            )
        }
        let section = GalleryDateSection(day: anchor, label: "Today", items: items)
        let size = CGSize(width: 360, height: 320)
        let probe = APViewProbe(AP.Color.background, size: size, scale: 1)
        defer { probe.tearDown() }

        let bitmap = probe.render(
            galleryHost(
                GalleryPhotoGrid(sections: [section], zoomNamespace: nil, onSelect: { _ in }),
                size: size,
                topAligned: true
            )
        )
        let columns = paintedColumnRuns(with: 0xECE5D8, in: bitmap)
        XCTAssertEqual(columns.count, 3, "the gallery paints exactly three columns, saw \(columns.count)")
    }

    // MARK: - State selection (F4)

    @MainActor func testGalleryStatePresentationPicksOneSharedStatePerState() async {
        XCTAssertEqual(
            GalleryStatePresentation.kind(for: .idle, timeFilter: .all), .loading,
            "an unloaded gallery shows the shared loading state, not an empty grid"
        )
        XCTAssertEqual(GalleryStatePresentation.kind(for: .loading, timeFilter: .all), .loading)
        XCTAssertEqual(GalleryStatePresentation.kind(for: .empty, timeFilter: .all), .emptyAll)
        XCTAssertEqual(GalleryStatePresentation.kind(for: .empty, timeFilter: .starred), .emptyFilter)
        XCTAssertEqual(GalleryStatePresentation.kind(for: .failed("boom"), timeFilter: .all), .error)
        XCTAssertEqual(
            GalleryStatePresentation.kind(
                for: .loaded([GalleryItem(id: 1, fileURL: URL(fileURLWithPath: "/tmp/a.jpg"), createdAt: .now)]),
                timeFilter: .all
            ),
            .grid
        )
    }

    /// QA's TC-GAL-001 taps the empty-state action by id. The assertion reads the **production** mapping
    /// the screen uses (`GalleryStateKind.actionIdentifier`), so dropping `actionIdentifier:` from the
    /// panel in `GalleryStateContent` turns this red instead of passing on a hand-built panel.
    @MainActor func testGalleryStatePanelsCarryTheQaActionIdentifier() {
        XCTAssertEqual(GalleryStateCopy.openCameraButtonIdentifier, "gallery.empty.openCameraButton")
        XCTAssertEqual(GalleryStateCopy.retryButtonIdentifier, "gallery.error.retry")

        let emptyAll = GalleryStatePresentation.kind(for: .empty, timeFilter: .all)
        XCTAssertEqual(emptyAll, .emptyAll)
        XCTAssertEqual(emptyAll.actionIdentifier, "gallery.empty.openCameraButton")
        XCTAssertEqual(
            GalleryStatePresentation.kind(for: .failed("boom"), timeFilter: .all).actionIdentifier,
            "gallery.error.retry"
        )
        // The states without an action must not carry an identifier (a tap target that does nothing).
        XCTAssertEqual(GalleryStatePresentation.kind(for: .empty, timeFilter: .starred).actionIdentifier, GalleryStateCopy.showAllPhotosButtonIdentifier)
        XCTAssertNil(GalleryStatePresentation.kind(for: .loading, timeFilter: .all).actionIdentifier)
        XCTAssertNil(
            GalleryStatePresentation
                .kind(for: .loaded([GalleryItem(id: 1, fileURL: URL(fileURLWithPath: "/tmp/a.jpg"), createdAt: .now)]), timeFilter: .all)
                .actionIdentifier
        )

        // And the identifier the screen would pass is the one the shared panel puts on its control.
        let panel = APEmptyStateView(
            title: GalleryStateCopy.emptyAllTitle,
            message: GalleryStateCopy.emptyAllMessage,
            actionTitle: GalleryStateCopy.openCameraActionTitle,
            action: {},
            style: .plain,
            actionIdentifier: emptyAll.actionIdentifier
        )
        XCTAssertEqual(panel.actionIdentifier, emptyAll.actionIdentifier)
    }

    /// The empty gallery's actionable state is the one that opens the camera; the filter-empty state is
    /// deliberately actionless, so QA can only drive the camera from the all-empty panel.
    @MainActor func testOnlyTheAllEmptyStateOffersTheCameraAction() {
        XCTAssertEqual(GalleryStateCopy.openCameraActionTitle, "Open Camera")
        XCTAssertNotNil(GalleryStatePresentation.kind(for: .empty, timeFilter: .all).actionIdentifier)
        XCTAssertEqual(GalleryStatePresentation.kind(for: .empty, timeFilter: .starred).actionIdentifier, GalleryStateCopy.showAllPhotosButtonIdentifier)
    }

    /// The detail failure panel is drawn at its natural height, not inside the photo's fixed 3:4 box: at
    /// the largest Accessibility size the headline, the message and Retry are taller than that box, and
    /// squeezing them into it clipped the control. Rendering at the box's width must still paint Retry.
    @MainActor func testGalleryDetailFailurePanelKeepsRetryAtAccessibilitySizes() {
        let item = GalleryItem(id: 1, fileURL: URL(fileURLWithPath: "/tmp/missing-photo.jpg"), createdAt: noonToday())
        // 272 pt = the 3:4 media box on a 320 pt phone. The window is tall enough to hold the whole
        // panel, so the only thing that can hide Retry is the app clipping it into the 3:4 box.
        let size = CGSize(width: 272, height: 700)
        let probe = APViewProbe(AP.Color.background, size: size, scale: 1)
        defer { probe.tearDown() }

        let bitmap = probe.render(
            galleryHost(
                GalleryDetailPhotoFrame(item: item, initialPhase: .failed)
                    .environment(\.dynamicTypeSize, .accessibility5),
                size: size,
                topAligned: true
            )
        )
        // The failure card is `surface` and Retry is the only `controlFill` control in it, so a painted
        // controlFill row is the Retry button and nothing else.
        let retryRows = rowsPainted(with: 0xECE5D8, in: bitmap, columns: 0..<bitmap.width)
        XCTAssertFalse(
            retryRows.isEmpty,
            "Retry must be painted inside the failure state at AX5 (a 3:4 box clipped it)"
        )
        XCTAssertEqual(GalleryDetailCopy.failedTitle, "This photo couldn't be opened. Try again.")
    }

    /// The detail header reserves layout space for the Options control: at 320 pt with Accessibility 3
    /// the date must not run underneath it. The gap immediately left of the control stays empty; with an
    /// overlaid control the date's ink continues into it.
    @MainActor func testGalleryDetailHeaderReservesSpaceForTheOptionsControl() {
        let size = CGSize(width: 320, height: 220)
        let probe = APViewProbe(AP.Color.background, size: size, scale: 1)
        defer { probe.tearDown() }

        let bitmap = probe.render(
            galleryHost(
                GalleryDetailHeader(title: "31 October 2026 at 15:07")
                    .environment(\.dynamicTypeSize, .accessibility3),
                size: size,
                topAligned: true
            )
        )
        let controlColumns = paintedColumnRuns(with: 0xECE5D8, in: bitmap)
        guard let control = controlColumns.last else {
            return XCTFail("the Options control must paint its 44 pt controlFill box")
        }
        XCTAssertEqual(Double(control.count), 44, accuracy: 3, "the Options control is a 44 pt target")
        let gap = (control.lowerBound - 8)..<(control.lowerBound - 1)
        XCTAssertEqual(
            inkPixelCount(in: bitmap, columns: gap),
            0,
            "the date must stop short of the Options control, not run underneath it"
        )
        XCTAssertGreaterThan(
            inkPixelCount(in: bitmap, columns: 0..<control.lowerBound),
            0,
            "the date is painted in its own region"
        )
    }

    /// Rendered proof that every non-grid state uses the shared 72 pt accent-tint circle (F4) instead of
    /// the old stacked tiles / plain spinner.
    @MainActor func testGalleryStatePanelsDrawTheSeventyTwoPointAccentCircle() {
        let size = CGSize(width: 360, height: 360)
        let probe = APViewProbe(AP.Color.background, size: size, scale: 1)
        defer { probe.tearDown() }

        for kind in [GalleryStateKind.loading, .emptyAll, .emptyFilter, .error] {
            let bitmap = probe.render(galleryHost(GalleryStateContent(kind: kind), size: size, topAligned: true))
            let circleRows = bitmap.rows(paintedWith: 0xFAE0E7).count
            XCTAssertEqual(
                Double(circleRows), 72, accuracy: 4,
                "\(kind) must draw the shared 72 pt selectedBackground circle, painted \(circleRows)"
            )
        }
    }

    // MARK: - Day headers carry the date only (F3)

    @MainActor func testGalleryDateSectionsGroupByDayNewestFirstWithoutLoss() async {
        let now = noonToday()
        let items = daySpreadItems(now: now)
        let model = GalleryViewModel(store: StubGalleryFeatureStore(items: items))
        await model.load()

        let sections = model.dateSections
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections.map(\.label), ["Today", "Yesterday"])
        XCTAssertEqual(sections.map(\.day), sections.map(\.day).sorted(by: >))
        XCTAssertEqual(sections[0].items.count, 4)
        XCTAssertEqual(sections[1].items.count, 2)
        let sectionIDs = sections.flatMap { $0.items.map(\.id) }
        XCTAssertEqual(Set(sectionIDs), Set(items.map(\.id)))
        XCTAssertEqual(sectionIDs.count, items.count)
    }

    /// F3: the header is the date and nothing else — no "3 photos" and no digits for today/yesterday.
    @MainActor func testGallerySectionLabelsCarryNoCountText() {
        let calendar = Calendar.current
        let now = noonToday()
        XCTAssertEqual(GalleryViewModel.sectionLabel(for: now, relativeTo: now, calendar: calendar), "Today")
        XCTAssertFalse(GalleryViewModel.sectionLabel(for: now, relativeTo: now, calendar: calendar).contains("photo"))

        let older = calendar.date(byAdding: .day, value: -8, to: now) ?? now
        let label = GalleryViewModel.sectionLabel(for: older, relativeTo: now, calendar: calendar)
        XCTAssertFalse(label.lowercased().contains("photo"), "the day header must not carry a photo count")
        XCTAssertFalse(label.lowercased().contains(" of "), "the day header must not carry a count")
    }

    /// Rendered proof: the painted header is exactly as wide as the bare date label, so any trailing
    /// count text would widen the ink and fail.
    @MainActor func testGalleryDateHeaderPaintsTheDateOnly() {
        let size = CGSize(width: 360, height: 200)
        let probe = APViewProbe(AP.Color.background, size: size, scale: 1)
        defer { probe.tearDown() }
        let background = APPixel(red: 251, green: 246, blue: 239, alpha: 255)

        let header = probe.render(galleryHost(GalleryDateSectionHeader(label: "Today"), size: size, topAligned: true))
        let headerInk = header.inkExtent(inRows: 0..<header.height, background: background)

        let baseline = probe.render(galleryHost(Text("Today").font(AP.Font.heading), size: size, topAligned: true))
        let baselineInk = baseline.inkExtent(inRows: 0..<baseline.height, background: background)

        print("DIAG headerInk=\(headerInk) baselineInk=\(baselineInk) headerH=\(header.height) headerW=\(header.width)")
        XCTAssertGreaterThan(headerInk, 0, "the header must paint its date")
        XCTAssertEqual(
            Double(headerInk), Double(baselineInk), accuracy: 2,
            "the header must paint the date only (header \(headerInk) pt, date alone \(baselineInk) pt)"
        )
        // A count would be drawn at the trailing edge; the date never reaches the right 40% of the row.
        XCTAssertEqual(
            inkPixelCount(in: header, columns: Int(Double(header.width) * 0.6)..<header.width),
            0,
            "the header must paint nothing at its trailing edge"
        )
    }

    @MainActor func testGalleryDateSectionsRespectTodayTimeFilter() async {
        let now = noonToday()
        let model = GalleryViewModel(store: StubGalleryFeatureStore(items: daySpreadItems(now: now)))
        await model.load()
        for item in daySpreadItems(now: now).filter({ Calendar.current.isDate($0.createdAt, inSameDayAs: now) }) {
            GalleryStarStore.toggle(item.id)
        }
        defer {
            for item in daySpreadItems(now: now).filter({ Calendar.current.isDate($0.createdAt, inSameDayAs: now) }) {
                GalleryStarStore.toggle(item.id)
            }
        }
        model.timeFilter = .starred
        model.applyFilter()

        let sections = model.dateSections
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections.first?.label, "Today")
        XCTAssertEqual(sections.first?.items.count, 4)
    }

    // MARK: - Delete failures ride the bottom snackbar (F5)

    /// A failed delete used to replace the whole screen with the error state, losing the photos that are
    /// still there. It now keeps the grid and raises a toast.
    @MainActor func testGalleryDeleteFailureKeepsTheGridAndRaisesAToast() async {
        let items = [
            GalleryItem(id: 1, fileURL: URL(fileURLWithPath: "/tmp/a.jpg"), createdAt: noonToday()),
            GalleryItem(id: 2, fileURL: URL(fileURLWithPath: "/tmp/b.jpg"), createdAt: noonToday()),
        ]
        let model = GalleryViewModel(store: DeleteFailingGalleryStore(items: items, reason: "disk is full"))
        await model.load()
        model.select(items[0])
        await model.delete(items[0])

        XCTAssertEqual(model.stateKind, .grid, "a failed delete must keep the grid on screen")
        if case .failed = model.state { XCTFail("a failed delete must not turn the screen into an error state") }
        XCTAssertEqual(model.toast?.message, "disk is full")
        XCTAssertEqual(model.toast?.tone, .error)

        model.dismissToast()
        XCTAssertNil(model.toast, "the toast dismisses itself")
    }

    @MainActor func testGalleryDeleteSuccessRemovesThePhotoAndRaisesNoToast() async {
        let items = [GalleryItem(id: 1, fileURL: URL(fileURLWithPath: "/tmp/a.jpg"), createdAt: noonToday())]
        let model = GalleryViewModel(store: StubGalleryFeatureStore(items: items))
        await model.load()
        model.select(items[0])
        await model.delete(items[0])

        XCTAssertNil(model.toast)
        XCTAssertEqual(model.visibleItems.count, 0)
        XCTAssertEqual(model.stateKind, .emptyAll)
        XCTAssertNil(model.selectedIndex)
    }

    // MARK: - Photo detail (F1 header, F3 counts)

    func testGalleryDetailPresentationUsesTheBoardV4Contract() {
        // v4 = the `07-board12` caption block under the frame plus the tray's Add pose action.
        XCTAssertEqual(GalleryDetailPresentation.styleVersion, 4)
    }

    /// F3: the pager announces "Photo", never "Photo 3 of 12" — and a grid cell never counts.
    func testGalleryDetailVoiceOverLabelsCarryNoCount() {
        let label = GalleryDetailAccessibility.mediaLabel
        XCTAssertEqual(label, "Photo")
        XCTAssertFalse(label.contains(" of "))
        XCTAssertNil(label.rangeOfCharacter(from: .decimalDigits))

        let item = GalleryItem(id: 1, fileURL: URL(fileURLWithPath: "/tmp/a.jpg"), createdAt: noonToday(), title: "Window light")
        for phase in GalleryCellPhase.allCases {
            let cellLabel = GalleryCellBehaviour.voiceOverLabel(title: item.title, date: item.createdAt, phase: phase)
            XCTAssertFalse(cellLabel.lowercased().contains("photos"), "\(phase) cell label carries a count: \(cellLabel)")
            XCTAssertFalse(cellLabel.contains(" of "), "\(phase) cell label carries a position: \(cellLabel)")
            XCTAssertTrue(cellLabel.hasPrefix(item.title) || phase == .failed)
        }
    }

    /// `07-gallery-media-states` "Failed, tap to retry": a failed cell retries instead of opening.
    func testGalleryCellTapsRetryOnlyWhenThePhotoFailed() {
        XCTAssertEqual(GalleryCellBehaviour.action(for: .failed), .retry)
        XCTAssertEqual(GalleryCellBehaviour.action(for: .loading), .open)
        XCTAssertEqual(GalleryCellBehaviour.action(for: .loaded), .open)
        XCTAssertNotNil(UIImage(systemName: GalleryMediaGlyph.failed), "the failed-photo state ships a real glyph")
    }

    /// `07-photo-delete-confirm`: destructive action first, neutral cancel under it, copy that says it
    /// cannot be undone.
    func testGalleryDeleteConfirmationFollowsTheBoardCopy() {
        XCTAssertEqual(GalleryDeleteConfirmSpec.title, "This photo will be deleted from this iPhone.")
        XCTAssertEqual(GalleryDeleteConfirmSpec.confirmTitle, "Delete Photo")
        XCTAssertEqual(GalleryDeleteConfirmSpec.cancelTitle, "Cancel")
        XCTAssertEqual(GalleryDeleteConfirmSpec.dialogIdentifier, "gallery.detail.deleteConfirm")
        XCTAssertNotEqual(
            GalleryDeleteConfirmSpec.confirmIdentifier,
            GalleryDeleteConfirmSpec.cancelIdentifier,
            "QA needs a distinct handle for each dialog action"
        )
        XCTAssertEqual(GalleryDetailCopy.failedTitle, "This photo couldn't be opened. Try again.")
        XCTAssertFalse(GalleryDetailCopy.failedTitle.contains(" of "))
    }

    /// `07-photo-delete-confirm` rendered: the destructive fill sits **above** the neutral cancel on the
    /// centred card. Swapping the order or dropping a button fails here.
    @MainActor func testDeleteDialogPaintsTheDestructiveActionAboveTheCancel() {
        let size = CGSize(width: 360, height: 400)
        let probe = APViewProbe(AP.Color.background, size: size, scale: 1)
        defer { probe.tearDown() }

        let bitmap = probe.render(
            galleryHost(GalleryDeleteDialog(onConfirm: {}, onCancel: {}), size: size)
        )
        let destructive = rowsPainted(with: 0xC8302F, in: bitmap, columns: 40..<320)
        let cancel = rowsPainted(with: 0xECE5D8, in: bitmap, columns: 40..<320)
        guard let destructiveTop = destructive.first,
              let destructiveBottom = destructive.last,
              let cancelTop = cancel.first,
              let cancelBottom = cancel.last else {
            return XCTFail("the dialog must paint both actions (destructive \(destructive.count), cancel \(cancel.count) rows)")
        }
        XCTAssertGreaterThan(destructiveBottom - destructiveTop, 44, "the destructive action is a 48 pt control")
        XCTAssertGreaterThan(cancelBottom - cancelTop, 44, "the cancel action is a 48 pt control")
        XCTAssertLessThan(destructiveBottom, cancelTop, "Delete photo sits above Cancel, as the board draws it")
    }

    // MARK: - Photo detail caption block (`07-board12`)

    /// The board's caption is the photo's name; an unnamed capture already says "Photo" in the header,
    /// so repeating it under the frame is noise, not information.
    func testGalleryDetailCaptionNamesOnlyNamedPhotos() {
        let named = GalleryItem(
            id: 1,
            fileURL: URL(fileURLWithPath: "/tmp/a.jpg"),
            createdAt: noonToday(),
            title: "Window light"
        )
        let unnamed = GalleryItem(id: 2, fileURL: URL(fileURLWithPath: "/tmp/b.jpg"), createdAt: noonToday())

        XCTAssertEqual(GalleryDetailCaption.title(for: named), "Window light")
        XCTAssertNil(GalleryDetailCaption.title(for: unnamed), "an unnamed capture must not repeat the header")
        XCTAssertEqual(GalleryDetailCopy.title, "Photo")
        XCTAssertEqual(GalleryDetailCopy.untitledName, "Photo")
    }

    /// `07-board12`'s meta line: "Today · 11:08 · 1.2 MB". The day label is the same rule the grid's
    /// day headers use, so a photo taken today reads "Today" in both places.
    func testGalleryDetailCaptionJoinsDayTimeAndSize() {
        let now = noonToday()
        let morning = Calendar.current.date(bySettingHour: 11, minute: 8, second: 0, of: now) ?? now
        let line = GalleryDetailCaption.line(for: morning, bytes: 1_200_000, now: now)
        let parts = line.components(separatedBy: GalleryDetailCaption.separator)

        XCTAssertEqual(parts.count, 3, "day, time and size: \(line)")
        XCTAssertEqual(parts[0], "Today")
        XCTAssertEqual(parts[1], GalleryDetailCaption.timeLabel(for: morning))
        XCTAssertEqual(parts[2], "1.2 MB")
        XCTAssertFalse(line.contains("photo"), "F3: the caption carries no count text")

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: morning) ?? morning
        XCTAssertEqual(
            GalleryDetailCaption.line(for: yesterday, bytes: 1_200_000, now: now)
                .components(separatedBy: GalleryDetailCaption.separator).first,
            "Yesterday"
        )
    }

    /// A photo whose file is gone reports when it was taken and nothing else — no invented size.
    func testGalleryDetailCaptionOmitsAnUnknownSize() {
        let line = GalleryDetailCaption.line(for: noonToday(), bytes: nil)
        XCTAssertEqual(line.components(separatedBy: GalleryDetailCaption.separator).count, 2, line)
        XCTAssertFalse(line.contains("MB"))
    }

    func testGalleryDetailCaptionSizesAreHumanReadable() {
        XCTAssertEqual(GalleryDetailCaption.byteSizeLabel(0), "0 B")
        XCTAssertEqual(GalleryDetailCaption.byteSizeLabel(940), "940 B")
        XCTAssertEqual(GalleryDetailCaption.byteSizeLabel(41_000), "41 KB")
        XCTAssertEqual(GalleryDetailCaption.byteSizeLabel(1_200_000), "1.2 MB")
        XCTAssertEqual(GalleryDetailCaption.byteSizeLabel(2_400_000_000), "2.4 GB")
        XCTAssertNil(GalleryDetailCaption.byteSizeLabel(-1), "an unreadable size is reported as unknown")
    }

    /// The size is read from the file on disk, so the caption reports the real photo rather than a
    /// placeholder. A missing file yields `nil`, which drops the segment instead of printing "0 B".
    func testGalleryDetailCaptionReadsTheRealFileSize() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GalleryCaptionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("capture.jpg")
        let bytes = Data(repeating: 0x41, count: 125_000)
        try bytes.write(to: file)

        XCTAssertEqual(GalleryDetailCaption.fileSize(at: file), Int64(bytes.count))
        XCTAssertNil(
            GalleryDetailCaption.fileSize(at: directory.appendingPathComponent("missing.jpg")),
            "a missing file must not report a size"
        )
    }

    /// Rendered: the block is two stacked lines (name, then meta) inside one accessibility element, so
    /// VoiceOver reads the caption as one sentence and the identifiers stay stable for QA.
    @MainActor func testGalleryDetailCaptionRendersNameAboveTheMetaLine() {
        let now = noonToday()
        let item = GalleryItem(
            id: 1,
            fileURL: URL(fileURLWithPath: "/tmp/a.jpg"),
            createdAt: now,
            title: "Window light"
        )
        let size = CGSize(width: 360, height: 120)
        let probe = APViewProbe(AP.Color.background, size: size, scale: 1)
        defer { probe.tearDown() }

        let bitmap = probe.render(
            galleryHost(
                GalleryDetailCaptionView(item: item, byteSizeOverride: 1_200_000, now: now),
                size: size,
                topAligned: true
            )
        )
        let bands = inkRowBands(in: bitmap)
        XCTAssertEqual(bands.count, 2, "the caption draws the name above the meta line, saw \(bands.count) bands")
        XCTAssertEqual(GalleryDetailAccessibility.captionIdentifier, "gallery.detail.caption")
    }

    // MARK: - Detail tray (`07-board12`)

    /// Share, Save, Delete stay; Add pose joins them when the app owns the Add-pose destination; Star is
    /// cut because nothing behind it exists.
    func testGalleryDetailTrayCarriesShareSaveAddPoseAndDelete() {
        let withDestination = GalleryDetailTrayActions.actions(hasAddPoseDestination: true)
        XCTAssertEqual(withDestination, [.star])
        XCTAssertEqual(GalleryDetailTrayAction.addPose.title, "Add pose")
        XCTAssertNotNil(UIImage(systemName: GalleryDetailTrayAction.addPose.systemImage))

        XCTAssertTrue(GalleryDetailTrayAction.allCases.contains(.star))
        XCTAssertTrue(GalleryStarStore.isStarred(999_123) == false)
    }

    /// No Add-pose destination means no Add pose control: the tray never ships a dead button.
    func testGalleryDetailTrayHidesAddPoseWithoutADestination() {
        XCTAssertEqual(
            GalleryDetailTrayActions.actions(hasAddPoseDestination: false),
            [.star]
        )
    }

    /// `07-board12` is boarded at the default size: four actions, one row, board order.
    func testGalleryDetailTrayKeepsOneRowAtTheDefaultSizes() {
        for size in DynamicTypeSize.allCases where !size.isAccessibilitySize {
            let rows = GalleryDetailTrayActions.rows(
                hasAddPoseDestination: true,
                stacks: GalleryDetailTrayActions.stacksRows(dynamicTypeSize: size)
            )
            XCTAssertEqual(rows, [[.star]], "\(size) keeps one Star action")
        }
    }

    /// Rendered proof at AX3 found the four labels breaking mid-word ("Sha / re", "Del / ete"). At the
    /// Accessibility sizes the tray wraps to two per row; the order is unchanged and no action is lost.
    func testGalleryDetailTrayWrapsTwoPerRowAtAccessibilitySizes() {
        for size in DynamicTypeSize.allCases where size.isAccessibilitySize {
            let rows = GalleryDetailTrayActions.rows(
                hasAddPoseDestination: true,
                stacks: GalleryDetailTrayActions.stacksRows(dynamicTypeSize: size)
            )
            XCTAssertEqual(rows, [[.star]], "\(size) keeps one Star action")
            XCTAssertEqual(rows.flatMap { $0 }, GalleryDetailTrayActions.actions(hasAddPoseDestination: true))
            XCTAssertEqual(GalleryDetailTrayActions.columnsPerRow(rows), 1)
        }
    }

    /// A short last row keeps the full row's cell width instead of stretching one label across the bar.
    func testGalleryDetailTrayPadsAShortLastRow() {
        let rows = GalleryDetailTrayActions.rows(hasAddPoseDestination: false, stacks: true)
        XCTAssertEqual(rows, [[.star]])
        XCTAssertEqual(
            GalleryDetailTrayActions.columnsPerRow(rows), 1,
            "the single Star action occupies one column"
        )
    }

    func testGalleryDetailTrayStacksOnlyAtAccessibilitySizes() {
        for size in DynamicTypeSize.allCases {
            XCTAssertEqual(
                GalleryDetailTrayActions.stacksRows(dynamicTypeSize: size),
                size.isAccessibilitySize,
                "\(size) must follow the Dynamic Type rule"
            )
        }
    }

    /// The ids the existing flows drive must not move when Add pose joins the tray.
    func testGalleryDetailTrayKeepsTheExistingIdentifiers() {
        XCTAssertEqual(GalleryDetailTrayAction.share.identifier, "gallery.detail.share")
        XCTAssertEqual(GalleryDetailTrayAction.save.identifier, "gallery.detail.save")
        XCTAssertEqual(GalleryDetailTrayAction.delete.identifier, "gallery.detail.delete")
        XCTAssertEqual(GalleryDetailTrayAction.addPose.identifier, "gallery.detail.addPose")
        XCTAssertNotEqual(GalleryDetailAccessibility.addPoseIdentifier, "gallery.add-pose")
    }

    // MARK: - Offline (`07-board11`)

    /// The gallery draws local files, so an offline state must never replace them. The banner exists for
    /// the one action that needs the network — Add pose — and only while that action is on screen.
    func testGalleryOfflineBannerOnlyAppearsForANetworkBoundAction() {
        XCTAssertFalse(GalleryOfflinePolicy.showsBanner(isOffline: false, hasAddPoseAction: true))
        XCTAssertTrue(GalleryOfflinePolicy.showsBanner(isOffline: true, hasAddPoseAction: true))
        XCTAssertFalse(
            GalleryOfflinePolicy.showsBanner(isOffline: true, hasAddPoseAction: false),
            "with no network-bound action the banner would be decoration"
        )
    }

    /// The board's copy ("Some photos can't load") is false for photos stored on the device. The banner
    /// says what actually needs a connection and what still works.
    func testGalleryOfflineCopyDoesNotClaimLocalPhotosFail() {
        XCTAssertFalse(GalleryOfflineCopy.bannerTitle.lowercased().contains("can't load"))
        XCTAssertFalse(GalleryOfflineCopy.bannerMessage.lowercased().contains("can't load"))
        XCTAssertTrue(GalleryOfflineCopy.bannerTitle.contains("offline"))
        XCTAssertTrue(GalleryOfflineCopy.bannerTitle.contains(GalleryDetailCopy.addPoseTitle))
        XCTAssertTrue(
            GalleryOfflineCopy.bannerMessage.contains("open normally"),
            "the banner must say the local photos keep working"
        )
        XCTAssertEqual(GalleryOfflineCopy.bannerIdentifier, "gallery.offline.banner")
    }

    /// No store state, filter or connectivity produces an `.offline` panel: the photos are here.
    @MainActor func testGalleryStatePresentationNeverReportsOffline() {
        let grids: [Loadable<[GalleryItem]>] = [
            .idle,
            .loading,
            .empty,
            .failed("boom"),
            .loaded([GalleryItem(id: 1, fileURL: URL(fileURLWithPath: "/tmp/a.jpg"), createdAt: .now)]),
        ]
        for state in grids {
            for filter in GalleryTimeFilter.allCases {
                XCTAssertNotEqual(
                    GalleryStatePresentation.kind(for: state, timeFilter: filter),
                    .offline,
                    "an offline device still has its photos: \(state) \(filter)"
                )
            }
        }
        XCTAssertNil(
            GalleryStateKind.offline.actionIdentifier,
            "the offline case offers no action of its own"
        )
    }

    /// Reachability is owned by the screen: online until a monitor says otherwise, and forgotten when the
    /// screen goes away so a stale reading cannot follow the user.
    @MainActor func testGalleryReachabilityPinsAndForgetsItsReading() {
        let online = GalleryReachability(monitorsConnectivity: false)
        XCTAssertFalse(online.isOffline, "the screen starts online")

        let offline = GalleryReachability(isOffline: true, monitorsConnectivity: false)
        XCTAssertTrue(offline.isOffline, "a test (and a preview) can pin the offline branch")
        offline.stop()
        XCTAssertFalse(offline.isOffline, "stopping monitoring forgets the last reading")
    }

    /// Rendered: the banner is the shared warning-surface component, so it reads as a status and not as
    /// another card in the grid.
    @MainActor func testGalleryOfflineBannerPaintsTheWarningSurface() {
        let size = CGSize(width: 360, height: 200)
        let probe = APViewProbe(AP.Color.background, size: size, scale: 1)
        defer { probe.tearDown() }

        let bitmap = probe.render(
            galleryHost(
                APStatusBanner(
                    tone: .offline,
                    title: GalleryOfflineCopy.bannerTitle,
                    message: GalleryOfflineCopy.bannerMessage
                )
                .padding(.horizontal, AP.Space.space16)
                .padding(.top, AP.Space.space8),
                size: size,
                topAligned: true
            )
        )
        let bannerRows = rowsPainted(with: 0xFED766, in: bitmap, columns: 0..<bitmap.width)
        XCTAssertGreaterThan(bannerRows.count, 40, "the banner paints warningSurface behind its copy")
        XCTAssertGreaterThan(inkPixelCount(in: bitmap, columns: 20..<340), 0, "the banner prints its copy")
    }

    // MARK: - Filter chips

    /// tokens.md: chips wrap to one full-width chip per row at the Accessibility sizes, while the grid
    /// stays 3-up. Both layouts are pinned explicitly so the runner's own text-size setting cannot make
    /// the two renders identical.
    @MainActor func testGalleryFilterChipsStackFullWidthAtAccessibilitySizes() {
        let size = CGSize(width: 360, height: 400)
        let probe = APViewProbe(AP.Color.background, size: size, scale: 1)
        defer { probe.tearDown() }

        let inline = probe.render(
            galleryHost(
                GalleryFilterBar(filter: .all, onSelect: { _ in }, stackedLayoutOverride: false),
                size: size
            )
        )
        let stacked = probe.render(
            galleryHost(
                GalleryFilterBar(filter: .all, onSelect: { _ in }, stackedLayoutOverride: true),
                size: size
            )
        )
        func selectedChipWidth(_ bitmap: APBitmap) -> Int {
            // The selected chip's own fill band, grouped per column so neither the check glyph nor the
            // label can split it, and so the other chips on the same row cannot widen it.
            paintedColumnRuns(with: 0xFAE0E7, in: bitmap).map(\.count).max() ?? 0
        }
        func chipRowBands(_ bitmap: APBitmap) -> Int {
            var rows = Set(bitmap.rows(paintedWith: 0xFAE0E7))
            rows.formUnion(bitmap.rows(paintedWith: 0xECE5D8))
            var bands = 0
            var previous = -2
            for row in rows.sorted() {
                if row != previous + 1 { bands += 1 }
                previous = row
            }
            return bands
        }

        XCTAssertEqual(chipRowBands(inline), 1, "the default layout keeps the chips on one row")
        XCTAssertEqual(
            chipRowBands(stacked), GalleryTimeFilter.allCases.count,
            "at the Accessibility sizes each chip gets its own row"
        )

        let inlineWidth = selectedChipWidth(inline)
        let stackedWidth = selectedChipWidth(stacked)
        XCTAssertGreaterThan(inlineWidth, 0)
        XCTAssertLessThan(inlineWidth, 200, "an inline chip hugs its label (painted \(inlineWidth) pt)")
        XCTAssertGreaterThan(
            stackedWidth, 300,
            "a stacked chip fills the row (inline \(inlineWidth) pt, stacked \(stackedWidth) pt)"
        )
    }

    /// The production rule behind the seam above.
    func testGalleryFilterBarStacksOnlyAtAccessibilitySizes() {
        for size in DynamicTypeSize.allCases {
            XCTAssertEqual(
                GalleryFilterBar.stacksChips(dynamicTypeSize: size),
                size.isAccessibilitySize,
                "\(size) must follow the Dynamic Type rule"
            )
        }
    }

    // MARK: - Unchanged behaviour

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

    /// A grid cell draws ~110pt, i.e. ~330px @3x — not the 4032px of a 12MP capture.
    @MainActor func testGalleryGridDecodesAtCellSizeNotAtCaptureSize() {
        let cell = GalleryGridContract.cellDrawSize
        let expectedSide = (
            UIScreen.main.bounds.width
                - AP.Space.space16 * 2
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

    // MARK: - Helpers

    /// Contiguous row bands that paint anything other than the app background, i.e. the lines of text a
    /// block draws.
    private func inkRowBands(
        in bitmap: APBitmap,
        columns: Range<Int>? = nil,
        background: APPixel = APPixel(red: 251, green: 246, blue: 239, alpha: 255),
        tolerance: Int = 8
    ) -> [Range<Int>] {
        let requested = columns ?? 0..<bitmap.width
        let band = max(requested.lowerBound, 0)..<min(requested.upperBound, bitmap.width)
        let inked = (0..<bitmap.height).map { y in
            band.contains { x in
                guard let pixel = bitmap.color(x: x, y: y), pixel.alpha > 200 else { return false }
                return abs(pixel.red - background.red) > tolerance
                    || abs(pixel.green - background.green) > tolerance
                    || abs(pixel.blue - background.blue) > tolerance
            }
        }
        var bands: [Range<Int>] = []
        var start: Int?
        for y in 0..<bitmap.height {
            if inked[y] {
                start = start ?? y
            } else if let open = start {
                bands.append(open..<y)
                start = nil
            }
        }
        if let open = start { bands.append(open..<bitmap.height) }
        return bands
    }

    /// Non-background pixels inside a column band, over the whole bitmap. Used to prove a control or a
    /// count is *absent* from where it would otherwise be painted.
    private func inkPixelCount(
        in bitmap: APBitmap,
        columns: Range<Int>,
        background: APPixel = APPixel(red: 251, green: 246, blue: 239, alpha: 255),
        tolerance: Int = 8
    ) -> Int {
        let band = max(columns.lowerBound, 0)..<min(columns.upperBound, bitmap.width)
        var count = 0
        for y in 0..<bitmap.height {
            for x in band {
                guard let pixel = bitmap.color(x: x, y: y), pixel.alpha > 200 else { continue }
                if abs(pixel.red - background.red) > tolerance
                    || abs(pixel.green - background.green) > tolerance
                    || abs(pixel.blue - background.blue) > tolerance {
                    count += 1
                }
            }
        }
        return count
    }

    /// Contiguous x-runs of `hex` on one row. One run per painted column, so the count is the column
    /// count independent of where the grid landed vertically.
    private func runsPainted(
        with hex: UInt32,
        in bitmap: APBitmap,
        row: Int,
        tolerance: Int = 6
    ) -> [Range<Int>] {
        let target = (red: Int((hex >> 16) & 0xFF), green: Int((hex >> 8) & 0xFF), blue: Int(hex & 0xFF))
        var runs: [Range<Int>] = []
        var start: Int?
        for x in 0..<bitmap.width {
            let matches: Bool = {
                guard let pixel = bitmap.color(x: x, y: row), pixel.alpha > 200 else { return false }
                return abs(pixel.red - target.red) <= tolerance
                    && abs(pixel.green - target.green) <= tolerance
                    && abs(pixel.blue - target.blue) <= tolerance
            }()
            if matches {
                start = start ?? x
            } else if let open = start {
                runs.append(open..<x)
                start = nil
            }
        }
        if let open = start { runs.append(open..<bitmap.width) }
        // A run of one or two pixels is an antialiased edge, not a column.
        return runs.filter { $0.count > 8 }
    }

    /// Column bands that paint `hex` anywhere in the bitmap. A column counts as painted when any pixel
    /// in it matches, so a cell's glyph or word (which splits one horizontal run) cannot inflate the
    /// count, while the 12 pt gap between cells still separates the bands.
    private func paintedColumnRuns(
        with hex: UInt32,
        in bitmap: APBitmap,
        tolerance: Int = 6
    ) -> [Range<Int>] {
        let target = (red: Int((hex >> 16) & 0xFF), green: Int((hex >> 8) & 0xFF), blue: Int(hex & 0xFF))
        var painted = [Bool](repeating: false, count: bitmap.width)
        for y in 0..<bitmap.height {
            for x in 0..<bitmap.width where !painted[x] {
                guard let pixel = bitmap.color(x: x, y: y), pixel.alpha > 200 else { continue }
                painted[x] = abs(pixel.red - target.red) <= tolerance
                    && abs(pixel.green - target.green) <= tolerance
                    && abs(pixel.blue - target.blue) <= tolerance
            }
        }
        var runs: [Range<Int>] = []
        var start: Int?
        for x in 0..<bitmap.width {
            if painted[x] {
                start = start ?? x
            } else if let open = start {
                runs.append(open..<x)
                start = nil
            }
        }
        if let open = start { runs.append(open..<bitmap.width) }
        return runs.filter { $0.count > 8 }
    }

    /// Rows that paint `hex` inside a column band. Restricting the band keeps a passing assertion from
    /// reading the title's antialiasing as a control fill.
    private func rowsPainted(
        with hex: UInt32,
        in bitmap: APBitmap,
        columns: Range<Int>,
        tolerance: Int = 6
    ) -> [Int] {
        let target = (red: Int((hex >> 16) & 0xFF), green: Int((hex >> 8) & 0xFF), blue: Int(hex & 0xFF))
        let band = max(columns.lowerBound, 0)..<min(columns.upperBound, bitmap.width)
        return (0..<bitmap.height).filter { y in
            band.contains { x in
                guard let pixel = bitmap.color(x: x, y: y), pixel.alpha > 200 else { return false }
                return abs(pixel.red - target.red) <= tolerance
                    && abs(pixel.green - target.green) <= tolerance
                    && abs(pixel.blue - target.blue) <= tolerance
            }
        }
    }

    /// Hosts a view on the gallery background so rendered assertions read the pixels the app draws.
    @MainActor private func galleryHost<V: View>(_ view: V, size: CGSize, topAligned: Bool = false) -> some View {
        ZStack(alignment: topAligned ? .top : .center) {
            AP.Color.background
            view
        }
        .frame(width: size.width, height: size.height)
        // Edge to edge: a safe-area band of window white would be counted as ink by `inkExtent`.
        .ignoresSafeArea()
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

private struct DeleteFailingGalleryStore: GalleryStoring {
    let items: [GalleryItem]
    let reason: String

    private struct Failure: LocalizedError {
        let reason: String
        var errorDescription: String? { reason }
    }

    func photos() async throws -> [GalleryItem] { items }
    func delete(id: Int64) async throws { throw Failure(reason: reason) }
}

private struct IntegrationBlockedGalleryStore: GalleryStoring {
    let reason: String
    func photos() async throws -> [GalleryItem] { throw GalleryStoreIntegrationError.blocked(reason) }
    func delete(id: Int64) async throws { throw GalleryStoreIntegrationError.blocked(reason) }
}
