import Foundation
import FirebaseFirestore

struct AppConfigPayload: Codable, Equatable, Sendable {
    let endpointUrl: String
    let isAccountEnabled: Bool
    let isExtractPoseEnabled: Bool
    let isPaywallEnabled: Bool

    private enum CodingKeys: String, CodingKey {
        case endpointUrl
        case isAccountEnabled
        case isExtractPoseEnabled
        case isPaywallEnabled
    }

    init(
        endpointUrl: String = AppConfigService.defaultURL,
        isAccountEnabled: Bool = false,
        isExtractPoseEnabled: Bool = true,
        isPaywallEnabled: Bool = false
    ) {
        self.endpointUrl = endpointUrl
        self.isAccountEnabled = isAccountEnabled
        self.isExtractPoseEnabled = isExtractPoseEnabled
        self.isPaywallEnabled = isPaywallEnabled
    }

    /// A cache written before the paywall switch existed must keep its other values instead of
    /// being discarded. The missing switch always resolves to its fail-safe default: off.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        endpointUrl = try container.decode(String.self, forKey: .endpointUrl)
        isAccountEnabled = try container.decode(Bool.self, forKey: .isAccountEnabled)
        isExtractPoseEnabled = try container.decode(Bool.self, forKey: .isExtractPoseEnabled)
        isPaywallEnabled = try container.decodeIfPresent(Bool.self, forKey: .isPaywallEnabled) ?? false
    }
}

struct ConfigApplicationDecision: Equatable {
    let updateEndpoint: Bool
    let updateAccountEnabled: Bool
    let updateExtractPoseEnabled: Bool
    let updatePaywallEnabled: Bool
    let rebuildRootForChanges: Bool
}

enum FetchOutcome: String, Sendable {
    case applied, unavailable, timeout, error, emptyOrInvalid
}

protocol ConfigPayloadStore: Sendable {
    func load() -> AppConfigPayload?
    func save(_ payload: AppConfigPayload)
}

final class UserDefaultsConfigPayloadStore: ConfigPayloadStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "app_config_payload") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> AppConfigPayload? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(AppConfigPayload.self, from: data)
    }

    func save(_ payload: AppConfigPayload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: key)
    }
}

protocol ConfigSource: Sendable {
    func fetchConfig() async throws -> [String: Any]?
}

struct FirestoreConfigSource: ConfigSource {
    init() {}

    func fetchConfig() async throws -> [String: Any]? {
        let db = Firestore.firestore()
        // Offline/server failures must resolve to compile-time defaults. The app's first paint
        // already happened before this server-only request starts.
        let snapshot = try await db.collection("config").document("app").getDocument(source: .server)
        return snapshot.data()
    }
}

/// Firestore configuration resolution with compile-time defaults and fallback policies.
enum AppConfigService {
    static let defaultURL = "https://pose-extract-server-production.up.railway.app"
    static let endpointKey = "api_baseurl"
    static let accountEnabledKey = "account_enabled"
    static let extractPoseEnabledKey = "extractPoseEnabled"
    static let paywallEnabledKey = "paywall_enabled"

    static func resolveInitialPayload(store: ConfigPayloadStore) -> AppConfigPayload {
        guard let cached = store.load() else { return AppConfigPayload() }
        return AppConfigPayload(
            endpointUrl: EndpointPolicy.validate(raw: cached.endpointUrl) ?? defaultURL,
            isAccountEnabled: cached.isAccountEnabled,
            isExtractPoseEnabled: cached.isExtractPoseEnabled,
            isPaywallEnabled: cached.isPaywallEnabled
        )
    }

    @discardableResult
    static func persistIfSuccessful(
        _ payload: AppConfigPayload,
        outcome: FetchOutcome,
        store: ConfigPayloadStore
    ) -> Bool {
        guard outcome == .applied else { return false }
        store.save(payload)
        return true
    }

