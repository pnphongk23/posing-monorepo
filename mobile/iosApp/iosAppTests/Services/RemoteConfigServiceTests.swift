import XCTest
@testable import iosApp

final class RemoteConfigServiceTests: XCTestCase {
    func testResolveWithoutFirebaseUsesDefault() {
        let resolution = RemoteConfigService.resolveWithoutFirebase()
        XCTAssertEqual(resolution.url, RemoteConfigService.defaultURL)
        XCTAssertEqual(resolution.source, .default)
    }

    func testResolveWithoutFirebaseUsesCache() {
        let resolution = RemoteConfigService.resolveWithoutFirebase(cachedRaw: "https://cached.example")
        XCTAssertEqual(resolution.url, "https://cached.example")
        XCTAssertEqual(resolution.source, .cache)
    }

    func testRejectsPlaceholderRevenueCatKey() {
        XCTAssertFalse(RemoteConfigService.isValidRevenueCatKey("REPLACE_WITH_DEV_PUBLIC_SDK_KEY"))
        XCTAssertFalse(RemoteConfigService.isValidRevenueCatKey("$(REVENUECAT_PUBLIC_SDK_KEY)"))
        XCTAssertFalse(RemoteConfigService.isValidRevenueCatKey("example_key"))
        XCTAssertFalse(RemoteConfigService.isValidRevenueCatKey(nil))
    }

    func testAcceptsRealRevenueCatKeyShape() {
        XCTAssertTrue(RemoteConfigService.isValidRevenueCatKey("appl_AbCdEfGhIjKlMnOpQrStUvWxYz"))
    }

    func testFirebasePlistInvalidWhenMissing() {
        XCTAssertFalse(RemoteConfigService.isFirebasePlistValid(at: nil))
        XCTAssertFalse(RemoteConfigService.isFirebasePlistValid(at: URL(fileURLWithPath: "/tmp/missing.plist")))
    }
}
