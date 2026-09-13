import Foundation

enum EndpointSource: String, Sendable { case `default`, cache, fetch }

enum FetchOutcome: String, Sendable {
    case applied, unavailable, timeout, error, emptyOrInvalid
}

enum FetchResult: Sendable {
    case success(String)
    case unavailable
    case timeout
    case error
}

struct EndpointResolution: Sendable {
    let url: String
    let source: EndpointSource
    let outcome: FetchOutcome
}

enum RuntimeConfigResolver {
    static let defaultFetchTimeoutSeconds: TimeInterval = 5

    static func resolve(
        defaultUrl: String,
        cachedRaw: String?,
        fetchResult: FetchResult
    ) -> EndpointResolution {
        let fetched: String? = switch fetchResult {
        case .success(let raw): EndpointPolicy.validate(raw: raw)
        default: nil
        }
        if let fetched {
            return EndpointResolution(url: fetched, source: .fetch, outcome: .applied)
        }
        if let cached = EndpointPolicy.validate(raw: cachedRaw) {
            return EndpointResolution(url: cached, source: .cache, outcome: fetchOutcome(for: fetchResult))
        }
        return EndpointResolution(url: defaultUrl, source: .default, outcome: fetchOutcome(for: fetchResult))
    }

    private static func fetchOutcome(for fetchResult: FetchResult) -> FetchOutcome {
        switch fetchResult {
        case .success: .emptyOrInvalid
        case .unavailable: .unavailable
        case .timeout: .timeout
        case .error: .error
        }
    }
}
