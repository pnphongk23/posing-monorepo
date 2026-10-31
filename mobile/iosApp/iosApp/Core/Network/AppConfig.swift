import Foundation

/// Runtime API base URL and feature configuration holder. Startup resolution writes here before any API call.
final class AppConfig: @unchecked Sendable {
    static let shared = AppConfig()

    private let lock = NSLock()
    private var _serverBaseURL = "https://pose-extract-server-production.up.railway.app"
    private var _isAccountFeatureEnabled = false
    /// D6 = A: extraction fails closed. First paint, a Firestore outage and a fresh install all
    /// read `false`; only a fetched explicit `true` turns it on.
    private var _isExtractPoseEnabled = false
    /// FEAT-011 kill switch. Off by default: the paywall never gates on a build that has not been
    /// told to, and a Firestore outage leaves capture free.
    private var _isPaywallEnabled = false

    #if DEBUG
    /// Debug-only endpoint override for instrumented Simulator runs: `-AIPoseAPIBaseURL <url>` on
    /// the launch arguments points the app at a local stub so the whole sign-in flow can be
    /// observed and re-run without touching the production deployment or a real account.
    /// Compiled out of Release.
    static let debugBaseURLOverride: String? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-AIPoseAPIBaseURL"),
              arguments.indices.contains(flag + 1) else { return nil }
        return EndpointPolicy.validate(raw: arguments[flag + 1])
    }()

    /// Debug-only switch for Simulator evidence runs: `-AIPoseAccountEnabled false`.
    /// Compiled out of Release.
    private static let debugAccountFeatureEnabledOverride: Bool? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-AIPoseAccountEnabled"),
              arguments.indices.contains(flag + 1) else { return nil }
        switch arguments[flag + 1].lowercased() {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }()

    /// Debug-only switch for Simulator evidence runs: `-AIPoseExtractPoseEnabled false`.
    /// Compiled out of Release.
    private static let debugExtractPoseEnabledOverride: Bool? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-AIPoseExtractPoseEnabled"),
              arguments.indices.contains(flag + 1) else { return nil }
        switch arguments[flag + 1].lowercased() {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }()

    /// Debug-only switch for Simulator QA runs: `-AIPosePaywallEnabled YES|NO` gates capture on the
    /// paywall without editing the Firestore `paywall_enabled` document. Compiled out of Release:
    /// a shipping build contains neither the argument name nor this lookup.
    static let debugPaywallEnabledOverride: Bool? =
        DebugLaunchArgumentOverride.booleanValue(
            for: DebugLaunchArgumentOverride.paywallEnabledFlag,
            in: ProcessInfo.processInfo.arguments,
            isDebugBuild: true
        )

    /// Evidence-run only: forces one catalogue footer state (`-AIPosePagingFixture loading|failed|end`)
    /// so the spinner, the retry row and the end line can be captured. Compiled out of Release with
    /// the other evidence switches.
    static let debugPagingFixtureOverride: String? =
        DebugLaunchArgumentOverride.stringValue(
            for: DebugLaunchArgumentOverride.pagingFixtureFlag,
            in: ProcessInfo.processInfo.arguments,
            isDebugBuild: true
        )

    /// Debug-only switch for Simulator QA runs: `-AIPoseAccountsEnabled YES|NO` exposes the Saved
    /// and Account surfaces without editing the Firestore `account_enabled` document. Compiled
    /// out of Release for the same reason as the paywall override above.
    static let debugAccountsEnabledOverride: Bool? =
        DebugLaunchArgumentOverride.booleanValue(
            for: DebugLaunchArgumentOverride.accountsEnabledFlag,
            in: ProcessInfo.processInfo.arguments,
            isDebugBuild: true
        )

    /// Debug-only switch for Simulator QA runs: `-AIPosePurchasesConfigured YES|NO` makes the capture
    /// gate treat the purchase context as configured, so the paywall is reachable on a build whose
    /// RevenueCat key or `REVENUECAT_ENTITLEMENT_ID` setting is still a placeholder (G3 would otherwise
    /// fail open).
    ///
    /// It is a *precondition* override, never a result: no access, offering or purchase is fabricated,
    /// so on such a build the paywall honestly reports itself unavailable and a purchase cannot
    /// complete. Compiled out of Release like the switches above.
    static let debugPurchasesConfiguredOverride: Bool? =
        DebugLaunchArgumentOverride.booleanValue(
            for: DebugLaunchArgumentOverride.purchasesConfiguredFlag,
            in: ProcessInfo.processInfo.arguments,
            isDebugBuild: true
        )
    #endif

    var SERVER_BASE_URL: String {
        #if DEBUG
        if let override = Self.debugBaseURLOverride { return override }
        #endif
        lock.lock()
        defer { lock.unlock() }
        return _serverBaseURL
    }

    func applyEndpoint(_ url: String) {
        lock.lock()
        _serverBaseURL = url
        lock.unlock()
    }

    var isAccountFeatureEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        #if DEBUG
        // The historical `-AIPoseAccountEnabled` keeps its precedence; `-AIPoseAccountsEnabled`
        // names the FieldPath it overrides (`account_enabled`) and is the fallback. Both sit on
        // top of the resolved payload, so the kill switch itself is untouched.
        if let override = Self.debugAccountFeatureEnabledOverride { return override }
        if let override = Self.debugAccountsEnabledOverride { return override }
        #endif
        return _isAccountFeatureEnabled
    }

    func applyAccountFeatureEnabled(_ enabled: Bool) {
        lock.lock()
        _isAccountFeatureEnabled = enabled
        lock.unlock()
    }

    var isExtractPoseEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        #if DEBUG
        if let override = Self.debugExtractPoseEnabledOverride { return override }
        #endif
        return _isExtractPoseEnabled
    }

    func applyExtractPoseEnabled(_ enabled: Bool) {
        lock.lock()
        _isExtractPoseEnabled = enabled
        lock.unlock()
    }

    var isPaywallEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        #if DEBUG
        // Only a Debug build can answer with the launch-argument override; every other build falls
        // straight through to the resolved payload, which fails closed to `false`.
        if let override = Self.debugPaywallEnabledOverride { return override }
        #endif
        return _isPaywallEnabled
    }

    func applyPaywallEnabled(_ enabled: Bool) {
        lock.lock()
        _isPaywallEnabled = enabled
        lock.unlock()
    }

    /// Pure gating decision for pose extraction feature.
    static func canExtractPose(isEnabled: Bool) -> Bool {
        isEnabled
    }
}

