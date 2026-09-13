import Foundation

struct SessionCredentials: Codable, Sendable, Equatable {
    let accessToken: String
    let refreshToken: String
}

protocol TokenStoring: Sendable {
    func saveCredentials(_ credentials: SessionCredentials)
    func loadCredentials() -> SessionCredentials?
    func clearCredentials()
}
