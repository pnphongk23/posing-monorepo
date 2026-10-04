import XCTest
@testable import iosApp

final class StubConfigSource: @unchecked Sendable, ConfigSource {
    var result: Result<[String: Any]?, Error>

    init(result: Result<[String: Any]?, Error>) {
        self.result = result
    }

    func fetchConfig() async throws -> [String: Any]? {
        try result.get()
    }
}

final class AppConfigServiceTests: XCTestCase {
    private func makeStore() -> (UserDefaults, UserDefaultsConfigPayloadStore) {
        let suite = "AppConfigServiceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, UserDefaultsConfigPayloadStore(defaults: defaults))
    }

    func testConfigCacheRoundTripAndFirstPaintUsesCachedFalse() {
        let (_, store) = makeStore()
        let fetched = AppConfigPayload(
            endpointUrl: "https://cached.example.com",
            isAccountEnabled: true,
            isExtractPoseEnabled: false
        )

        XCTAssertTrue(AppConfigService.persistIfSuccessful(fetched, outcome: .applied, store: store))
        XCTAssertEqual(store.load(), fetched)
        XCTAssertEqual(AppConfigService.resolveInitialPayload(store: store), fetched)
    }

    func testConfigCacheWithoutSuccessfulFetchUsesCompileTimeDefaults() {
        let (_, store) = makeStore()
        XCTAssertEqual(AppConfigService.resolveInitialPayload(store: store), AppConfigPayload())
    }

    func testFailedFetchDoesNotOverwriteLastSuccessfulConfig() {
        let (_, store) = makeStore()
        let cached = AppConfigPayload(
            endpointUrl: "https://cached.example.com",
            isAccountEnabled: true,
            isExtractPoseEnabled: false
        )
        store.save(cached)

        XCTAssertFalse(AppConfigService.persistIfSuccessful(AppConfigPayload(), outcome: .error, store: store))
        XCTAssertEqual(store.load(), cached)
        XCTAssertEqual(AppConfigService.resolveInitialPayload(store: store).isExtractPoseEnabled, false)
    }

    func testResolveWithNilDataUsesDefaults() {
        let payload = AppConfigService.resolvePayload(data: nil)
        XCTAssertEqual(payload.endpointUrl, AppConfigService.defaultURL)
        XCTAssertFalse(payload.isAccountEnabled)
        XCTAssertTrue(payload.isExtractPoseEnabled)
    }

    func testResolveWithValidFirestoreData() {
        let data: [String: Any] = [
            "api_baseurl": "https://custom.api.endpoint",
            "account_enabled": true,
            "extractPoseEnabled": false
        ]
        let payload = AppConfigService.resolvePayload(data: data)
        XCTAssertEqual(payload.endpointUrl, "https://custom.api.endpoint")
        XCTAssertTrue(payload.isAccountEnabled)
        XCTAssertFalse(payload.isExtractPoseEnabled)
    }

    func testResolveWithInvalidEndpointFallsBackToDefault() {
        let invalidData: [String: Any] = [
          "api_baseurl": "not-a-valid-url",
          "account_enabled": "true",
          "extractPoseEnabled": "garbage"
        ]
        let payload = AppConfigService.resolvePayload(data: invalidData)
        XCTAssertEqual(payload.endpointUrl, AppConfigService.defaultURL)
        XCTAssertTrue(payload.isAccountEnabled)
        XCTAssertTrue(payload.isExtractPoseEnabled)
    }

    func testParseBooleanRecognizesVariousTypesAndValues() {
        XCTAssertNil(AppConfigService.parseBoolean(raw: nil))
        XCTAssertNil(AppConfigService.parseBoolean(raw: "garbage"))
        XCTAssertEqual(AppConfigService.parseBoolean(raw: true), true)
        XCTAssertEqual(AppConfigService.parseBoolean(raw: false), false)
        XCTAssertEqual(AppConfigService.parseBoolean(raw: NSNumber(value: 1)), true)
        XCTAssertEqual(AppConfigService.parseBoolean(raw: NSNumber(value: 0)), false)
        XCTAssertEqual(AppConfigService.parseBoolean(raw: "true"), true)
        XCTAssertEqual(AppConfigService.parseBoolean(raw: "false"), false)
        XCTAssertEqual(AppConfigService.parseBoolean(raw: "1"), true)
        XCTAssertEqual(AppConfigService.parseBoolean(raw: "0"), false)
        XCTAssertEqual(AppConfigService.parseBoolean(raw: "TrUe"), true)
        XCTAssertEqual(AppConfigService.parseBoolean(raw: "FALSE"), false)
        XCTAssertEqual(AppConfigService.parseBoolean(raw: "yes"), true)
        XCTAssertEqual(AppConfigService.parseBoolean(raw: "no"), false)
    }

    func testAccountEnabledResolutionOrder() {
        // A fetched true value is enabled.
        let p1 = AppConfigService.resolvePayload(
            data: ["account_enabled": "true"]
        )
        XCTAssertTrue(p1.isAccountEnabled)

        // Missing defaults to disabled.
        let p2 = AppConfigService.resolvePayload(
            data: [:]
        )
        XCTAssertFalse(p2.isAccountEnabled)

        // Missing / unparseable in both defaults to false
        let p3 = AppConfigService.resolvePayload(
            data: ["account_enabled": "unparseable"]
        )
        XCTAssertFalse(p3.isAccountEnabled)
    }

