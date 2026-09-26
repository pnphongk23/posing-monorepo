import UIKit
import SwiftUI
import FirebaseCore
import FirebaseRemoteConfig
import FirebaseAnalytics
import FirebaseCrashlytics

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private(set) var isFirebaseConfigured = false

    private(set) var galleryBootstrap: GalleryStoreBootstrap = .integrationBlocked("not bootstrapped")

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        isFirebaseConfigured = tryConfigureFirebase()
        AppImage.configure()
        galleryBootstrap = GalleryStoreBootstrap.make()
        // RevenueCat owns the purchase surface (FEAT-011). Configure before any screen can mount so
        // the paywall reads a real offering instead of the fail-closed `unconfigured` state.
        RevenueCatAdapter.shared.configureFromEnvironment()
        // Account-scoped state follows session changes for the whole process, not per screen.
        SessionScopeCoordinator.shared.start()
        resolveEndpointThenShowRoot()
        return true
    }

    private func tryConfigureFirebase() -> Bool {
        guard let url = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") else {
            return false
        }
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return false
        }
        guard let apiKey = plist["API_KEY"] as? String, !apiKey.isEmpty, apiKey.hasPrefix("AIza") else {
            return false
        }
        guard let appId = plist["GOOGLE_APP_ID"] as? String,
              appId.range(of: #"^1:\d{6,}:ios:[0-9a-f]+$"#, options: .regularExpression) != nil else {
            return false
        }
        let joined = plist.values.compactMap { "\($0)" }.joined(separator: " ").lowercased()
        guard !joined.contains("placeholder") && !joined.contains("example") else {
            return false
        }
        FirebaseApp.configure()
        return FirebaseApp.app() != nil
    }

    private func resolveEndpointThenShowRoot() {
        let defaultUrl = StartupEndpoint.defaultURL
        let key = StartupEndpoint.remoteConfigKey
        let start = Date()

        // First paint must not wait for RemoteConfig. The previous version only built the window
        // inside the `fetchAndActivate` callback, with a 5s `asyncAfter` fallback, so a slow or
        // hanging fetch showed *nothing* (no tab bar, no poses, no gallery) for up to five seconds
        // — the reported "first tap on Gallery/Camera takes forever" start. A RemoteConfig read
        // that needs no network is the last-activated cache, which is available synchronously.
        let preFetchCache = isFirebaseConfigured
            ? StartupEndpoint.validate(raw: RemoteConfig.remoteConfig().configValue(forKey: key).stringValue)
            : nil
        let preFetchAccountRaw = isFirebaseConfigured
            ? RemoteConfig.remoteConfig().configValue(forKey: RemoteConfigService.accountEnabledKey).stringValue
            : nil
        let initialAccountEnabled = RemoteConfigService.resolveAccountEnabled(
            cachedRaw: preFetchAccountRaw,
            fetchedRaw: nil
        )
        let initialSource = preFetchCache != nil ? "cache" : "default"
        AppConfig.shared.applyEndpoint(
            StartupEndpoint.resolve(defaultUrl: defaultUrl, cachedRaw: preFetchCache, fetchedRaw: nil)
        )
        RemoteConfigService.applyAccountEnabled(initialAccountEnabled)
        showRootViewController()
        logFirstPaint(startedAt: start, endpointSource: initialSource)

        guard isFirebaseConfigured else {
            logEndpointResolved(source: initialSource, startedAt: start)
            return
        }

        let latch = StartupLatch()

        // Applies fetched startup values and finishes the launch bookkeeping exactly once. The root
        // is rebuilt only when the endpoint or account-feature value differs from the cached value.
        let applyFetched: (String?, String?) -> Void = { [weak self] fetchedRaw, fetchedAccountRaw in
            guard latch.admitFetch() else { return }
            latch.seal()

            let accountEnabledBeforeFetch = AppConfig.shared.isAccountFeatureEnabled
            let fetchedAccountEnabled = RemoteConfigService.resolveAccountEnabled(
                cachedRaw: preFetchAccountRaw,
                fetchedRaw: fetchedAccountRaw
            )
            RemoteConfigService.applyAccountEnabled(fetchedAccountEnabled)
            let accountFeatureChanged = accountEnabledBeforeFetch != AppConfig.shared.isAccountFeatureEnabled

            guard let fetched = StartupEndpoint.validate(raw: fetchedRaw) else {
                if accountFeatureChanged { self?.showRootViewController() }
                guard latch.claimFinalization() else { return }
                self?.logEndpointResolved(source: initialSource, startedAt: start)
                return
            }

            let endpointChanged = fetched != AppConfig.shared.SERVER_BASE_URL
            if endpointChanged {
                AppConfig.shared.applyEndpoint(fetched)
                #if DEBUG
                NSLog("%@", "AIPOSE_PERF endpoint_swapped source=fetch")
                #endif
            }
            if endpointChanged || accountFeatureChanged { self?.showRootViewController() }
            guard latch.claimFinalization() else { return }
            self?.logEndpointResolved(source: "fetch", startedAt: start)
        }

        // Keeps the historical 5s budget for changing the base URL: after it, a late fetch can no
        // longer re-point the app under an interaction that already started.
        let timeout = DispatchWorkItem { [weak self] in
            latch.seal()
            guard latch.claimFinalization() else { return }
            self?.logEndpointResolved(source: initialSource, startedAt: start)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: timeout)

        let remoteConfig = RemoteConfig.remoteConfig()
        remoteConfig.fetchAndActivate { status, _ in
            timeout.cancel()
            let isSuccess = status == .successFetchedFromRemote || status == .successUsingPreFetchedData
            let fetchedRaw: String? = isSuccess
                ? remoteConfig.configValue(forKey: key).stringValue
                : nil
            let fetchedAccountRaw: String? = isSuccess
                ? remoteConfig.configValue(forKey: RemoteConfigService.accountEnabledKey).stringValue
                : nil
            applyFetched(fetchedRaw, fetchedAccountRaw)
        }
    }

    /// Simulator/device-visible evidence that the root exists before the endpoint resolves.
    private func logFirstPaint(startedAt: Date, endpointSource: String) {
        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        #if DEBUG
        NSLog("%@", "AIPOSE_PERF launch_first_paint ms=\(durationMs) endpoint_source=\(sanitized(endpointSource))")
        #endif
        guard isFirebaseConfigured else { return }
        Crashlytics.crashlytics().log("first_paint_ms=\(durationMs) endpoint_source=\(sanitized(endpointSource))")
    }

    private func logEndpointResolved(source: String, startedAt: Date) {
        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        #if DEBUG
        // Pairs with the `launch_first_paint` line: first paint happens before this one.
        NSLog("%@", "AIPOSE_PERF endpoint_finalized source=\(sanitized(source)) ms=\(durationMs)")
        #endif
        guard isFirebaseConfigured else { return }
        Analytics.logEvent("app_start", parameters: nil)
        Analytics.logEvent("endpoint_resolved", parameters: [
            "source": sanitized(source),
            "outcome": sanitized("applied"),
            "duration_ms": "\(min(durationMs, 100000))",
        ])
        Crashlytics.crashlytics().log("endpoint_source=\(sanitized(source))")
    }

    private func sanitized(_ value: String) -> String {
        if value.contains("://") || value.contains(" ") || value.count > 100 {
            return "redacted"
        }
        return value
    }

    private func showRootViewController() {
        let rootView = ContentView(
            isFirebaseConfigured: isFirebaseConfigured,
            galleryBootstrap: galleryBootstrap
        )
        let host = UIHostingController(rootView: rootView)
        if let window {
            // Endpoint changed after the first paint: swap the root in the existing window so no
            // blank frame is shown.
            window.rootViewController = host
            return
        }
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        self.window = window
    }
}

/// One-shot guard for launch endpoint finalisation. The `fetchAndActivate` callback and the 5s
/// seal timer can complete in either order, so "apply the endpoint once" needs a lock rather than
/// the unsynchronised `didResolve` local the previous version used.
private final class StartupLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var isSealed = false
    private var isFinalized = false

    /// True while the fetch is still allowed to change the endpoint.
    func admitFetch() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !isSealed && !isFinalized
    }

    func seal() {
        lock.lock()
        isSealed = true
        lock.unlock()
    }

    /// True for exactly one caller per launch, so the launch analytics event is logged once.
    func claimFinalization() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if isFinalized { return false }
        isFinalized = true
        return true
    }
}

private enum StartupEndpoint {
    static let defaultURL = "https://pose-extract-server-production.up.railway.app"
    static let remoteConfigKey = "api_baseurl"

    static func validate(raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        guard let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return nil
        }
        if raw.contains(" ") || raw.count > 2048 { return nil }
        return raw
    }

    static func resolve(defaultUrl: String, cachedRaw: String?, fetchedRaw: String?) -> String {
        if let fetched = validate(raw: fetchedRaw) { return fetched }
        if let cached = validate(raw: cachedRaw) { return cached }
        return defaultUrl
    }
}
