import Foundation

/// Firebase Remote Config resolution with bounded timeout and config fallback.
enum RemoteConfigService {
    static let defaultURL = "https://pose-extract-server-production.up.railway.app"
    static let accountEnabledKey = "account_enabled"

    enum ResolutionSource: String, Sendable {
        case `default`, cache, fetch
    }

    struct Resolution: Sendable {
        let url: String
        let source: ResolutionSource
    }

    /// Pure decision used when Firebase is unavailable (no I/O).
    static func resolveWithoutFirebase(cachedRaw: String? = nil) -> Resolution {
        let url = EndpointPolicy.resolve(defaultUrl: defaultURL, cachedRaw: cachedRaw, fetchedRaw: nil)
        let source: ResolutionSource = EndpointPolicy.validate(raw: cachedRaw) != nil ? .cache : .default
        return Resolution(url: url, source: source)
    }

    /// Applies resolved endpoint to [AppConfig] — call after startup gate completes.
    static func apply(_ resolution: Resolution) {
        AppConfig.shared.applyEndpoint(resolution.url)
    }

    static func parseBoolean(raw: String?) -> Bool? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return nil
        }
        switch value {
        case "true", "1", "yes": return true
        case "false", "0", "no": return false
        default: return nil
        }
    }

    static func resolveAccountEnabled(cachedRaw: String?, fetchedRaw: String?) -> Bool {
        parseBoolean(raw: fetchedRaw) ?? parseBoolean(raw: cachedRaw) ?? true
    }

    static func applyAccountEnabled(_ enabled: Bool) {
        AppConfig.shared.applyAccountFeatureEnabled(enabled)
    }

    /// Validates RevenueCat public SDK key from Info.plist; rejects placeholders.
    static func isValidRevenueCatKey(_ key: String?) -> Bool {
        guard let key, !key.isEmpty else { return false }
        if key.contains("$(") { return false }
        let lower = key.lowercased()
        if lower.contains("placeholder") || lower.contains("example") { return false }
        if lower.hasPrefix("replace_with") { return false }
        return true
    }

    /// Validates Firebase plist presence without configuring Firebase.
    static func isFirebasePlistValid(at url: URL?) -> Bool {
        guard let url, let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return false
        }
        guard let apiKey = plist["API_KEY"] as? String, !apiKey.isEmpty, apiKey.hasPrefix("AIza") else {
            return false
        }
        guard let appId = plist["GOOGLE_APP_ID"] as? String,
              appId.range(of: #"^1:\d{6,}:ios:[0-9a-f]+$"#, options: .regularExpression) != nil else {
            return false
        }
        let joined = plist.values.compactMap { "\($0)" }.joined(separator: " ").lowercased()
        return !joined.contains("placeholder") && !joined.contains("example")
    }
}
