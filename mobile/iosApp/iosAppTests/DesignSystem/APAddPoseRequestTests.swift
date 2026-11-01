import SwiftUI
import XCTest
@testable import iosApp

/// The Gallery header's `+` runs the Add pose flow on the Poses tab, but the Poses tab — and with it
/// the `onChange(of: addPoseRequest)` that opens the flow — is rebuilt when the tab changes. A signal
/// raised before the switch would arrive as the rebuilt screen's initial value, and an initial value
/// never fires `onChange`, so the request is latched and delivered once the screen is on screen.
final class APAddPoseRequestTests: XCTestCase {
    func testNothingIsDeliveredBeforeTheGalleryAsks() {
        var request = APAddPoseRequest()
        XCTAssertEqual(request.signal, 0)
        XCTAssertFalse(request.deliver(), "appearing with no request must not fire the signal")
        XCTAssertEqual(request.signal, 0)
    }

    func testARequestIsDeliveredExactlyOnce() {
        var request = APAddPoseRequest()
        request.ask()
        XCTAssertTrue(request.isPending)

        XCTAssertTrue(request.deliver(), "the Poses tab took the request")
        XCTAssertEqual(request.signal, 1)
        XCTAssertFalse(request.isPending, "a delivered request is not left pending")

        XCTAssertFalse(request.deliver(), "a second appearance must not open Add pose again")
        XCTAssertEqual(request.signal, 1)
    }

    func testASecondRequestFromTheGalleryIsANewSignalValue() {
        var request = APAddPoseRequest()
        request.ask()
        XCTAssertTrue(request.deliver())
        request.ask()
        XCTAssertTrue(request.deliver())
        XCTAssertEqual(request.signal, 2, "the screen watches the value, so a repeat request must change it")
    }

    @MainActor func testTheRebuiltScreenSeesTheSignalChangeAfterItAppears() async {
        // The claim behind the latch, tested against the modifier production uses: a screen built with
        // the pre-switch value still observes the delivery, because it lands after the screen appears.
        let recorded = RecordedRequest()
        let pending = {
            var request = APAddPoseRequest()
            request.ask()
            return request
        }()

        let probe = APViewProbe(
            APAddPoseDeliveryRig(request: pending) { recorded.value = $0 },
            size: CGSize(width: 320, height: 240)
        )
        defer { probe.tearDown() }
        for _ in 0..<40 {
            await Task.yield()
            if recorded.value != nil { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        guard let delivered = recorded.value else {
            return XCTFail("the screen must observe the request delivered on its appearance")
        }
        XCTAssertEqual(delivered.signal, 1, "the delivered signal is a change from the value it was built with")
        XCTAssertFalse(delivered.isPending)
    }
}

private final class RecordedRequest {
    var value: APAddPoseRequest?
}

/// A stand-in for the Poses tab: it watches the signal exactly like `PosesScreen` does and reports the
/// values it sees, while the production modifier delivers the latched request on appearance.
private struct APAddPoseDeliveryRig: View {
    @State private var request: APAddPoseRequest
    let onChange: (APAddPoseRequest) -> Void

    init(request: APAddPoseRequest, onChange: @escaping (APAddPoseRequest) -> Void) {
        _request = State(initialValue: request)
        self.onChange = onChange
    }

    var body: some View {
        Text("Poses")
            .onChange(of: request) { onChange($0) }
            .modifier(APAddPoseDelivery(request: $request))
    }
}

/// The Gallery `+` and the Gallery detail's Add pose both land in `PosesScreen` at an instant when the
/// screen — and with it the `SessionPresenceModel` it reads the session from — has just been rebuilt,
/// so the session has not been read back from storage yet. These pin the answer for each state,
/// including the unread one: a signed-in user must not be shown the sign-in prompt.
final class APAddPoseGateTests: XCTestCase {
    func testSignedInSessionOpensTheAddPoseFlow() {
        var gate = APAddPoseGate()
        XCTAssertEqual(gate.request(isResolved: true, isSignedIn: true), .open)
        XCTAssertFalse(gate.isHolding, "a known session is answered immediately")
    }

    func testSignedOutSessionAsksTheUserToSignIn() {
        var gate = APAddPoseGate()
        XCTAssertEqual(gate.request(isResolved: true, isSignedIn: false), .askSignIn)
        XCTAssertFalse(gate.isHolding)
    }

    func testARequestBeforeTheSessionIsReadIsHeldInsteadOfAnswered() {
        var gate = APAddPoseGate()
        XCTAssertEqual(
            gate.request(isResolved: false, isSignedIn: false),
            .waitForSession,
            "the sign-in prompt must not appear before the session has been read"
        )
        XCTAssertTrue(gate.isHolding, "the request waits for the read instead of being dropped")
    }

    func testAHeldRequestOpensTheFlowWhenTheReadSessionIsSignedIn() {
        var gate = APAddPoseGate()
        XCTAssertEqual(gate.request(isResolved: false, isSignedIn: false), .waitForSession)
        XCTAssertEqual(gate.sessionRead(isSignedIn: true), .open)
        XCTAssertFalse(gate.isHolding)
        XCTAssertNil(gate.sessionRead(isSignedIn: true), "a held request is answered exactly once")
    }

    func testAHeldRequestAsksToSignInWhenTheReadSessionIsSignedOut() {
        var gate = APAddPoseGate()
        XCTAssertEqual(gate.request(isResolved: false, isSignedIn: false), .waitForSession)
        XCTAssertEqual(gate.sessionRead(isSignedIn: false), .askSignIn)
        XCTAssertNil(gate.sessionRead(isSignedIn: false))
    }

    func testNothingIsAnsweredWithoutAHeldRequest() {
        var gate = APAddPoseGate()
        XCTAssertNil(gate.sessionRead(isSignedIn: true))
        XCTAssertNil(gate.sessionRead(isSignedIn: false))
    }

    /// The reported bug, end to end over the real session seam: credentials are in storage, the screen
    /// that asks has not read them yet, and the answer must still be the Add pose flow.
    @MainActor func testAStoredSessionIsNotTreatedAsSignedOutBeforeTheFirstRead() async {
        let model = SessionPresenceModel(
            boundary: SessionBoundary(tokenStorage: AddPoseGateTokenStorage(credentials: addPoseGateCredentials))
        )
        var gate = APAddPoseGate()
        XCTAssertEqual(gate.request(isResolved: model.isResolved, isSignedIn: model.isSignedIn), .waitForSession)

        model.start()
        await addPoseGateWaitUntil("resolved") { model.isResolved }
        XCTAssertEqual(gate.sessionRead(isSignedIn: model.isSignedIn), .open)
    }

    @MainActor func testAnEmptySessionAsksToSignInOnlyAfterTheRead() async {
        let model = SessionPresenceModel(boundary: SessionBoundary(tokenStorage: AddPoseGateTokenStorage()))
        var gate = APAddPoseGate()
        XCTAssertEqual(gate.request(isResolved: model.isResolved, isSignedIn: model.isSignedIn), .waitForSession)

        model.start()
        await addPoseGateWaitUntil("resolved") { model.isResolved }
        XCTAssertEqual(gate.sessionRead(isSignedIn: model.isSignedIn), .askSignIn)
    }

    @MainActor
    private func addPoseGateWaitUntil(
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

private let addPoseGateCredentials = SessionCredentials(accessToken: "access", refreshToken: "refresh")

private final class AddPoseGateTokenStorage: TokenStoring, @unchecked Sendable {
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
