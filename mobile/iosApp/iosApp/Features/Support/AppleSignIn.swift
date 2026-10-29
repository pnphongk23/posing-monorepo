import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// Why the sheet is being shown. A sign-in asks for the profile scopes; a deletion re-auth asks for
/// no scopes at all, because it only needs a fresh authorization code to revoke the grant.
enum AppleAuthorizationPurpose: Equatable, Sendable {
    case signIn
    case deleteAccountReauth

    var requestedScopes: [ASAuthorization.Scope] {
        switch self {
        case .signIn: return [.fullName, .email]
        case .deleteAccountReauth: return []
        }
    }
}

struct AppleAuthorizationRequest: Equatable, Sendable {
    let rawNonce: String
    let requestNonce: String
    var purpose: AppleAuthorizationPurpose = .signIn
}

struct AppleAuthorizationResult: Equatable, Sendable {
    let identityToken: String
    let rawNonce: String
    let fullName: String?
    /// Present on every authorization; the deletion re-auth exists only to obtain it.
    var authorizationCode: String? = nil
}

enum AppleAuthorizationError: Error, LocalizedError, Sendable {
    case invalidCredential
    case invalidIdentityToken
    case invalidAuthorizationCode

    var errorDescription: String? {
        switch self {
        case .invalidCredential: return "Apple sign-in returned an invalid credential."
        case .invalidIdentityToken: return "Apple sign-in returned an invalid identity token."
        case .invalidAuthorizationCode: return "Apple did not return an authorization code."
        }
    }
}

enum AppleNonce {
    private static let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
    static let minimumLength = 32

    static func random() -> String {
        var generator = SystemRandomNumberGenerator()
        return String((0..<minimumLength).map { _ in
            alphabet[Int.random(in: 0..<alphabet.count, using: &generator)]
        })
    }

    static func sha256Hex(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)
        ).map { String(format: "%02x", $0) }.joined()
    }
}

protocol AppleAuthorizationProviding: AnyObject, Sendable {
    @MainActor
    func authorize(_ request: AppleAuthorizationRequest) async throws -> AppleAuthorizationResult
}

@MainActor
final class AuthenticationServicesAppleAuthorizationProvider: NSObject, AppleAuthorizationProviding,
    ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<AppleAuthorizationResult, Error>?
    private var controller: ASAuthorizationController?
    private var rawNonce = ""
    private var purpose: AppleAuthorizationPurpose = .signIn

    func authorize(_ requestData: AppleAuthorizationRequest) async throws -> AppleAuthorizationResult {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = requestData.purpose.requestedScopes
        request.nonce = requestData.requestNonce
        rawNonce = requestData.rawNonce
        purpose = requestData.purpose
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let controller = ASAuthorizationController(authorizationRequests: [request])
                controller.delegate = self
                controller.presentationContextProvider = self
                self.controller = controller
                controller.performRequests()
            }
        }, onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(.failure(CancellationError()))
            }
        })
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? UIWindow()
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            finish(.failure(AppleAuthorizationError.invalidCredential))
            return
        }
        guard let identityToken = credential.identityToken,
              let token = String(data: identityToken, encoding: .utf8),
              !token.isEmpty else {
            finish(.failure(AppleAuthorizationError.invalidIdentityToken))
            return
        }
        let authorizationCode = credential.authorizationCode
            .flatMap { String(data: $0, encoding: .utf8) }
            .flatMap { $0.isEmpty ? nil : $0 }
        if purpose == .deleteAccountReauth, authorizationCode == nil {
            finish(.failure(AppleAuthorizationError.invalidAuthorizationCode))
            return
        }
        let fullName = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        finish(.success(AppleAuthorizationResult(
            identityToken: token,
            rawNonce: rawNonce,
            fullName: fullName.isEmpty ? nil : fullName,
            authorizationCode: authorizationCode
        )))
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        if let authorizationError = error as? ASAuthorizationError,
           authorizationError.code == .canceled {
            finish(.failure(CancellationError()))
        } else {
            finish(.failure(error))
        }
    }

    private func finish(_ result: Result<AppleAuthorizationResult, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        controller = nil
        continuation.resume(with: result)
    }
}

