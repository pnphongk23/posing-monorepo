import Foundation

/// Runtime API base URL holder. Startup resolution writes here before any API call.
final class AppConfig: @unchecked Sendable {
    static let shared = AppConfig()

    private let lock = NSLock()
    private var _serverBaseURL = "https://pose-extract-server-production.up.railway.app"
    private var _isAccountFeatureEnabled = true

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
}