#if DEBUG
/// QA-only launch-argument overrides for the Firestore switches (`paywall_enabled`,
/// `account_enabled`) plus the purchase-context precondition (`-AIPosePurchasesConfigured`), so a
/// Simulator run can exercise every surface without editing the production documents.
///
/// The whole reader is compiled **only** into a Debug build: Release carries neither the argument
/// names nor the argv lookup, so there is no Release code path to disable. `booleanValue` still
/// takes `isDebugBuild` as an **input** so a test can pin the `nil` answer it would give, and the
/// Release guarantee itself is proven by the source scan in `AppConfigTests`.
///
/// `nil` means "no override": a missing flag, a flag without a value and an unparsable value all
/// keep the resolved payload in charge. Values go through the same boolean parser the Firestore
/// payload uses, so `YES`/`NO`/`true`/`false` (any case) are accepted.
enum DebugLaunchArgumentOverride {
    static let paywallEnabledFlag = "-AIPosePaywallEnabled"
    /// Evidence runs only: forces the catalogue's paging into one footer state
    /// (`-AIPosePagingFixture loading|failed|end`). Compiled out of Release with the rest.
    static let pagingFixtureFlag = "-AIPosePagingFixture"
    static let accountsEnabledFlag = "-AIPoseAccountsEnabled"
    static let purchasesConfiguredFlag = "-AIPosePurchasesConfigured"

    static func stringValue(
        for flag: String,
        in arguments: [String],
        isDebugBuild: Bool
    ) -> String? {
        guard isDebugBuild else { return nil }
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    static func booleanValue(
        for flag: String,
        in arguments: [String],
        isDebugBuild: Bool
    ) -> Bool? {
        // A Release build never looks at argv; this guard is the runtime half of that promise and
        // `#if DEBUG` above is the compile-time half.
        guard isDebugBuild else { return nil }
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else { return nil }
        return AppConfigService.parseBoolean(raw: arguments[index + 1])
    }
}
#endif
