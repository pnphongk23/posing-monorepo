import Foundation
import FirebaseAnalytics
import FirebaseCore

/// Where a paywall presentation came from. The shutter press is the automatic trigger; Settings →
/// Premium is the user-initiated one. The value is also the analytics `trigger` parameter, so the
/// enum is the only place the two strings exist.
enum PaywallTrigger: String, Equatable {
    case shutter
    case settings
}

/// One sink for the paywall's funnel events, mirroring the adapter's own seam
/// (`RevenueCatAdapter.logEvent`): production defaults to Firebase, tests inject a recorder and assert
/// "fires once, with these parameters" without a network or a mock protocol.
typealias PaywallAnalyticsSink = (String, [String: String]) -> Void

/// The paywall's event names, in one place, so the emitters, the tests and the funnel dashboard
/// cannot drift apart.
enum PaywallEvent {
    /// Once per presentation.
    static let view = "paywall_view"
    static let planSelect = "paywall_plan_select"
    static let ctaTap = "paywall_cta_tap"
    static let close = "paywall_close"
    static let restoreTap = "paywall_restore_tap"
}

enum PaywallAnalytics {
    /// The only call into the analytics SDK on this surface. Parameters are enumerated strings; no
    /// account id, email, app user id, token or price ever reaches them.
    ///
    /// The `FirebaseApp` guard mirrors `AppDelegate.tryConfigureFirebase()`: a build whose
    /// `GoogleService-Info.plist` is a placeholder never configures Firebase, and an event must be a
    /// quiet no-op there (unit tests and Dev builds included) instead of an SDK call on an
    /// unconfigured app.
    static func production(_ name: String, _ parameters: [String: String]) {
        guard FirebaseApp.app() != nil else { return }
        Analytics.logEvent(name, parameters: parameters)
    }
}
