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

enum OAuthCallbackError: Error {
    case invalidCallback
    case missingCode
    case exchangeFailed
}

struct OAuthCallbackParser {
    static func code(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "aipose",
              components.host == "auth",
              components.path == "/callback",
              components.fragment == nil,
              let items = components.queryItems,
              items.count == 1,
              items[0].name == "code",
              let code = items[0].value,
              !code.isEmpty else {
            return nil
        }
        return code
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
            guard let callbackURL, let code = OAuthCallbackParser.code(from: callbackURL) else {
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
