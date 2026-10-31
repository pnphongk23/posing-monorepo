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
        XCTAssertFalse(payload.isExtractPoseEnabled, "extraction fails closed (D6 = A)")
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
        XCTAssertFalse(payload.isExtractPoseEnabled, "an unparseable switch is not an opt-in")
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
        // Missing in the fetched document (and therefore a cache miss too) is off.
        XCTAssertFalse(AppConfigService.resolvePayload(data: nil).isExtractPoseEnabled)
        XCTAssertFalse(AppConfigService.resolvePayload(data: [:]).isExtractPoseEnabled)

        XCTAssertFalse(AppConfigService.resolvePayload(data: ["extractPoseEnabled": false]).isExtractPoseEnabled)
        XCTAssertFalse(AppConfigService.resolvePayload(data: ["extractPoseEnabled": "false"]).isExtractPoseEnabled)
        XCTAssertFalse(AppConfigService.resolvePayload(data: ["extractPoseEnabled": NSNumber(value: 0)]).isExtractPoseEnabled)
        XCTAssertFalse(AppConfigService.resolvePayload(data: ["extractPoseEnabled": "garbage"]).isExtractPoseEnabled)

        // Only an explicit opt-in turns extraction on.
        XCTAssertTrue(AppConfigService.resolvePayload(data: ["extractPoseEnabled": true]).isExtractPoseEnabled)
        XCTAssertTrue(AppConfigService.resolvePayload(data: ["extractPoseEnabled": "true"]).isExtractPoseEnabled)
    }

    func testSealedFetchStillUpdatesThePaywallSwitch() {
        XCTAssertEqual(
            AppConfigService.applicationDecision(isEndpointWindowSealed: true),
            ConfigApplicationDecision(
                updateEndpoint: false,
                updateAccountEnabled: false,
                updateExtractPoseEnabled: true,
                updatePaywallEnabled: true,
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
                updatePaywallEnabled: true,
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
        XCTAssertFalse(payload.isExtractPoseEnabled)
    }

    func testConfigSourceFetchErrorFallsBackToDefaults() async {
        struct CustomError: Error {}
        let source = StubConfigSource(result: .failure(CustomError()))

        let (payload, outcome) = await AppConfigService.fetchAndResolve(source: source)
        XCTAssertEqual(outcome, .error)
        XCTAssertEqual(payload.endpointUrl, AppConfigService.defaultURL)
        XCTAssertFalse(payload.isAccountEnabled)
        XCTAssertFalse(payload.isExtractPoseEnabled)
    }

    func testConfigSourceTimeoutFallsBackToDefaults() async {
        struct TimeoutError: Error {}
        let source = StubConfigSource(result: .failure(TimeoutError()))

        let (payload, outcome) = await AppConfigService.fetchAndResolve(source: source)
        XCTAssertEqual(outcome, .error)
        XCTAssertEqual(payload.endpointUrl, AppConfigService.defaultURL)
        XCTAssertFalse(payload.isAccountEnabled)
        XCTAssertFalse(payload.isExtractPoseEnabled)
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
            isExtractPoseEnabled: false,
            isPaywallEnabled: true
        )
        AppConfigService.apply(payload)

        XCTAssertEqual(AppConfig.shared.SERVER_BASE_URL, "https://applied.endpoint.org")
        XCTAssertTrue(AppConfig.shared.isAccountFeatureEnabled)
        XCTAssertFalse(AppConfig.shared.isExtractPoseEnabled)
        XCTAssertTrue(AppConfig.shared.isPaywallEnabled)

        // Reset to clean state
        AppConfigService.apply(AppConfigPayload())
        XCTAssertFalse(AppConfig.shared.isPaywallEnabled)
    }

    // MARK: - paywall_enabled (FEAT-011 M1)

    func testPaywallEnabledDefaultsToOffWhenTheKeyIsMissing() {
        XCTAssertFalse(AppConfigService.resolvePayload(data: nil).isPaywallEnabled)
        XCTAssertFalse(AppConfigService.resolvePayload(data: [:]).isPaywallEnabled)
        XCTAssertFalse(AppConfigPayload().isPaywallEnabled, "The build default must never gate capture")
    }

    func testPaywallEnabledReadsBooleansAndRejectsWrongTypes() {
        XCTAssertTrue(AppConfigService.resolvePayload(data: ["paywall_enabled": true]).isPaywallEnabled)
        XCTAssertTrue(AppConfigService.resolvePayload(data: ["paywall_enabled": "true"]).isPaywallEnabled)
        XCTAssertFalse(AppConfigService.resolvePayload(data: ["paywall_enabled": false]).isPaywallEnabled)
        // A number or a nested object is not a switch: fail safe to off.
        XCTAssertFalse(AppConfigService.resolvePayload(data: ["paywall_enabled": 1]).isPaywallEnabled)
        XCTAssertFalse(
            AppConfigService.resolvePayload(data: ["paywall_enabled": ["enabled": true]]).isPaywallEnabled
        )
        XCTAssertFalse(AppConfigService.resolvePayload(data: ["paywall_enabled": "garbage"]).isPaywallEnabled)
    }

    func testPaywallEnabledSurvivesTheCacheAndIsRestoredOffline() {
        let (_, store) = makeStore()
        let fetched = AppConfigPayload(
            endpointUrl: "https://cached.example.com",
            isAccountEnabled: true,
            isExtractPoseEnabled: false,
            isPaywallEnabled: true
        )

        XCTAssertTrue(AppConfigService.persistIfSuccessful(fetched, outcome: .applied, store: store))
        let restored = AppConfigService.resolveInitialPayload(store: store)

        XCTAssertEqual(restored, fetched)
        XCTAssertTrue(restored.isPaywallEnabled)
    }

    /// A cache written before the paywall switch existed keeps its old values and adds the switch
    /// as off, so an upgrade can never turn the paywall on by accident.
    func testLegacyCacheWithoutThePaywallKeyDecodesWithTheSwitchOff() throws {
        let (defaults, _) = makeStore()
        let legacy = #"{"endpointUrl":"https://legacy.example.com","isAccountEnabled":true,"isExtractPoseEnabled":false}"#
        defaults.set(Data(legacy.utf8), forKey: "app_config_payload")
        let store = UserDefaultsConfigPayloadStore(defaults: defaults)

        let payload = AppConfigService.resolveInitialPayload(store: store)

        XCTAssertEqual(payload.endpointUrl, "https://legacy.example.com")
        XCTAssertTrue(payload.isAccountEnabled)
        XCTAssertFalse(payload.isExtractPoseEnabled)
        XCTAssertFalse(payload.isPaywallEnabled)
    }

    func testLateFetchUpdatesThePaywallSwitch() {
        XCTAssertTrue(AppConfigService.applicationDecision(isEndpointWindowSealed: true).updatePaywallEnabled)
        XCTAssertTrue(AppConfigService.applicationDecision(isEndpointWindowSealed: false).updatePaywallEnabled)
    }

    // MARK: - Applying a fetched payload (the real launch path)

    /// The launch path must apply the paywall switch even after the endpoint window is sealed,
    /// otherwise a cached ON keeps the paywall on for the rest of the session.
    func testFetchedPaywallOffTurnsACachedPaywallOffInSession() {
        let config = AppConfig()
        config.applyPaywallEnabled(true)
        let decision = AppConfigService.applicationDecision(isEndpointWindowSealed: true)

        let applied = AppConfigService.applyFetched(
            AppConfigPayload(isPaywallEnabled: false),
            decision: decision,
            to: config
        )

        XCTAssertTrue(applied.paywallChanged)
        XCTAssertFalse(config.isPaywallEnabled, "A cached ON must not outlive a fetched OFF")
    }

    func testFetchedPaywallOnAppliesThroughTheSamePath() {
        let config = AppConfig()
        XCTAssertFalse(config.isPaywallEnabled)

        let applied = AppConfigService.applyFetched(
            AppConfigPayload(isPaywallEnabled: true),
            decision: AppConfigService.applicationDecision(isEndpointWindowSealed: true),
            to: config
        )

        XCTAssertTrue(applied.paywallChanged)
        XCTAssertTrue(config.isPaywallEnabled)
        XCTAssertFalse(applied.rebuildRoot, "A kill switch flip does not need a new root view")
    }

    func testSealedFetchKeepsEndpointAndAppliesKillSwitches() {
        let config = AppConfig()
        config.applyEndpoint("https://kept.example.com")

        let applied = AppConfigService.applyFetched(
            AppConfigPayload(
                endpointUrl: "https://ignored.example.com",
                isAccountEnabled: true,
                isExtractPoseEnabled: false,
                isPaywallEnabled: true
            ),
            decision: AppConfigService.applicationDecision(isEndpointWindowSealed: true),
            to: config
        )

        XCTAssertFalse(applied.endpointChanged)
        XCTAssertFalse(applied.accountChanged)
        XCTAssertEqual(config.SERVER_BASE_URL, "https://kept.example.com")
        XCTAssertTrue(config.isPaywallEnabled)
        XCTAssertFalse(config.isExtractPoseEnabled)
    }

    // MARK: - Numeric values are not switches

    func testNumericNSNumberIsNotASwitch() {
        // A real boolean bridged through Foundation keeps its type.
        XCTAssertTrue(AppConfigService.resolveSwitch(NSNumber(value: true), defaultValue: false))
        XCTAssertFalse(AppConfigService.resolveSwitch(NSNumber(value: false), defaultValue: true))
        // A number that happens to bridge to a truthy value is not an opt-in.
        XCTAssertFalse(AppConfigService.resolveSwitch(NSNumber(value: 1), defaultValue: false))
        XCTAssertTrue(AppConfigService.resolveSwitch(NSNumber(value: 0), defaultValue: true))
    }

    func testBridgedNumericNSNumberCannotTurnThePaywallOn() {
        XCTAssertFalse(
            AppConfigService.resolvePayload(data: ["paywall_enabled": NSNumber(value: 1)]).isPaywallEnabled
        )
        XCTAssertFalse(
            AppConfigService.resolvePayload(data: ["paywall_enabled": NSNumber(value: 0)]).isPaywallEnabled
        )
        XCTAssertTrue(
            AppConfigService.resolvePayload(data: ["paywall_enabled": NSNumber(value: true)]).isPaywallEnabled
        )
    }

    func testEntitlementIDPlaceholdersAreRejectedLikeTheSDKKey() {
        XCTAssertFalse(AppConfigService.isValidIdentifier(nil))
        XCTAssertFalse(AppConfigService.isValidIdentifier(""))
        XCTAssertFalse(AppConfigService.isValidIdentifier("REPLACE_WITH_ENTITLEMENT_ID"))
        XCTAssertFalse(AppConfigService.isValidIdentifier("$(REVENUECAT_ENTITLEMENT_ID)"))
        XCTAssertFalse(AppConfigService.isValidIdentifier("example_entitlement"))
        XCTAssertFalse(AppConfigService.isValidIdentifier("placeholder"))
        XCTAssertTrue(AppConfigService.isValidIdentifier("premium"))
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

    // MARK: - account_enabled: the account switch on the shared config document

    /// The 1.2 build reads `account_enabled` — the row the live document carries — and nothing
    /// else. The switch fails closed: only an explicit boolean (or its accepted string form) says
    /// on, so a missing row, an unparsable value and a fetch error all keep the account surface
    /// hidden rather than half-open.
    func testAccountSwitchIsReadFromTheSharedDocumentKey() {
        XCTAssertTrue(
            AppConfigService.resolvePayload(data: ["account_enabled": true]).isAccountEnabled,
            "the row the production document carries switches accounts on"
        )
        XCTAssertTrue(AppConfigService.resolvePayload(data: ["account_enabled": "true"]).isAccountEnabled)
        XCTAssertFalse(AppConfigService.resolvePayload(data: ["account_enabled": false]).isAccountEnabled)
        XCTAssertFalse(AppConfigService.resolvePayload(data: [:]).isAccountEnabled, "a missing row is off")
        XCTAssertFalse(AppConfigService.resolvePayload(data: ["account_enabled": "garbage"]).isAccountEnabled)
        XCTAssertFalse(
            AppConfigService.resolvePayload(data: ["account_enabled": ["nested": true]]).isAccountEnabled,
            "a non-boolean value is off"
        )
    }

    /// The same switch on every failed launch path: an empty document, a throwing source and a
    /// timeout all resolve accounts off, so a Firestore outage never opens a sign-in surface the
    /// build cannot complete a purchase on.
    func testEveryFailedLaunchPathResolvesAccountsOff() async {
        struct SourceFailure: Error {}
        let empty = await AppConfigService.fetchAndResolve(source: StubConfigSource(result: .success(nil)))
        let failing = await AppConfigService.fetchAndResolve(source: StubConfigSource(result: .failure(SourceFailure())))

        XCTAssertFalse(empty.payload.isAccountEnabled)
        XCTAssertEqual(failing.outcome, .error)
        XCTAssertFalse(failing.payload.isAccountEnabled)
    }

    // MARK: - Extraction fails closed (D6 = A)

    /// Offline, a throwing source, an empty document and a timeout all keep extraction off, and the
    /// Jobs entry stays hidden for every one of them.
    func testEveryFailedLaunchPathResolvesExtractionOff() async {
        struct SourceFailure: Error {}
        let emptyDocument = await AppConfigService.fetchAndResolve(
            source: StubConfigSource(result: .success(nil))
        )
        let throwing = await AppConfigService.fetchAndResolve(
            source: StubConfigSource(result: .failure(SourceFailure()))
        )
        let offline = await AppConfigService.fetchAndResolve(
            source: StubConfigSource(result: .failure(URLError(.notConnectedToInternet)))
        )
        let timedOut = await AppConfigService.fetchAndResolve(
            source: StubConfigSource(result: .failure(URLError(.timedOut)))
        )

        for result in [emptyDocument, throwing, offline, timedOut] {
            XCTAssertFalse(result.payload.isExtractPoseEnabled, "no launch path may resolve extraction to on")
            XCTAssertFalse(JobsEntryPolicy.canOpen(extractPoseEnabled: result.payload.isExtractPoseEnabled))
        }
    }

    /// First paint happens before any fetch. A fresh payload and a fresh `AppConfig` are both off,
    /// which is also what an install without a usable Firebase plist keeps for the whole launch.
    func testFirstPaintStartsWithExtractionOff() {
        XCTAssertFalse(AppConfigPayload().isExtractPoseEnabled)
        XCTAssertFalse(AppConfig().isExtractPoseEnabled)
        XCTAssertFalse(AppConfigService.isFirebasePlistValid(at: nil))

        let (_, emptyStore) = makeStore()
        let firstPaint = AppConfigService.resolveInitialPayload(store: emptyStore)
        XCTAssertFalse(firstPaint.isExtractPoseEnabled)
        XCTAssertFalse(JobsEntryPolicy.canOpen(extractPoseEnabled: firstPaint.isExtractPoseEnabled))
    }

    /// A cache written by an older build stored `true` as its *default*, so it is discarded as an
    /// opt-in while the endpoint and account values it also holds are kept.
    func testV1CacheDoesNotCarryItsDefaultExtractionOnIntoThisBuild() {
        let (defaults, _) = makeStore()
        let legacy = #"{"endpointUrl":"https://legacy.example.com","isAccountEnabled":true,"isExtractPoseEnabled":true,"isPaywallEnabled":false}"#
        defaults.set(Data(legacy.utf8), forKey: "app_config_payload")
        let store = UserDefaultsConfigPayloadStore(defaults: defaults)

        let payload = AppConfigService.resolveInitialPayload(store: store)

        XCTAssertFalse(payload.isExtractPoseEnabled, "a v1 `true` was the old default, not an operator's opt-in")
        XCTAssertEqual(payload.endpointUrl, "https://legacy.example.com")
        XCTAssertTrue(payload.isAccountEnabled)
        XCTAssertFalse(JobsEntryPolicy.canOpen(extractPoseEnabled: payload.isExtractPoseEnabled))
    }

    /// This build's own cache keeps an explicit ON across a relaunch, which is what makes an
    /// offline launch after a successful fetch behave like the fetched payload.
    func testV2CacheKeepsAnExplicitExtractionOn() {
        let (_, store) = makeStore()
        let fetched = AppConfigPayload(endpointUrl: "https://cached.example.com", isExtractPoseEnabled: true)
        XCTAssertEqual(fetched.schemaVersion, AppConfigPayload.currentSchemaVersion)
        XCTAssertTrue(AppConfigService.persistIfSuccessful(fetched, outcome: .applied, store: store))

        let restored = AppConfigService.resolveInitialPayload(store: store)
        XCTAssertTrue(restored.isExtractPoseEnabled)
        XCTAssertEqual(restored.endpointUrl, "https://cached.example.com")
    }

    /// A cached ON must not outlive a fetched OFF in the same launch.
    func testCachedExtractionOnIsTurnedOffByALateFetch() {
        let config = AppConfig()
        config.applyExtractPoseEnabled(true)
        let decision = AppConfigService.applicationDecision(isEndpointWindowSealed: true)

        let applied = AppConfigService.applyFetched(
            AppConfigPayload(endpointUrl: AppConfigService.defaultURL, isExtractPoseEnabled: false),
            decision: decision,
            to: config
        )

        XCTAssertTrue(applied.extractPoseChanged)
        XCTAssertFalse(config.isExtractPoseEnabled)
        XCTAssertFalse(JobsEntryPolicy.canOpen(extractPoseEnabled: config.isExtractPoseEnabled))
    }
}
