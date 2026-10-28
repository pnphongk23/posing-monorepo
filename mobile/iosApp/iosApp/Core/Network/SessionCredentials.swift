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

/// Has this install ever held a real session?
///
/// The question is about the *device install*, not the current session, so it outlives sign-out,
/// 401 clears and account switches: the Account surface uses it to tell a first-time visitor
/// (nothing to "again") from a user whose session ended ("sign in again"). A fresh install that
/// never signed in answers `false`.
protocol SignInHistoryRecording: Sendable {
    var hasSignedInBefore: Bool { get }
    func recordSignedIn()
}

/// Minimal persistence for `SignInHistoryRecording`: one flag in `UserDefaults`. `SessionBoundary`
/// is the only writer, because it is the single owner of credential mutations; readers only ask the
/// question, so the two sides cannot disagree. QA's `clearState` launch wipes it back to a fresh
/// install, which is exactly the state the neutral copy describes.
final class UserDefaultsSignInHistory: SignInHistoryRecording, @unchecked Sendable {
    static let shared = UserDefaultsSignInHistory()
    static let key = "session.hasSignedInBefore"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasSignedInBefore: Bool { defaults.bool(forKey: Self.key) }

    func recordSignedIn() { defaults.set(true, forKey: Self.key) }
}
