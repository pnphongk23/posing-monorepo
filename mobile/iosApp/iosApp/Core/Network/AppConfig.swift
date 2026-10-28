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

    /// Debug-only switch for Simulator QA runs: `-AIPoseAccountsEnabled YES|NO` exposes the Saved
    /// and Account surfaces without editing the Firestore `accounts_enabled_v2` document. Compiled
    /// out of Release for the same reason as the paywall override above.
    static let debugAccountsEnabledOverride: Bool? =
        DebugLaunchArgumentOverride.booleanValue(
            for: DebugLaunchArgumentOverride.accountsEnabledFlag,
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
        // names the FieldPath it overrides (`accounts_enabled_v2`) and is the fallback. Both sit on
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

/// QA-only launch-argument overrides for the two Firestore switches (`paywall_enabled`,
/// `accounts_enabled_v2`), so a Simulator run can exercise both surfaces without editing the
/// production documents.
///
/// The reader is a pure function with `isDebugBuild` as an **input**, not as a compile-time fact: a
/// unit test can then assert the Release answer (`nil`) without a Release build, and the only
/// production wiring — the `ProcessInfo` lookup — is compiled under `#if DEBUG` (see `AppConfig`).
enum DebugLaunchArgumentOverride {
    #if DEBUG
    /// Argument names. Kept inside `#if DEBUG` so a Release binary carries neither the names nor the
    /// wiring that reads them.
    static let paywallEnabledFlag = "-AIPosePaywallEnabled"
    static let accountsEnabledFlag = "-AIPoseAccountsEnabled"
    #endif

    /// `nil` means "no override": a Release build, a missing flag, a flag without a value and an
    /// unparsable value all keep the resolved payload in charge. Values go through the same boolean
    /// parser the Firestore payload uses, so `YES`/`NO`/`true`/`false` (any case) are accepted.
    static func booleanValue(
        for flag: String,
        in arguments: [String],
        isDebugBuild: Bool
    ) -> Bool? {
        // Release builds never look at argv — by construction, and this guard is what a test pins.
        guard isDebugBuild else { return nil }
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else { return nil }
        return AppConfigService.parseBoolean(raw: arguments[index + 1])
    }
}
