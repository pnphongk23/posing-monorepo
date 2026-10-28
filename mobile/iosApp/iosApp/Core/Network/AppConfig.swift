import Foundation

/// Runtime API base URL and feature configuration holder. Startup resolution writes here before any API call.
final class AppConfig: @unchecked Sendable {
    static let shared = AppConfig()

    private let lock = NSLock()
    private var _serverBaseURL = "https://pose-extract-server-production.up.railway.app"
    private var _isAccountFeatureEnabled = false
    private var _isExtractPoseEnabled = true
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
        if let override = Self.debugAccountFeatureEnabledOverride { return override }
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
