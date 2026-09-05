// iosApp/iosApp/AppDelegate.swift
import UIKit
import ComposeApp
import FirebaseCore
import FirebaseRemoteConfig
import FirebaseAnalytics
import FirebaseCrashlytics

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        AIPoseCameraBridgeRuntime.install()

        // WI-04: arm the Google sign-in bridge observer BEFORE any Kotlin
        // com.aipose.google.signin.request can be posted, so the existing
        // OAuthHandoff own-API flow can be started from the Compose layer.
        // Minimal real access — no auth-semantics change, no second flow.
        _ = OAuthSignInObserver.shared

        // FEAT-010 / DEC-007: configure Firebase best-effort only when a real
        // GoogleService-Info.plist is present in the bundle. The real plist is
        // supplied out of band and git-ignored; a missing or placeholder-shaped
        // plist is skipped so the app boots without Firebase.
        tryConfigureFirebase()
        RevenueCatAdapter.shared.configureFromEnvironment()

        // FEAT-010 / DEC-006: resolve the api_baseurl endpoint (cache/fetch/
        // default) and apply it to both Kotlin holders BEFORE the Compose root
        // is created, then show the root. The native launch screen covers the
        // bounded wait.
        resolveEndpointThenShowRoot()

        return true
    }

    // MARK: - Firebase configuration

    private func tryConfigureFirebase() {
        guard let url = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") else {
            return
        }
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return
        }
        guard let apiKey = plist["API_KEY"] as? String, !apiKey.isEmpty, apiKey.hasPrefix("AIza") else {
            return
        }
        // Firebase GOOGLE_APP_ID shape: 1:<project-number>:ios:<hex> (four colon
        // segments). Prior regex required a 7+ digit first segment and skipped
        // valid production plists such as 1:##########:ios:##########.
        guard let appId = plist["GOOGLE_APP_ID"] as? String,
              appId.range(of: #"^1:\d{6,}:ios:[0-9a-f]+$"#, options: .regularExpression) != nil else {
            return
        }
        // Reject obviously placeholder values.
        let joined = plist.values.compactMap { "\($0)" }.joined(separator: " ").lowercased()
        guard !joined.contains("placeholder") && !joined.contains("example") else {
            return
        }
        FirebaseApp.configure()
    }

    private var isFirebaseConfigured: Bool {
        FirebaseApp.app() != nil
    }

    // MARK: - DEC-006 endpoint resolution

    private func resolveEndpointThenShowRoot() {
        let defaultUrl = AppConfig.shared.SERVER_BASE_URL
        let key = EndpointPolicy.shared.REMOTE_CONFIG_KEY
        let start = Date()
        // Guard so the completion and the timeout can never apply/show twice.
        var didResolve = false

        // Single application path into Kotlin (sets both holders consistently),
        // guarded by `didResolve`. Runs on the main queue.
        let applyAndShow: (String, String) -> Void = { [weak self] finalUrl, source in
            guard !didResolve else { return }
            didResolve = true
            AppStartupConfig.shared.applyEndpoint(url: finalUrl)
            self?.logEndpointResolved(source: source, startedAt: start)
            self?.showRootViewController()
        }

        guard isFirebaseConfigured else {
            // No Firebase: source default, no observability.
            applyAndShow(defaultUrl, "default")
            return
        }

        let remoteConfig = RemoteConfig.remoteConfig()
        // Capture the pre-fetch valid cache BEFORE fetchAndActivate so a failed
        // or invalid fetch can never clobber a last-known-good value.
        let preFetchCache = EndpointPolicy.shared.validate(raw: remoteConfig.configValue(forKey: key).stringValue)

        // Bounded wait safety net: if the callback never fires, use the
        // pre-fetch cache (or the source default). Startup never blocks forever.
        let timeout = DispatchWorkItem { [weak self] in
            let final = preFetchCache ?? defaultUrl
            applyAndShow(final, preFetchCache != nil ? "cache" : "default")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: timeout)

        remoteConfig.fetchAndActivate { [weak self] status, _ in
            timeout.cancel()
            // Only treat the post-fetch value as "fetched" when Firebase reports a
            // successful activation (fetched from remote OR using pre-fetched data)
            // AND it validates; otherwise fall back to the valid pre-fetch cache,
            // then the provisional default. The decision is delegated to the shared
            // pure-Kotlin resolver so precedence is covered by common tests.
            let isSuccess = (status == RemoteConfigFetchAndActivateStatus.successFetchedFromRemote
                || status == RemoteConfigFetchAndActivateStatus.successUsingPreFetchedData)
            let fetchedRaw: String? = isSuccess
                ? remoteConfig.configValue(forKey: key).stringValue
                : nil
            let final = AppStartupConfig.shared.resolveEndpointValue(
                defaultUrl: defaultUrl,
                cachedRaw: preFetchCache,
                fetchedRaw: fetchedRaw
            )
            let source: String
            if isSuccess, EndpointPolicy.shared.validate(raw: fetchedRaw) != nil {
                source = "fetch"
            } else if preFetchCache != nil {
                source = "cache"
            } else {
                source = "default"
            }
            applyAndShow(final, source)
        }
    }

    private func logEndpointResolved(source: String, startedAt: Date) {
        guard isFirebaseConfigured else { return }
        Analytics.logEvent("app_start", parameters: nil)
        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        // FR-004: only sanitized, non-sensitive metadata. No pose/camera/payment.
        Analytics.logEvent("endpoint_resolved", parameters: [
            "source": sanitized(source),
            "outcome": sanitized("applied"),
            "duration_ms": "\(min(durationMs, 100000))",
        ])
        Crashlytics.crashlytics().log("endpoint_source=\(sanitized(source))")
    }

    // Mirror the Kotlin EventSanitizer value-safety contract minimally.
    private func sanitized(_ value: String) -> String {
        // Only non-sensitive metadata is allowed: no URLs, spaces, or long tokens.
        if value.contains("://") || value.contains(" ") || value.count > 100 {
            return "redacted"
        }
        return value
    }

    private func showRootViewController() {
        window = UIWindow(frame: UIScreen.main.bounds)
        let mainViewController = MainViewControllerKt.MainViewController()
        window?.rootViewController = mainViewController
        window?.makeKeyAndVisible()
    }
}
