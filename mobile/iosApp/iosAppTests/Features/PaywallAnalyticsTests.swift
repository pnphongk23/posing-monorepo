import Combine
import XCTest
@testable import iosApp

/// The five paywall funnel events, through the same closure seam the RevenueCat adapter uses.
/// Every assertion is "fires once, with exactly these parameters": a duplicated event inflates the
/// funnel, and a payload carrying an identifier is a privacy defect, so both are pinned here.
@MainActor
final class PaywallAnalyticsTests: XCTestCase {
    // MARK: - Recording seam

    /// Main-actor recorder, because the model emits from the main actor and the assertions read it.
    @MainActor
    private final class Recorder {
        private(set) var events: [(name: String, parameters: [String: String])] = []

        var sink: PaywallAnalyticsSink {
            { [weak self] name, parameters in
                self?.events.append((name, parameters))
            }
        }

        func named(_ name: String) -> [(name: String, parameters: [String: String])] {
            events.filter { $0.name == name }
        }

        func only(_ name: String) -> [String: String]? {
            let matches = named(name)
            XCTAssertEqual(matches.count, 1, "\(name) must fire exactly once per occurrence")
            return matches.first?.parameters
        }
    }

    @MainActor
    private final class FakeGateway: PurchaseGateway {
        private let subject: CurrentValueSubject<PurchaseSnapshot, Never>
        var snapshot: PurchaseSnapshot { subject.value }
        var snapshots: AnyPublisher<PurchaseSnapshot, Never> { subject.eraseToAnyPublisher() }

        var nextLoad: PurchaseSnapshot
        var nextPurchase: PurchaseSnapshot
        var nextRestore: PurchaseSnapshot
        private(set) var loadCount = 0
        private(set) var purchasedPackageIDs: [String] = []
        private(set) var restoreCount = 0

        init(
            snapshot: PurchaseSnapshot = PurchaseSnapshot(state: .notEntitled, products: []),
            nextLoad: PurchaseSnapshot? = nil,
            nextPurchase: PurchaseSnapshot? = nil,
            nextRestore: PurchaseSnapshot? = nil
        ) {
            self.subject = CurrentValueSubject(snapshot)
            self.nextLoad = nextLoad ?? snapshot
            self.nextPurchase = nextPurchase ?? snapshot
            self.nextRestore = nextRestore ?? snapshot
        }

        func loadOffering() async -> PurchaseSnapshot {
            loadCount += 1
            subject.send(nextLoad)
            return nextLoad
        }

        func purchase(packageID: String) async -> PurchaseSnapshot {
            purchasedPackageIDs.append(packageID)
            subject.send(nextPurchase)
            return nextPurchase
        }

        func restore() async -> PurchaseSnapshot {
            restoreCount += 1
            subject.send(nextRestore)
            return nextRestore
        }
    }

    private let annual = PurchaseProduct(
        identifier: "annual", packageType: .annual, localizedPrice: "$39.99", period: "year"
    )
    private let monthly = PurchaseProduct(
        identifier: "monthly", packageType: .monthly, localizedPrice: "$5.99", period: "month"
    )
    private var readyOffering: PurchaseSnapshot {
        PurchaseSnapshot(state: .notEntitled, products: [monthly, annual])
    }

    private let session = SessionCredentials(accessToken: "access", refreshToken: "refresh")

    private func makeModel(
        gateway: FakeGateway,
        recorder: Recorder,
        signedIn: Bool = true,
        trigger: PaywallTrigger = .shutter,
        connectivity: FakeAnalyticsConnectivity = FakeAnalyticsConnectivity(),
        signIn: @escaping SignInAction.Starter = {}
    ) -> PaywallModel {
        let storage = FakeAnalyticsTokenStorage(credentials: signedIn ? session : nil)
        let model = PaywallModel(
            gateway: gateway,
            boundary: SessionBoundary(tokenStorage: storage),
            signInAction: SignInAction(start: signIn),
            connectivity: connectivity,
            analytics: recorder.sink
        )
        model.trigger = trigger
        return model
    }

    // MARK: - paywall_view

    func testPaywallViewEmitsOncePerPresentationWithItsState() async {
        let recorder = Recorder()
        let gateway = FakeGateway(nextLoad: readyOffering)
        let model = makeModel(gateway: gateway, recorder: recorder)

        model.start()
        await waitUntil("ready") { model.phase == .ready }
        model.start()
        try? await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertEqual(
            recorder.named(PaywallEvent.view).count,
            1,
            "a re-entrant start() is the same presentation, so it must not double-count the funnel"
        )
        let parameters = recorder.only(PaywallEvent.view)
        XCTAssertEqual(parameters?["trigger"], "shutter")
        XCTAssertEqual(parameters?["signed_in"], "true")
        XCTAssertEqual(parameters?["plans_state"], "ready")

        // A second presentation is a second view event.
        let second = makeModel(gateway: FakeGateway(nextLoad: readyOffering), recorder: recorder)
        second.start()
        await waitUntil("second view") { recorder.named(PaywallEvent.view).count == 2 }
        XCTAssertEqual(recorder.named(PaywallEvent.view).count, 2)
    }

