import Foundation

/// DEC-006 validation for Remote Config `api_baseurl`.
enum EndpointPolicy {
    static let remoteConfigKey = "api_baseurl"

    static func validate(raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return nil
        }
        if value.contains(" ") || value.count > 2048 { return nil }
        return value
    }

    static func resolve(defaultUrl: String, cachedRaw: String?, fetchedRaw: String?) -> String {
        if let fetched = validate(raw: fetchedRaw) { return fetched }
        if let cached = validate(raw: cachedRaw) { return cached }
        return defaultUrl
    }
}
