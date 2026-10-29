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


/// A deletion that needs one more Apple step before it can proceed. This is not a user-facing
/// failure: the Account model runs the Apple sheet and retries exactly once.
enum AccountDeletionError: Error, Equatable, Sendable {
    case appleReauthRequired
    case appleIdentityMismatch

    init?(apiError: PoseAPIError) {
        switch apiError.code {
        case "APPLE_REAUTH_REQUIRED": self = .appleReauthRequired
        case "APPLE_IDENTITY_MISMATCH": self = .appleIdentityMismatch
        default: return nil
        }
    }
}
