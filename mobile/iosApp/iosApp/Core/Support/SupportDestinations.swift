import Foundation

/// Canonical external destinations used by Settings, Account and the Paywall.
///
/// The URLs are the ones the KMP runtime shipped (`LegalAuthority` in
/// `platform/ExternalActions.kt`): both Google Sites pages respond `200`.
///
/// FEAT-015 `PA-015-04` instead names `https://aipose.app/terms|privacy`, but the
/// `aipose.app` domain is `NXDOMAIN` (verified 2026-09) — opening those produced a dead
/// link, i.e. the reported "tap does nothing" symptom. Do not reintroduce that host
/// without checking it resolves; `SupportDestinationsTests` guards it.
enum SupportDestinations {
    static let termsOfService = "https://sites.google.com/view/posingapp/terms-of-service"
    static let privacyPolicy = "https://sites.google.com/view/posingapp/privacy-policy"
    /// FEAT-015 `PA-015-03`.
    static let support = "https://forms.gle/AaeCnLdnvMz4kCSa6"
    /// Where "Delete account" sends the user: an external request form an admin works through by
    /// hand. The app deletes nothing itself any more, so a working URL is the whole feature —
    /// `SupportDestinationsTests.testDeleteAccountDestinationIsNotAPlaceholder` fails while this is
    /// still the pre-launch placeholder, which is deliberate: shipping it would make the row dead.
    static let deleteAccount = "https://forms.gle/QJo1cwnPPbDSfsPL6"

    static var termsOfServiceURL: URL? { webURL(termsOfService) }
    static var privacyPolicyURL: URL? { webURL(privacyPolicy) }
    static var supportURL: URL? { webURL(support) }
    static var deleteAccountURL: URL? { webURL(deleteAccount) }

    /// `true` while a destination is still the pre-launch stand-in (`REPLACE…` or `sample`).
    /// Those strings are the marker the two placeholder guards in `SupportDestinationsTests` read.
    static func isPlaceholder(_ raw: String) -> Bool {
        let lowered = raw.lowercased()
        return lowered.contains("replace") || lowered.contains("sample")
    }

    /// Accepts only absolute `http(s)` URLs with a host, so a typo or a missing scheme
    /// degrades to "not configured" instead of a tap that silently does nothing.
    static func webURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" "),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else {
            return nil
        }
        return url
    }
}
