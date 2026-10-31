import Foundation

/// What the app remembers about the third-party-AI disclosure on Add pose (App Review 5.1.2(i)).
///
/// The record is per **account**, not per install: two people signing in on the same phone each get
/// asked once, and signing out does not carry one person's answer to the next. `promptsEveryUpload`
/// is the shipped policy switch, so "ask once per account" and "ask on every upload" are one flag
/// apart instead of two code paths.
protocol AddPoseConsentStoring: Sendable {
    /// `true` asks before every upload; `false` asks once per signed-in account.
    var promptsEveryUpload: Bool { get }

    /// The backend account id of the current session, or `nil` when the install holds no session.
    func accountID() async -> String?

    func hasAcknowledged(accountID: String) -> Bool

    func recordAcknowledgement(accountID: String)
}

/// `UserDefaults`-backed consent ledger keyed by backend account id.
///
/// Only a boolean per account is stored — no photo, no form content, nothing that identifies what was
/// uploaded — so the ledger cannot become a second copy of a user's data.
final class AddPoseConsentStore: AddPoseConsentStoring, @unchecked Sendable {
    static let shared = AddPoseConsentStore()

    /// The one line that changes the consent policy.
    ///
    /// `false` (shipped): the sheet appears once per signed-in account and the acknowledgement is
    /// written before the first upload. `true`: the sheet appears before every upload and nothing is
    /// remembered. Both paths send the photo only after Allow, so the flag is a frequency choice, never
    /// a consent bypass.
    static let promptEveryUpload = false

    static let keyPrefix = "addPose.consent.acknowledged."

    private let defaults: UserDefaults
    private let keyPrefix: String
    private let accountIDProvider: @Sendable () async -> String?

    let promptsEveryUpload: Bool

    init(
        defaults: UserDefaults = .standard,
        keyPrefix: String = AddPoseConsentStore.keyPrefix,
        promptsEveryUpload: Bool = AddPoseConsentStore.promptEveryUpload,
        accountIDProvider: @escaping @Sendable () async -> String? = AddPoseConsentStore.sessionAccountID
    ) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
        self.promptsEveryUpload = promptsEveryUpload
        self.accountIDProvider = accountIDProvider
    }

    /// Default identity source: the session token this install already holds.
    ///
    /// Resolving the id from the token instead of `GET /api/account/me` keeps the gate offline-safe —
    /// a consent check must never be the reason a submit fails or waits on the network.
    static let sessionAccountID: @Sendable () async -> String? = {
        AddPoseConsentStore.accountID(
            fromAccessToken: ServiceLocator.tokenStorage.loadCredentials()?.accessToken
        )
    }

    /// The backend identifies an account by the Supabase `sub` claim — `accountAuth` verifies the
    /// token and looks the account up by it, so `sub` is exactly `AccountSummary.id`. The claim is read
    /// as a local cache key only: it is never trusted for authorization, and nothing is decoded from
    /// the signature segment.
    static func accountID(fromAccessToken token: String?) -> String? {
        guard let token else { return nil }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        guard let payload = base64URLData(String(parts[1])),
              let object = try? JSONSerialization.jsonObject(with: payload),
              let claims = object as? [String: Any],
              let subject = claims["sub"] as? String
        else { return nil }
        let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func accountID() async -> String? {
        await accountIDProvider()
    }

    func hasAcknowledged(accountID: String) -> Bool {
        guard !accountID.isEmpty else { return false }
        return defaults.bool(forKey: keyPrefix + accountID)
    }

    func recordAcknowledgement(accountID: String) {
        guard !accountID.isEmpty else { return }
        defaults.set(true, forKey: keyPrefix + accountID)
    }

    private static func base64URLData(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        return Data(base64Encoded: base64)
    }
}