@MainActor
struct AppleSignInAction {
    typealias SignIn = @MainActor @Sendable (String, String, String?) async throws -> Void

    enum Outcome: Equatable {
        case succeeded
        case cancelled
        case failed(String)
    }

    private let provider: any AppleAuthorizationProviding
    private let signIn: SignIn

    init(
        provider: any AppleAuthorizationProviding = AuthenticationServicesAppleAuthorizationProvider(),
        signIn: @escaping SignIn = { identityToken, nonce, fullName in
            try await ServiceLocator.makeAPIClient().signInWithApple(
                identityToken: identityToken, nonce: nonce, fullName: fullName
            )
        }
    ) {
        self.provider = provider
        self.signIn = signIn
    }

    func run() async -> Outcome {
        let rawNonce = AppleNonce.random()
        let request = AppleAuthorizationRequest(rawNonce: rawNonce, requestNonce: AppleNonce.sha256Hex(rawNonce))
        do {
            let result = try await provider.authorize(request)
            try await signIn(result.identityToken, rawNonce, result.fullName)
            return .succeeded
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed(ErrorCopy.text(for: error) ?? "Sign-in could not be completed.")
        }
    }
}

@MainActor
final class AppleSignInModel: ObservableObject {
    @Published private(set) var isAuthenticating = false
    @Published private(set) var error: String?

    private let action: AppleSignInAction

    init(action: AppleSignInAction = AppleSignInAction()) {
        self.action = action
    }

    func signIn() async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        error = nil
        defer { isAuthenticating = false }
        switch await action.run() {
        case .succeeded: return true
        case .cancelled: return false
        case .failed(let text):
            error = text
            return false
        }
    }

    func clearError() {
        error = nil
    }
}

/// Raised when the Apple sheet fails for a reason the user cannot retry blindly (no code came back,
/// or the system reported an error). Carries user-facing copy so the Account screen can show it.
struct AppleReauthorizationError: Error, LocalizedError, Sendable {
    let message: String

    var errorDescription: String? { message }
}

/// Apple confirmation for an account deletion: the same `ASAuthorizationAppleIDProvider` seam as
/// sign-in, asking for no scopes and returning only the fresh authorization code the server trades
/// for the user's refresh token. We never store an Apple token.
@MainActor
struct AppleReauthorizationAction {
    enum Outcome: Equatable {
        case code(String)
        case cancelled
        case failed(String)
    }

    private let provider: any AppleAuthorizationProviding

    init(provider: any AppleAuthorizationProviding = AuthenticationServicesAppleAuthorizationProvider()) {
        self.provider = provider
    }

    func run() async -> Outcome {
        let rawNonce = AppleNonce.random()
        let request = AppleAuthorizationRequest(
            rawNonce: rawNonce,
            requestNonce: AppleNonce.sha256Hex(rawNonce),
            purpose: .deleteAccountReauth
        )
        do {
            let result = try await provider.authorize(request)
            guard let code = result.authorizationCode, !code.isEmpty else {
                return .failed(AccountStateCopy.deleteAccountAppleConfirmationFailedMessage)
            }
            return .code(code)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed(AccountStateCopy.deleteAccountAppleConfirmationFailedMessage)
        }
    }

    /// The code, or `CancellationError` when the user closed the sheet. Every other failure carries
    /// the "couldn't confirm with Apple" copy, so the caller has one place to decide what to say.
    func authorizationCode() async throws -> String {
        switch await run() {
        case .code(let code): return code
        case .cancelled: throw CancellationError()
        case .failed(let text): throw AppleReauthorizationError(message: text)
        }
    }
}