    func testExtractPoseEnabledResolutionOrder() {
        // Missing in fetched and cached defaults to true
        let p1 = AppConfigService.resolvePayload(data: nil)
        XCTAssertTrue(p1.isExtractPoseEnabled)

        // Explicit false in fetched overrides cached true
        let p2 = AppConfigService.resolvePayload(
            data: ["extractPoseEnabled": false]
        )
        XCTAssertFalse(p2.isExtractPoseEnabled)

        XCTAssertFalse(AppConfigService.resolvePayload(data: ["extractPoseEnabled": "false"]).isExtractPoseEnabled)
        XCTAssertFalse(AppConfigService.resolvePayload(data: ["extractPoseEnabled": NSNumber(value: 0)]).isExtractPoseEnabled)
        XCTAssertTrue(AppConfigService.resolvePayload(data: ["extractPoseEnabled": "garbage"]).isExtractPoseEnabled)
    }

    func testSealedFetchOnlyUpdatesExtractPoseFlag() {
        XCTAssertEqual(
            AppConfigService.applicationDecision(isEndpointWindowSealed: true),
            ConfigApplicationDecision(
                updateEndpoint: false,
                updateAccountEnabled: false,
                updateExtractPoseEnabled: true,
                rebuildRootForChanges: false
            )
        )
    }

    func testUnsealedFetchUpdatesAllConfigAndMayRebuildRoot() {
        XCTAssertEqual(
            AppConfigService.applicationDecision(isEndpointWindowSealed: false),
            ConfigApplicationDecision(
                updateEndpoint: true,
                updateAccountEnabled: true,
                updateExtractPoseEnabled: true,
                rebuildRootForChanges: true
            )
        )
    }

    func testConfigSourceFetchSuccessApplied() async {
        let source = StubConfigSource(result: .success([
            "api_baseurl": "https://fetched.source.io",
            "account_enabled": true,
            "extractPoseEnabled": false
        ]))

        let (payload, outcome) = await AppConfigService.fetchAndResolve(source: source)
        XCTAssertEqual(outcome, .applied)
        XCTAssertEqual(payload.endpointUrl, "https://fetched.source.io")
        XCTAssertTrue(payload.isAccountEnabled)
        XCTAssertFalse(payload.isExtractPoseEnabled)
    }

    func testConfigSourceFetchNilDataEmptyOrInvalid() async {
        let source = StubConfigSource(result: .success(nil))

        let (payload, outcome) = await AppConfigService.fetchAndResolve(source: source)
        XCTAssertEqual(outcome, .emptyOrInvalid)
        XCTAssertEqual(payload.endpointUrl, AppConfigService.defaultURL)
        XCTAssertFalse(payload.isAccountEnabled)
        XCTAssertTrue(payload.isExtractPoseEnabled)
    }

    func testConfigSourceFetchErrorFallsBackToDefaults() async {
        struct CustomError: Error {}
        let source = StubConfigSource(result: .failure(CustomError()))

        let (payload, outcome) = await AppConfigService.fetchAndResolve(source: source)
        XCTAssertEqual(outcome, .error)
        XCTAssertEqual(payload.endpointUrl, AppConfigService.defaultURL)
        XCTAssertFalse(payload.isAccountEnabled)
        XCTAssertTrue(payload.isExtractPoseEnabled)
    }

    func testConfigSourceTimeoutFallsBackToDefaults() async {
        struct TimeoutError: Error {}
        let source = StubConfigSource(result: .failure(TimeoutError()))

        let (payload, outcome) = await AppConfigService.fetchAndResolve(source: source)
        XCTAssertEqual(outcome, .error)
        XCTAssertEqual(payload.endpointUrl, AppConfigService.defaultURL)
        XCTAssertFalse(payload.isAccountEnabled)
        XCTAssertTrue(payload.isExtractPoseEnabled)
    }

    func testMissingEndpointUsesDefaultWhileOtherFieldsResolve() {
        let payload = AppConfigService.resolvePayload(data: [
            "account_enabled": false,
            "extractPoseEnabled": true
        ])

        XCTAssertEqual(payload.endpointUrl, AppConfigService.defaultURL)
        XCTAssertFalse(payload.isAccountEnabled)
        XCTAssertTrue(payload.isExtractPoseEnabled)
    }

    func testApplyUpdatesSharedAppConfig() {
        let payload = AppConfigPayload(
            endpointUrl: "https://applied.endpoint.org",
            isAccountEnabled: true,
            isExtractPoseEnabled: false
        )
        AppConfigService.apply(payload)

        XCTAssertEqual(AppConfig.shared.SERVER_BASE_URL, "https://applied.endpoint.org")
        XCTAssertTrue(AppConfig.shared.isAccountFeatureEnabled)
        XCTAssertFalse(AppConfig.shared.isExtractPoseEnabled)

        // Reset to clean state
        AppConfigService.apply(AppConfigPayload())
    }

    func testRejectsPlaceholderRevenueCatKey() {
        XCTAssertFalse(AppConfigService.isValidRevenueCatKey("REPLACE_WITH_DEV_PUBLIC_SDK_KEY"))
        XCTAssertFalse(AppConfigService.isValidRevenueCatKey("$(REVENUECAT_PUBLIC_SDK_KEY)"))
        XCTAssertFalse(AppConfigService.isValidRevenueCatKey("example_key"))
        XCTAssertFalse(AppConfigService.isValidRevenueCatKey(nil))
    }

    func testAcceptsRealRevenueCatKeyShape() {
        XCTAssertTrue(AppConfigService.isValidRevenueCatKey("appl_AbCdEfGhIjKlMnOpQrStUvWxYz"))
    }

    func testFirebasePlistInvalidWhenMissing() {
        XCTAssertFalse(AppConfigService.isFirebasePlistValid(at: nil))
        XCTAssertFalse(AppConfigService.isFirebasePlistValid(at: URL(fileURLWithPath: "/tmp/missing.plist")))
    }
}
