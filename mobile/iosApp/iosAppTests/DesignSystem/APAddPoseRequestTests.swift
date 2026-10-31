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