    func testSignedOutViewReportsSigninAndTheSettingsTrigger() async {
        let recorder = Recorder()
        let model = makeModel(
            gateway: FakeGateway(nextLoad: readyOffering),
            recorder: recorder,
            signedIn: false,
            trigger: .settings
        )

        model.start()
        await waitUntil("view") { recorder.named(PaywallEvent.view).count == 1 }

        let parameters = recorder.only(PaywallEvent.view)
        XCTAssertEqual(parameters?["signed_in"], "false")
        XCTAssertEqual(parameters?["trigger"], "settings", "Settings → Premium is its own trigger")
        XCTAssertEqual(parameters?["plans_state"], "signin")
    }

    func testUnavailableOfferingReportsUnavailable() async {
        let recorder = Recorder()
        let model = makeModel(
            gateway: FakeGateway(nextLoad: PurchaseSnapshot(state: .noOffering, products: [])),
            recorder: recorder
        )
        model.start()
        await waitUntil("unavailable") { recorder.named(PaywallEvent.view).count == 1 }
        XCTAssertEqual(recorder.only(PaywallEvent.view)?["plans_state"], "unavailable")
    }

    // MARK: - paywall_plan_select

    func testPlanSelectEmitsOnlyForRealPackages() async {
        let recorder = Recorder()
        let model = makeModel(gateway: FakeGateway(nextLoad: readyOffering), recorder: recorder)
        model.start()
        await waitUntil("ready") { model.phase == .ready }

        model.select("placeholder.annual")
        XCTAssertTrue(recorder.named(PaywallEvent.planSelect).isEmpty, "a placeholder row is not a plan")

        model.select(monthly.identifier)
        XCTAssertEqual(recorder.only(PaywallEvent.planSelect)?["plan"], "monthly")

        model.select(annual.identifier)
        XCTAssertEqual(recorder.named(PaywallEvent.planSelect).count, 2)
        XCTAssertEqual(recorder.named(PaywallEvent.planSelect).last?.parameters["plan"], "annual")
    }

    // MARK: - paywall_cta_tap

    func testCTATapDistinguishesSignInFromPurchase() async {
        let recorder = Recorder()
        let signedInGateway = FakeGateway(nextLoad: readyOffering)
        let signedIn = makeModel(gateway: signedInGateway, recorder: recorder)
        signedIn.start()
        await waitUntil("ready") { signedIn.phase == .ready }
        XCTAssertEqual(signedIn.tapPrimary(), .purchase)
        XCTAssertEqual(recorder.only(PaywallEvent.ctaTap)?["action"], "purchase")
        XCTAssertEqual(recorder.only(PaywallEvent.ctaTap)?["plan"], "annual")
        XCTAssertEqual(recorder.only(PaywallEvent.ctaTap)?["signed_in"], "true")

        let recorder2 = Recorder()
        let signedOutGateway = FakeGateway(nextLoad: readyOffering)
        let signedOut = makeModel(gateway: signedOutGateway, recorder: recorder2, signedIn: false)
        signedOut.start()
        await waitUntil("prices") { signedOut.selectedProductID != nil }
        XCTAssertEqual(signedOut.tapPrimary(), .signIn)
        XCTAssertEqual(recorder2.only(PaywallEvent.ctaTap)?["action"], "sign_in")
        XCTAssertTrue(
            signedOutGateway.purchasedPackageIDs.isEmpty,
            "the signed-out CTA never starts a guest purchase (the build-18 regression)"
        )
    }

    func testCTATapEmitsNothingWhenDisabled() async {
        let connectivity = FakeAnalyticsConnectivity(isOffline: true)
        let recorder = Recorder()
        let model = makeModel(
            gateway: FakeGateway(nextLoad: readyOffering),
            recorder: recorder,
            connectivity: connectivity
        )
        model.start()
        await waitUntil("view") { recorder.named(PaywallEvent.view).count == 1 }

        XCTAssertTrue(model.isOffline)
        XCTAssertFalse(model.isCTAEnabled)
        XCTAssertEqual(model.tapPrimary(), .blocked)
        XCTAssertTrue(recorder.named(PaywallEvent.ctaTap).isEmpty)
    }

    // MARK: - paywall_restore_tap

