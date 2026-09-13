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
