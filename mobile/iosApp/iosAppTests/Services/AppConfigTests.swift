import XCTest
@testable import iosApp

final class AppConfigTests: XCTestCase {
    func testAccountFeatureFlagDefaultsToEnabled() {
        XCTAssertTrue(AppConfig().isAccountFeatureEnabled)
    }

    func testAccountFeatureFlagCanBeAppliedInBothDirections() {
        let config = AppConfig()

        config.applyAccountFeatureEnabled(false)
        XCTAssertFalse(config.isAccountFeatureEnabled)

        config.applyAccountFeatureEnabled(true)
        XCTAssertTrue(config.isAccountFeatureEnabled)
    }
}