    func testRestoreTapEmitsBeforeTheGatewayAnswers() async {
        let recorder = Recorder()
        let model = makeModel(
            gateway: FakeGateway(
                nextLoad: readyOffering,
                nextRestore: PurchaseSnapshot(state: .purchaseFailed, products: [monthly, annual], failure: .network)
            ),
            recorder: recorder
        )
        model.start()
        await waitUntil("ready") { model.phase == .ready }

        await model.restore()

        XCTAssertEqual(model.phase, .purchaseFailed, "the restore itself failed")
        let parameters = recorder.only(PaywallEvent.restoreTap)
        XCTAssertEqual(parameters?["signed_in"], "true")
        XCTAssertEqual(parameters?["trigger"], "shutter", "a failed restore is still a counted tap")
    }

    // MARK: - paywall_close

    func testCloseEmitsOnceWithTheEntitledFlag() async {
        let recorder = Recorder()
        let model = makeModel(gateway: FakeGateway(nextLoad: readyOffering), recorder: recorder)
        model.start()
        await waitUntil("ready") { model.phase == .ready }

        model.noteDismissed()
        model.noteDismissed()

        let parameters = recorder.only(PaywallEvent.close)
        XCTAssertEqual(parameters?["entitled"], "false")
        XCTAssertEqual(parameters?["trigger"], "shutter")
        XCTAssertEqual(parameters?["signed_in"], "true")

        let recorder2 = Recorder()
        let buying = makeModel(
            gateway: FakeGateway(
                nextLoad: readyOffering,
                nextPurchase: PurchaseSnapshot(state: .entitled, products: [monthly, annual])
            ),
            recorder: recorder2
        )
        buying.start()
        await waitUntil("ready") { buying.phase == .ready }
        await buying.purchase()
        XCTAssertEqual(buying.phase, .entitled)
        buying.noteDismissed()
        XCTAssertEqual(recorder2.only(PaywallEvent.close)?["entitled"], "true")
    }

    // MARK: - Payload discipline

    /// No account id, email, token, price or free text may reach the analytics payload: the keys and
    /// values come from enumerated sets only.
    func testNoIdentifierInAnyEventPayload() async {
        let recorder = Recorder()
        let model = makeModel(gateway: FakeGateway(nextLoad: readyOffering), recorder: recorder, trigger: .settings)
        model.start()
        await waitUntil("ready") { model.phase == .ready }
        model.select(monthly.identifier)
        _ = model.tapPrimary()
        await model.restore()
        model.noteDismissed()

        let allowedKeys: Set<String> = ["trigger", "signed_in", "plans_state", "plan", "action", "entitled"]
        let allowedValues: Set<String> = [
            "shutter", "settings", "true", "false", "ready", "signin", "loading", "unavailable", "offline",
            "annual", "monthly", "none", "purchase", "sign_in",
        ]
        XCTAssertFalse(recorder.events.isEmpty, "the run has to emit something for this test to mean anything")
        for event in recorder.events {
            XCTAssertTrue(
                Set(event.parameters.keys).isSubset(of: allowedKeys),
                "\(event.name) carries an unexpected key: \(event.parameters.keys.sorted())"
            )
            for (key, value) in event.parameters {
                XCTAssertTrue(
                    allowedValues.contains(value),
                    "\(event.name).\(key) = \(value) is not an enumerated value"
                )
                XCTAssertFalse(value.contains("@"), "no email may appear in an analytics payload")
                XCTAssertNil(value.rangeOfCharacter(from: .decimalDigits), "no price or id digits")
            }
        }
    }

    // MARK: - Helpers

    @MainActor
    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 3,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(condition(), "Timed out waiting for \(description)", file: file, line: line)
    }
}

@MainActor
final class FakeAnalyticsConnectivity: ConnectivityReporting {
    private let subject: CurrentValueSubject<Bool, Never>
    var isOffline: Bool { subject.value }
    var changes: AnyPublisher<Bool, Never> { subject.eraseToAnyPublisher() }

    init(isOffline: Bool = false) {
        subject = CurrentValueSubject(isOffline)
    }

    func start() {}

    func set(isOffline offline: Bool) { subject.send(offline) }
}

final class FakeAnalyticsTokenStorage: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var credentials: SessionCredentials?

    init(credentials: SessionCredentials? = nil) {
        self.credentials = credentials
    }

    func saveCredentials(_ credentials: SessionCredentials) {
        lock.lock()
        self.credentials = credentials
        lock.unlock()
    }

    func loadCredentials() -> SessionCredentials? {
        lock.lock()
        defer { lock.unlock() }
        return credentials
    }

    func clearCredentials() {
        lock.lock()
        credentials = nil
        lock.unlock()
    }
}
