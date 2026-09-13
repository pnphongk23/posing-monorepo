import Foundation

struct PoseAPIError: Error, Sendable {
    let code: String
    let message: String
}

enum UnauthorizedCodes {
    static let all: Set<String> = ["UNAUTHORIZED", "401", "AUTH_FAILED"]

    static func contains(_ code: String?) -> Bool {
        guard let code else { return false }
        return all.contains(code)
    }
}

extension PoseAPIError {
    var isUnauthorized: Bool { UnauthorizedCodes.contains(code) }
}

enum APIClientError: Error, Sendable {
    case invalidURL
    case cancelled
    case httpStatus(Int)
    case decodingFailed
}
