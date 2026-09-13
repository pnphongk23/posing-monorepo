import SwiftUI
import XCTest
@testable import iosApp

final class SupportDestinationsTests: XCTestCase {
    func testLegalAndSupportDestinationsResolveToHTTPSURLs() {
        for raw in [
            SupportDestinations.termsOfService,
            SupportDestinations.privacyPolicy,
            SupportDestinations.support,
        ] {
            guard let url = SupportDestinations.webURL(raw) else {
                return XCTFail("\(raw) is not a usable web URL")
            }
            XCTAssertEqual(url.scheme, "https")
            XCTAssertNotNil(url.host)
        }

        XCTAssertNotNil(SupportDestinations.termsOfServiceURL)
        XCTAssertNotNil(SupportDestinations.privacyPolicyURL)
        XCTAssertNotNil(SupportDestinations.supportURL)
    }

    /// Regression guard: FEAT-015 `PA-015-04` names `aipose.app/terms|privacy`, but that
    /// domain does not resolve, so shipping it makes the row look dead — the bug this
    /// helper exists to prevent.
    func testLegalDestinationsDoNotUseTheUnresolvableHost() {
        XCTAssertEqual(SupportDestinations.termsOfServiceURL?.host, "sites.google.com")
        XCTAssertEqual(SupportDestinations.privacyPolicyURL?.host, "sites.google.com")
        XCTAssertFalse(SupportDestinations.termsOfService.contains("aipose.app"))
        XCTAssertFalse(SupportDestinations.privacyPolicy.contains("aipose.app"))
    }

    func testWebURLRejectsNonWebSchemesAndGarbage() {
        XCTAssertNil(SupportDestinations.webURL(""))
        XCTAssertNil(SupportDestinations.webURL("   "))
        XCTAssertNil(SupportDestinations.webURL("not a url"))
        XCTAssertNil(SupportDestinations.webURL("ftp://example.com/terms"))
        XCTAssertNil(SupportDestinations.webURL("mailto:help@example.com"))
        XCTAssertNil(SupportDestinations.webURL("https://"))
        XCTAssertNil(SupportDestinations.webURL("https://example.com/a b"))
        XCTAssertEqual(SupportDestinations.webURL("  https://example.com/terms  ")?.path, "/terms")
    }

    @MainActor func testCameraAccessStatusCopy() {
        XCTAssertEqual(CameraAccessStatus.allowed.label, "Allowed")
        XCTAssertEqual(CameraAccessStatus.denied.label, "Blocked")
        XCTAssertEqual(CameraAccessStatus.restricted.label, "Blocked")
        XCTAssertEqual(CameraAccessStatus.notDetermined.label, "Not set")
        XCTAssertEqual(CameraAccessStatus.unknown.label, "Unknown")
        XCTAssertEqual(CameraAccessStatus.allowed.badgeColor, AIPoseColor.accentGreen)
        XCTAssertEqual(CameraAccessStatus.denied.badgeColor, AIPoseColor.error)
    }
}
