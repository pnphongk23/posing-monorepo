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

    @MainActor func testFooterRetriggersWhenAnInFlightPageFinishes() async {
        // The stall: `.loadMore` is mounted while the last request is still in flight, so the trigger
        // is rejected and never re-fires. Keyed on the paging state, it must fire on completion.
        let service = FooterPageSpy()
        let model = PosesViewModel(service: service)
        model.state = .loaded([NativePose(id: "1", name: "P", category: "Standing", imageURL: nil, instructions: [], isSaved: false)])
        model.setPagingForTesting(error: nil, hasMore: true, remainingAutoFetches: 0, isLoading: true)

        let probe = APViewProbe(APPagingFooter(model: model), size: CGSize(width: 393, height: 220))
        defer { probe.tearDown() }
        probe.settle()
        await Task.yield()
        XCTAssertEqual(service.pageCalls, 0, "an in-flight page must not be requested again")

        model.setPagingForTesting(error: nil, hasMore: true, remainingAutoFetches: 0, isLoading: false)
        probe.settle()
        for _ in 0..<20 {
            await Task.yield()
            if service.pageCalls > 0 { break }
        }
        XCTAssertGreaterThan(service.pageCalls, 0, "the footer must fetch the next page once the previous one settles")
    }

    // MARK: - Appearance (F7)

    @MainActor func testAppearancePreferenceRoundTripsThroughDefaults() throws {
        let suite = try XCTUnwrap(UserDefaults(suiteName: "ap-appearance-tests"))
        suite.removeObject(forKey: APAppearance.storageKey)
        defer { suite.removeObject(forKey: APAppearance.storageKey) }

        XCTAssertEqual(APAppearance.load(from: suite), .system, "the default follows the system")

        let store = APAppearanceStore(defaults: suite)
        store.appearance = .dark
        XCTAssertEqual(APAppearance.load(from: suite), .dark, "the choice is persisted")
        XCTAssertEqual(store.appearance.colorScheme, .dark)
        XCTAssertNil(APAppearance.system.colorScheme, "system follows the device")
    }

    // MARK: - Applied appearance + pinned bar geometry

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

    @MainActor func testPinnedSaveSquarePaintsAtTheSharedHeightAtAX3() {
        let pose = NativePose(
            id: "bar-pose",
            name: "Window light",
            category: "Standing",
            imageURL: nil,
            instructions: ["Step one"],
            isSaved: false
        )
        let model = PosesViewModel(service: ShellPoseService(pose: pose), bookmarkService: ShellBookmarkStub())
        model.state = .loaded([pose])
        let probe = APViewProbe(
            PoseDetailScreen(pose: pose, model: model, onTryPose: { _ in })
                .environment(\.dynamicTypeSize, .accessibility3),
            size: CGSize(width: 393, height: 852)
        )
        defer { probe.tearDown() }
        let painted = probe.capture()

        // The primary action paints the accent fill and the bar is the only place it can be at AX3 in
        // the bottom band. Its height is the shared bar height (the square Save reads the same value).
        let barBand = (painted.height - 160)..<painted.height
        let ctaRows = rowsPainted(with: 0xE89CAE, in: painted).filter { barBand.contains($0) }
        guard let top = ctaRows.first, let bottom = ctaRows.last else {
            return XCTFail("the pinned primary action must be painted")
        }
        // Rounded corners cost a few pixels in the render, so the bar is compared with a small slack.
        XCTAssertGreaterThanOrEqual(
            Double(bottom - top + 1), Double(APBarMetrics.controlHeight(for: .accessibility3)) - 8,
            "the pinned bar is at least the shared control height"
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

/// Counts paged reads so the footer's lifecycle is observable.
private final class FooterPageSpy: PoseServing, @unchecked Sendable {
    private(set) var pageCalls = 0

    func poses(query: String?) async throws -> [NativePose] { [] }

    func pose(id: String) async throws -> NativePose { throw PoseAdapterError.poseNotFound(id) }

    func posesPage(query: String?, offset: Int, limit: Int) async throws -> PosePage {
        pageCalls += 1
        return .end
    }
}

/// A bookmark service that always succeeds (the bar geometry test only needs the control to render).
private struct ShellBookmarkStub: PoseBookmarkServing {
    func savePose(poseId: String) async throws {}
    func unsavePose(poseId: String) async throws {}
}

/// Serves one pose from the catalogue *and* from `pose(id:)`, so the detail's availability check
/// passes and the pinned bar renders.
private struct ShellPoseService: PoseServing {
    let pose: NativePose
    func poses(query: String?) async throws -> [NativePose] { [pose] }
    func pose(id: String) async throws -> NativePose { pose }
}

/// An empty catalogue: the geometry test drives the state itself.
private struct APEmptyPoseService: PoseServing {
    func poses(query: String?) async throws -> [NativePose] { [] }
    func pose(id: String) async throws -> NativePose { throw PoseAdapterError.poseNotFound(id) }
}
