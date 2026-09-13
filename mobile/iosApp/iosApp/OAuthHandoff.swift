import AuthenticationServices
import Foundation
import UIKit

enum OAuthCallbackError: LocalizedError {
    case invalidCallback
    case missingCode
    case providerDenied(String)
    case exchangeFailed

    var errorDescription: String? {
        switch self {
        case .invalidCallback:
            return "Unable to start Google sign-in."
        case .missingCode:
            return "Google sign-in returned an invalid callback."
        case .providerDenied(let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Google sign-in was not completed." : "Google sign-in failed: \(trimmed)"
        case .exchangeFailed:
            return "Unable to finish Google sign-in. Please try again."
        }
    }
}

struct OAuthCallbackParser {
    private static func components(from url: URL) -> URLComponents? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.caseInsensitiveCompare("aipose") == .orderedSame else {
            return nil
        }
        return components
    }

    private static func fragmentItems(from components: URLComponents) -> [URLQueryItem] {
        guard let fragment = components.fragment, !fragment.isEmpty else { return [] }
        let fragmentQuery = fragment.hasPrefix("?") ? String(fragment.dropFirst()) : fragment
        return URLComponents(string: "?\(fragmentQuery)")?.queryItems ?? []
    }

    private static func items(named name: String, in items: [URLQueryItem]) -> [URLQueryItem] {
        items.filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    private static func queryItems(from url: URL) -> (query: [URLQueryItem], fragment: [URLQueryItem])? {
        guard let components = components(from: url) else { return nil }
        return (components.queryItems ?? [], fragmentItems(from: components))
    }

    static func code(from url: URL) -> String? {
        guard let parts = queryItems(from: url) else { return nil }
        let queryCodeItems = items(named: "code", in: parts.query)
        if queryCodeItems.count == 1,
           let code = queryCodeItems[0].value,
           !code.isEmpty {
            return code
        }
        let fragmentCodeItems = items(named: "code", in: parts.fragment)
        guard fragmentCodeItems.count == 1,
              let code = fragmentCodeItems[0].value,
              !code.isEmpty else {
            return nil
        }
        return code
    }

    static func providerError(from url: URL) -> String? {
        guard let parts = queryItems(from: url) else { return nil }
        for items in [parts.query, parts.fragment] {
            guard let error = self.items(named: "error", in: items).first?.value,
                  !error.isEmpty else { continue }
            return self.items(named: "error_description", in: items).first?.value ?? error
        }
        return nil
    }

    static func summary(from url: URL) -> String {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryKeys = (components?.queryItems ?? []).map(\.name)
        let fragmentKeys: [String]
        if let fragment = components?.fragment,
           let fragmentComponents = URLComponents(string: "?\(fragment)") {
            fragmentKeys = (fragmentComponents.queryItems ?? []).map(\.name)
        } else {
            fragmentKeys = []
        }
        return "scheme=\(components?.scheme ?? "nil") host=\(components?.host ?? "nil") path=\(components?.path ?? "nil") queryKeys=\(queryKeys.joined(separator: ",")) fragmentKeys=\(fragmentKeys.joined(separator: ",")) hasFragment=\(components?.fragment != nil)"
    }
}

@MainActor
final class OAuthHandoff: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private let apiClient: APIClient

    init(apiClient: APIClient = ServiceLocator.makeAPIClient()) {
        self.apiClient = apiClient
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    func start() async throws {
        let baseURL = AppConfig.shared.SERVER_BASE_URL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let startURL = URL(string: "\(baseURL)/api/auth/google/start") else {
            throw OAuthCallbackError.invalidCallback
        }
        let callbackURL = try await beginWebAuthentication(startURL: startURL)
        print("[OAuth] callback \(OAuthCallbackParser.summary(from: callbackURL))")
        if let providerError = OAuthCallbackParser.providerError(from: callbackURL) {
            throw OAuthCallbackError.providerDenied(providerError)
        }
        guard let code = OAuthCallbackParser.code(from: callbackURL) else {
            throw OAuthCallbackError.missingCode
        }
        do {
            try await apiClient.exchangeSession(code: code)
        } catch {
            throw OAuthCallbackError.exchangeFailed
        }
    }

    private func beginWebAuthentication(startURL: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let authenticationSession = ASWebAuthenticationSession(
                url: startURL,
                callbackURLScheme: "aipose"
            ) { [weak self] callbackURL, error in
                self?.session = nil
                if let authError = error as? ASWebAuthenticationSessionError, authError.code == .canceledLogin {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: OAuthCallbackError.invalidCallback)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            authenticationSession.presentationContextProvider = self
            authenticationSession.prefersEphemeralWebBrowserSession = false
            session = authenticationSession
            authenticationSession.start()
        }
    }
}