    static func parseBoolean(raw: Any?) -> Bool? {
        if let bool = raw as? Bool {
            return bool
        }
        if let number = raw as? NSNumber {
            return number.boolValue
        }
        guard let string = raw as? String else {
            return nil
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch trimmed {
        case "true", "1", "yes": return true
        case "false", "0", "no": return false
        default: return nil
        }
    }

    /// Fail-safe switch resolution: a boolean, or a string `parseBoolean` understands. Any other
    /// type (a number, an object, an array) is not a switch and resolves to `defaultValue`.
    static func resolveSwitch(_ raw: Any?, defaultValue: Bool) -> Bool {
        if let bool = raw as? Bool { return bool }
        if let string = raw as? String { return parseBoolean(raw: string) ?? defaultValue }
        return defaultValue
    }

    /// Pure resolution logic for endpoint, accountEnabled, extractPoseEnabled and paywallEnabled.
    static func resolvePayload(
        data: [String: Any]?,
        defaultUrl: String = defaultURL
    ) -> AppConfigPayload {
        // 1. Endpoint
        let fetchedEndpointRaw = data?[endpointKey] as? String
        let endpoint = EndpointPolicy.resolve(
            defaultUrl: defaultUrl,
            cachedRaw: nil,
            fetchedRaw: fetchedEndpointRaw
        )

        // 2. Account Enabled: defaults to false when unavailable (preserves existing behavior)
        let fetchedAccountRaw = data?[accountEnabledKey]
        let accountEnabled = parseBoolean(raw: fetchedAccountRaw)
            ?? false

        // 3. Extract Pose Enabled: defaults to true when missing/error/offline
        let fetchedExtractRaw = data?[extractPoseEnabledKey]
        let extractPoseEnabled = parseBoolean(raw: fetchedExtractRaw) ?? true

        // 4. Paywall Enabled: defaults to false when missing/error/offline, so a Firestore outage
        // can never lock capture behind a paywall. Only an explicit boolean (or its string form)
        // counts as a switch; a number or an object is not an opt-in.
        let paywallEnabled = resolveSwitch(data?[paywallEnabledKey], defaultValue: false)

        return AppConfigPayload(
            endpointUrl: endpoint,
            isAccountEnabled: accountEnabled,
            isExtractPoseEnabled: extractPoseEnabled,
            isPaywallEnabled: paywallEnabled
        )
    }

    /// Orchestrated fetch & resolve using an injected ConfigSource (real Firestore or test double).
    static func fetchAndResolve(
        source: ConfigSource,
        defaultUrl: String = defaultURL
    ) async -> (payload: AppConfigPayload, outcome: FetchOutcome) {
        do {
            guard let data = try await source.fetchConfig() else {
                let payload = resolvePayload(data: nil, defaultUrl: defaultUrl)
                return (payload, .emptyOrInvalid)
            }
            let payload = resolvePayload(data: data, defaultUrl: defaultUrl)
            return (payload, .applied)
        } catch {
            let payload = resolvePayload(data: nil, defaultUrl: defaultUrl)
            return (payload, .error)
        }
    }

    /// Applies resolved values to [AppConfig].
    static func apply(_ payload: AppConfigPayload) {
        AppConfig.shared.applyEndpoint(payload.endpointUrl)
        AppConfig.shared.applyAccountFeatureEnabled(payload.isAccountEnabled)
        AppConfig.shared.applyExtractPoseEnabled(payload.isExtractPoseEnabled)
        AppConfig.shared.applyPaywallEnabled(payload.isPaywallEnabled)
    }

    /// A late fetch may still change the extraction and paywall kill switches, while endpoint and
    /// account updates retain the historical five-second launch budget.
    static func applicationDecision(isEndpointWindowSealed: Bool) -> ConfigApplicationDecision {
        ConfigApplicationDecision(
            updateEndpoint: !isEndpointWindowSealed,
            updateAccountEnabled: !isEndpointWindowSealed,
            updateExtractPoseEnabled: true,
            updatePaywallEnabled: true,
            rebuildRootForChanges: !isEndpointWindowSealed
        )
    }

    /// Validates a non-secret identifier read from build configuration: an empty value, an
    /// unresolved `$(SETTING)` reference, or a committed placeholder is not a usable value.
    static func isValidIdentifier(_ value: String?) -> Bool {
        guard let value, !value.isEmpty else { return false }
        if value.contains("$(") { return false }
        let lower = value.lowercased()
        if lower.contains("placeholder") || lower.contains("example") { return false }
        if lower.hasPrefix("replace_with") { return false }
        return true
    }

    /// Validates RevenueCat public SDK key from Info.plist; rejects placeholders.
    static func isValidRevenueCatKey(_ key: String?) -> Bool {
        isValidIdentifier(key)
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
