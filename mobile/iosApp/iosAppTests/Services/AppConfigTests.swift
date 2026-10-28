import XCTest
@testable import iosApp

final class AppConfigTests: XCTestCase {
    func testAccountFeatureFlagDefaultsToDisabled() {
        XCTAssertFalse(AppConfig().isAccountFeatureEnabled)
    }

    func testAccountFeatureFlagCanBeAppliedInBothDirections() {
        let config = AppConfig()

        config.applyAccountFeatureEnabled(false)
        XCTAssertFalse(config.isAccountFeatureEnabled)

        config.applyAccountFeatureEnabled(true)
        XCTAssertTrue(config.isAccountFeatureEnabled)
    }

    func testExtractPoseFeatureFlagDefaultsToEnabled() {
        XCTAssertTrue(AppConfig().isExtractPoseEnabled)
    }

    func testExtractPoseFeatureFlagCanBeAppliedInBothDirections() {
        let config = AppConfig()

        config.applyExtractPoseEnabled(false)
        XCTAssertFalse(config.isExtractPoseEnabled)

        config.applyExtractPoseEnabled(true)
        XCTAssertTrue(config.isExtractPoseEnabled)
    }

    func testPaywallFeatureFlagDefaultsToDisabled() {
        XCTAssertFalse(AppConfig().isPaywallEnabled, "Fail-safe: a fresh config never gates capture")
    }

    func testPaywallFeatureFlagCanBeAppliedInBothDirections() {
        let config = AppConfig()

        config.applyPaywallEnabled(true)
        XCTAssertTrue(config.isPaywallEnabled)
        config.applyPaywallEnabled(false)
        XCTAssertFalse(config.isPaywallEnabled)
    }

    func testCanExtractPosePureFunction() {
        XCTAssertTrue(AppConfig.canExtractPose(isEnabled: true))
        XCTAssertFalse(AppConfig.canExtractPose(isEnabled: false))
    }

    func testJobsEntryIsBlockedWhenPoseExtractionIsDisabled() {
        XCTAssertFalse(JobsEntryPolicy.canOpen(extractPoseEnabled: false))
        XCTAssertTrue(JobsEntryPolicy.canOpen(extractPoseEnabled: true))
    }
}
