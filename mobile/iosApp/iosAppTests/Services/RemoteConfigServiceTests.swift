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

    func testParseBooleanRecognizesSupportedValuesAndRejectsMissingOrGarbage() {
        XCTAssertNil(RemoteConfigService.parseBoolean(raw: nil))
        XCTAssertNil(RemoteConfigService.parseBoolean(raw: "garbage"))
        XCTAssertEqual(RemoteConfigService.parseBoolean(raw: "true"), true)
        XCTAssertEqual(RemoteConfigService.parseBoolean(raw: "false"), false)
        XCTAssertEqual(RemoteConfigService.parseBoolean(raw: "1"), true)
        XCTAssertEqual(RemoteConfigService.parseBoolean(raw: "0"), false)
        XCTAssertEqual(RemoteConfigService.parseBoolean(raw: "TrUe"), true)
        XCTAssertEqual(RemoteConfigService.parseBoolean(raw: "FALSE"), false)
        XCTAssertEqual(RemoteConfigService.parseBoolean(raw: "yes"), true)
        XCTAssertEqual(RemoteConfigService.parseBoolean(raw: "no"), false)
    }

    func testResolveAccountEnabledPrefersFetchedThenCacheThenDefaultFalse() {
        XCTAssertTrue(RemoteConfigService.resolveAccountEnabled(cachedRaw: "false", fetchedRaw: "true"))
        XCTAssertFalse(RemoteConfigService.resolveAccountEnabled(cachedRaw: "false", fetchedRaw: nil))
        XCTAssertFalse(RemoteConfigService.resolveAccountEnabled(cachedRaw: "false", fetchedRaw: "unparseable"))
        XCTAssertFalse(RemoteConfigService.resolveAccountEnabled(cachedRaw: nil, fetchedRaw: nil))
        XCTAssertFalse(RemoteConfigService.resolveAccountEnabled(cachedRaw: "unparseable", fetchedRaw: nil))
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
