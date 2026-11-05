import UIKit
import SwiftUI
import FirebaseCore
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
        // The paywall must not paint "Price unavailable" for a price that is already on its way, so the
        // store's offering is read once here — kicked, never awaited: launch does not wait on the store.
        // Gated by the paywall kill switch: a build that cannot show the paywall must not ask for prices.
        if AppConfig.shared.isPaywallEnabled {
            OfferingPrefetcher.shared.prefetch(using: RevenueCatAdapter.shared)
        }
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
        let start = Date()

        // First paint uses the last successfully fetched config when present, without waiting
        // for Firestore or network. Compile-time defaults apply before the first successful fetch.
        let configStore = UserDefaultsConfigPayloadStore()
        let initialPayload = AppConfigService.resolveInitialPayload(store: configStore)
        AppConfigService.apply(initialPayload)
        showRootViewController()
        logFirstPaint(startedAt: start, endpointSource: "cache-or-default")

        guard isFirebaseConfigured else {
            logEndpointResolved(source: "default", startedAt: start)
            return
        }

        let latch = StartupLatch()

        // Keeps the historical 5s budget for changing the base URL: after it, a late fetch can no
        // longer re-point the app under an interaction that already started.
        let timeout = DispatchWorkItem { [weak self] in
            latch.seal()
            guard latch.claimFinalization() else { return }
            self?.logEndpointResolved(source: "default", startedAt: start)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: timeout)

        Task { [weak self] in
            let result = await AppConfigService.fetchAndResolve(source: FirestoreConfigSource())
            timeout.cancel()
            guard result.outcome == .applied else {
                latch.sealAndAdmitFetch()
                guard latch.claimFinalization() else { return }
                await MainActor.run {
                    self?.logEndpointResolved(source: "cache-or-default", startedAt: start)
                }
                return
            }
            AppConfigService.persistIfSuccessful(result.payload, outcome: result.outcome, store: configStore)
            let mayApplyEndpointAndAccount = latch.sealAndAdmitFetch()
            let decision = AppConfigService.applicationDecision(
                isEndpointWindowSealed: !mayApplyEndpointAndAccount
            )

            let fetchedPayload = result.payload
            let applied = AppConfigService.applyFetched(fetchedPayload, decision: decision)

            if applied.endpointChanged {
                #if DEBUG
                NSLog("%@", "AIPOSE_PERF endpoint_swapped source=fetch")
                #endif
            }

            await MainActor.run {
                if applied.rebuildRoot {
                    self?.showRootViewController()
                }
            }

            guard latch.claimFinalization() else { return }
            let source = result.payload.endpointUrl == AppConfigService.defaultURL ? "default" : "fetch"
            await MainActor.run {
                self?.logEndpointResolved(source: source, startedAt: start)
            }
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

/// One-shot guard for launch endpoint finalisation. The fetch callback and the 5s
/// seal timer can complete in either order, so "apply the endpoint once" needs a lock rather than
/// an unsynchronised local.
private final class StartupLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var isSealed = false
    private var isFinalized = false

    /// Atomically seals an in-budget fetch or rejects a fetch after the deadline.
    func sealAndAdmitFetch() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isSealed && !isFinalized else { return false }
        isSealed = true
        return true
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
