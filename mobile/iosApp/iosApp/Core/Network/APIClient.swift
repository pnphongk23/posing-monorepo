import Foundation

struct APIClient: Sendable {
    let baseURL: String
    let session: URLSession
    let boundary: SessionBoundary
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    init(baseURL: String, session: URLSession = .shared, boundary: SessionBoundary) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.session = session
        self.boundary = boundary
    }

    func request(
        path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: Data? = nil,
        contentType: String? = "application/json",
        acceptedStatus: Set<Int> = [200]
    ) async throws -> (Data, HTTPURLResponse) {
        try await performRequest(
            path: path, method: method, query: query, body: body,
            contentType: contentType, acceptedStatus: acceptedStatus, allowRefresh: true
        )
    }

    private func performRequest(
        path: String,
        method: String,
        query: [URLQueryItem],
        body: Data?,
        contentType: String?,
        acceptedStatus: Set<Int>,
        allowRefresh: Bool
    ) async throws -> (Data, HTTPURLResponse) {
        guard var components = URLComponents(string: "\(baseURL)\(path)") else {
            throw APIClientError.invalidURL
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIClientError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if let body { request.httpBody = body }
        if let token = await boundary.loadAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.httpStatus(-1)
        }

        if http.statusCode == 401, allowRefresh {
            let refreshed = await boundary.refresh { refreshToken in
                await self.refreshSession(refreshToken: refreshToken)
            }
            if refreshed {
                return try await performRequest(
                    path: path, method: method, query: query, body: body,
                    contentType: contentType, acceptedStatus: acceptedStatus, allowRefresh: false
                )
            }
        }

        if !acceptedStatus.contains(http.statusCode) {
            if let envelope = try? decoder.decode(ApiErrorEnvelope.self, from: data),
               let error = envelope.error {
                throw PoseAPIError(
                    code: error.code ?? String(http.statusCode),
                    message: error.message ?? "Server error: \(http.statusCode)"
                )
            }
            throw PoseAPIError(
                code: String(http.statusCode),
                message: "Server error: \(http.statusCode)"
            )
        }
        return (data, http)
    }

    func refreshSession(refreshToken: String) async -> SessionCredentials? {
        guard let url = URL(string: "\(baseURL)/api/auth/refresh") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(RefreshRequest(refreshToken: refreshToken))
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let decoded = try decoder.decode(RefreshResponse.self, from: data)
            return SessionCredentials(accessToken: decoded.accessToken, refreshToken: decoded.refreshToken)
        } catch {
            return nil
        }
    }

    /// Email + password sign-in (PLAN §4). Mirrors `exchangeSession`, but runs without the
    /// 401-refresh retry: a sign-in 401 is `INVALID_CREDENTIALS`, not an expired access token, so
    /// letting it fall into the refresh cycle would clear a real session on a wrong password.
    func signInWithPassword(email: String, password: String) async throws {
        let body = try JSONEncoder().encode(EmailSignInRequest(email: email, password: password))
        let (data, _) = try await performRequest(
            path: "/api/auth/email/signin",
            method: "POST",
            query: [],
            body: body,
            contentType: "application/json",
            acceptedStatus: [200],
            allowRefresh: false
        )
        let response = try decoder.decode(EmailSignInResponse.self, from: data)
        await boundary.saveCredentials(
            SessionCredentials(accessToken: response.accessToken, refreshToken: response.refreshToken)
        )
    }

    /// Apple sign-in sends the raw nonce paired with Apple's hashed request nonce. Like password
    /// sign-in, a 401 is an auth failure and must not enter the refresh cycle.
    func signInWithApple(identityToken: String, nonce: String, fullName: String?) async throws {
        let body = try JSONEncoder().encode(AppleSignInRequest(
            identityToken: identityToken,
            nonce: nonce,
            fullName: fullName
        ))
        let (data, _) = try await performRequest(
            path: "/api/auth/apple/signin",
            method: "POST",
            query: [],
            body: body,
            contentType: "application/json",
            acceptedStatus: [200],
            allowRefresh: false
        )
        let response = try decoder.decode(AppleSignInResponse.self, from: data)
        await boundary.saveCredentials(
            SessionCredentials(accessToken: response.accessToken, refreshToken: response.refreshToken)
        )
    }

    /// Account deletion succeeds only on 204. Credential ownership stays with the caller so a
    /// failed delete cannot accidentally sign out the user.
    ///
    /// For an account that signs in with Apple the server answers `409 APPLE_REAUTH_REQUIRED` first;
    /// the retry then carries the fresh authorization code, which the server trades for — and
    /// revokes — the Apple grant. We never store an Apple token.
    func deleteAccount(appleAuthorizationCode: String? = nil) async throws {
        let body: Data?
        if let appleAuthorizationCode {
            body = try JSONEncoder().encode(AppleAccountDeletionRequest(appleAuthorizationCode: appleAuthorizationCode))
        } else {
            body = nil
        }
        do {
            _ = try await performRequest(
                path: "/api/account",
                method: "DELETE",
                query: [],
                body: body,
                contentType: body == nil ? nil : "application/json",
                acceptedStatus: [204],
                allowRefresh: false
            )
        } catch let error as PoseAPIError {
            // A 409 here is a required second step, not a failure: surface it as its own type so the
            // account model cannot mistake it for an error the user has to read.
            if let challenge = AccountDeletionError(apiError: error) {
                throw challenge
            }
            throw error
        }
    }

    func exchangeSession(code: String) async throws {
        let body = try JSONEncoder().encode(SessionExchangeRequest(code: code))
        let (data, _) = try await request(
            path: "/api/auth/session",
            method: "POST",
            body: body,
            acceptedStatus: [200]
        )
        let credentials = try decoder.decode(SessionExchangeResponse.self, from: data)
        await boundary.saveCredentials(
            SessionCredentials(accessToken: credentials.accessToken, refreshToken: credentials.refreshToken)
        )
    }

    func decode<T: Decodable & Sendable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }
}
