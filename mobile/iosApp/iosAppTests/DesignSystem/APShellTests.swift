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
        let rows = APMoreMenuSpec.rows(isAddPoseEnabled: true, showsSaved: true, showsSettings: true)
        XCTAssertEqual(rows.map(\.title), ["Add pose", "Jobs", "Saved", "Settings"])
        XCTAssertEqual(rows.last?.systemImage, "gearshape", "Settings is the gear row")

        // Only the Jobs badge may carry a number: no row title carries one.
        for row in rows {
            XCTAssertFalse(
                row.title.contains(where: \.isNumber),
                "\(row.title) must not carry a count"
            )
        }
        XCTAssertEqual(
            APMoreMenuSpec.rows(isAddPoseEnabled: true, showsSaved: false, showsSettings: true).map(\.title),
            ["Add pose", "Jobs", "Settings"],
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
