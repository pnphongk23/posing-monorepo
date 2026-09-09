import AuthenticationServices
import ComposeApp
import Foundation
import UIKit

// MARK: - WI-04 Kotlin → Swift sign-in bridge
//
// The Compose layer drives the single existing OAuth seam by posting
// `com.aipose.google.signin.request`; this observer runs the own-API
// OAuthHandoff flow and posts a REAL result back on `com.aipose.google.signin.response`
// (`result` = "success" | "failure", plus `message` on failure). No parallel auth
// flow and no fake success: the response is only ever emitted by the genuine
// [OAuthHandoff.start] completion after the own-API /api/auth/session exchange
// and credential persistence.

extension Notification.Name {
    static let aiposeGoogleSignInRequest = Notification.Name("com.aipose.google.signin.request")
    static let aiposeGoogleSignInResponse = Notification.Name("com.aipose.google.signin.response")
}

/// Single observable bridge that starts the existing OAuth flow on request and
/// posts the real outcome back to Kotlin. Install at native app startup via
/// `OAuthSignInObserver.shared` (harmless to touch more than once).
final class OAuthSignInObserver: NSObject {
    static let shared: OAuthSignInObserver = {
        let observer = OAuthSignInObserver()
        observer.install()
        return observer
    }()

    private var token: NSObjectProtocol?
    private let handoff = OAuthHandoff()

    func install() {
        guard token == nil else { return }
        token = NotificationCenter.default.addObserver(
            forName: .aiposeGoogleSignInRequest,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleRequest()
        }
    }

    private func handleRequest() {
        handoff.start { [weak self] result in
            guard self != nil else { return }
            let info: [String: Any]
            switch result {
            case .success:
                info = ["result": "success"]
            case .failure(let error):
                info = ["result": "failure", "message": error.localizedDescription]
            }
            NotificationCenter.default.post(
                name: .aiposeGoogleSignInResponse,
                object: nil,
                userInfo: info
            )
        }
    }
}

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
        guard let fragment = components.fragment, !fragment.isEmpty else {
            return []
        }
        // URLComponents parses the fragment as an opaque string, so parse it as
        // a query only after the callback scheme has been validated.
        let fragmentQuery = fragment.hasPrefix("?") ? String(fragment.dropFirst()) : fragment
        return URLComponents(string: "?\(fragmentQuery)")?.queryItems ?? []
    }

    private static func items(named name: String, in items: [URLQueryItem]) -> [URLQueryItem] {
        items.filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    private static func queryItems(from url: URL) -> (query: [URLQueryItem], fragment: [URLQueryItem])? {
        guard let components = components(from: url) else {
            return nil
        }
        return (components.queryItems ?? [], fragmentItems(from: components))
    }

    static func code(from url: URL) -> String? {
        guard let parts = queryItems(from: url) else {
            return nil
        }

        // The own backend intentionally sends code in the query. Prefer it and
        // do not merge it with a second provider fragment response.
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
        guard let parts = queryItems(from: url) else {
            return nil
        }

        for items in [parts.query, parts.fragment] {
            guard let error = self.items(named: "error", in: items).first?.value,
                  !error.isEmpty else {
                continue
            }
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

struct SessionExchangeResponse: Decodable {
    let accessToken: String
    let refreshToken: String
}

final class OAuthHandoff: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    func start(completion: @escaping (Result<Void, Error>) -> Void) {
        let baseURL = AppConfig.shared.SERVER_BASE_URL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let startURL = URL(string: "\(baseURL)/api/auth/google/start") else {
            completion(.failure(OAuthCallbackError.invalidCallback))
            return
        }

        let authenticationSession = ASWebAuthenticationSession(
            url: startURL,
            callbackURLScheme: "aipose"
        ) { [weak self] callbackURL, error in
            self?.session = nil
            if let error {
                completion(.failure(error))
                return
            }
            guard let callbackURL else {
                completion(.failure(OAuthCallbackError.invalidCallback))
                return
            }
            // Keep callback diagnostics safe: structure and parameter names only,
            // never the one-time code or exchanged tokens.
            print("[OAuth] callback \(OAuthCallbackParser.summary(from: callbackURL))")
            if let providerError = OAuthCallbackParser.providerError(from: callbackURL) {
                completion(.failure(OAuthCallbackError.providerDenied(providerError)))
                return
            }
            guard let code = OAuthCallbackParser.code(from: callbackURL) else {
                completion(.failure(OAuthCallbackError.missingCode))
                return
            }
            self?.exchange(code: code, baseURL: baseURL, completion: completion)
        }
        authenticationSession.presentationContextProvider = self
        authenticationSession.prefersEphemeralWebBrowserSession = false
        session = authenticationSession
        authenticationSession.start()
    }

    private func exchange(
        code: String,
        baseURL: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/api/auth/session") else {
            completion(.failure(OAuthCallbackError.exchangeFailed))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["code": code])

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard error == nil,
                  let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let data,
                  let credentials = try? JSONDecoder().decode(SessionExchangeResponse.self, from: data) else {
                DispatchQueue.main.async { completion(.failure(error ?? OAuthCallbackError.exchangeFailed)) }
                return
            }
            IosSessionBridgeKt.persistSessionCredentials(
                accessToken: credentials.accessToken,
                refreshToken: credentials.refreshToken
            )
            DispatchQueue.main.async { completion(.success(())) }
        }.resume()
    }
}
