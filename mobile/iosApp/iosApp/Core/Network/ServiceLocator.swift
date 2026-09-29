import Foundation

/// Shared native service wiring. Endpoint must be applied before first API use.
enum ServiceLocator {
    static let tokenStorage: TokenStoring = KeychainTokenStorage()
    static let sessionBoundary = SessionBoundary(tokenStorage: tokenStorage)

    static func makeAPIClient(baseURL: String? = nil) -> APIClient {
        APIClient(
            baseURL: baseURL ?? AppConfig.shared.SERVER_BASE_URL,
            boundary: sessionBoundary
        )
    }

    static func makePoseAPIService(baseURL: String? = nil) -> PoseAPIService {
        PoseAPIService(client: makeAPIClient(baseURL: baseURL))
    }

    @MainActor
    static let jobsService: JobsService = JobsService()
}
