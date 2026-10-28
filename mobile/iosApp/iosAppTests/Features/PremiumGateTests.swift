import XCTest
@testable import iosApp

/// The capture gate is the whole product decision of FEAT-011 M1, so it is proved as a table here:
/// no camera, no store, no session, no simulator.
///
/// The two contracts that matter are *order* and *fail-open*: the paywall may only be decided for a
/// confirmed, signed-in, unentitled Account, it must be decided before camera readiness, and every
/// unknown/outage state must let the press through exactly as it did before the gate existed.
@MainActor
final class PremiumGateTests: XCTestCase {
    private func decide(
        paywallEnabled: Bool = true,
        purchasesConfigured: Bool = true,
        accountsAvailable: Bool = true,
        purchasesLinked: Bool = true,
        entitlement: PurchaseGatewayState = .notEntitled,
        signedIn: Bool = true,
        cameraReady: Bool = true
    ) -> CaptureGateOutcome {
        PremiumGate.captureOutcome(
            PremiumGateInputs(
                paywallEnabled: paywallEnabled,
                purchasesConfigured: purchasesConfigured,
                accountsAvailable: accountsAvailable,
                purchasesLinked: purchasesLinked,
                entitlement: entitlement,
                signedIn: signedIn
            ),
            cameraReady: cameraReady
        )
    }

    // MARK: - G1 kill switch

    /// Flag off → exactly today's behaviour, even for a user who is not entitled.
    func testG1KillSwitchOffKeepsTheCapturePathUnchanged() {
        XCTAssertEqual(decide(paywallEnabled: false, entitlement: .notEntitled), .capture)
        XCTAssertEqual(decide(paywallEnabled: false, entitlement: .expired), .capture)
        XCTAssertEqual(decide(paywallEnabled: false, entitlement: .notEntitled, signedIn: false), .capture)
    }

    /// An unready camera still "does nothing" when the gate allows the press — that half of today's
    /// behaviour is preserved, so moving the gate ahead of readiness did not change the camera.
    func testG1KillSwitchOffWithAnUnreadyCameraDoesNothing() {
        XCTAssertEqual(
            decide(paywallEnabled: false, entitlement: .notEntitled, cameraReady: false),
            .unchanged
        )
    }

    // MARK: - G3 a build that cannot sell, or accounts that are off

    func testG3UnconfiguredPurchasesAllowCapture() {
        XCTAssertEqual(decide(purchasesConfigured: false), .capture)
        XCTAssertEqual(decide(purchasesConfigured: false, signedIn: false), .capture)
    }

    func testG3AccountsUnavailableAllowCapture() {
        XCTAssertEqual(decide(accountsAvailable: false), .capture)
        XCTAssertEqual(decide(accountsAvailable: false, signedIn: false), .capture)
    }

    /// G1 is decided before G3, so flipping the kill switch back is a complete rollback: a build that
    /// also cannot sell still behaves like today.
    func testG1IsDecidedBeforeG3() {
        XCTAssertEqual(
            decide(paywallEnabled: false, purchasesConfigured: false, accountsAvailable: false),
            .capture
        )
    }

    // MARK: - G4 signed out

    /// A signed-out user gets the paywall with its sign-in prompt (M2: no guest purchase), whatever
    /// the stale snapshot says.
    func testG4SignedOutAsksForSignIn() {
        XCTAssertEqual(decide(entitlement: .notEntitled, signedIn: false), .paywall(signIn: true))
        XCTAssertEqual(decide(entitlement: .signInRequired, signedIn: false), .paywall(signIn: true))
        XCTAssertEqual(decide(entitlement: .entitled, signedIn: false), .paywall(signIn: true))
    }

    // MARK: - G5 access

    func testG5EntitledAndSignedInUserCaptures() {
        XCTAssertEqual(decide(entitlement: .entitled, signedIn: true), .capture)
    }

    // MARK: - G6 the provider context is not confirmed yet

    /// A failed (or still running) cold-start link leaves `linkedAccountID == nil` with a snapshot the
    /// adapter cannot vouch for. That is an outage, not a "no": the subscriber must still be able to
    /// take the photo.
    func testG6UnlinkedProviderContextFailsOpen() {
        XCTAssertEqual(
            decide(purchasesLinked: false, entitlement: .notEntitled),
            .capture
        )
        XCTAssertEqual(
            decide(purchasesLinked: false, entitlement: .loading),
            .capture
        )
    }

    // MARK: - G7 only a confirmed answer may gate

    /// Every state that is not a successful entitlement fetch for the linked Account fails open:
    /// booting, a failed price list, the outcomes of a purchase attempt, and a build that cannot sell.
    func testG7UnknownAndTransientStatesFailOpen() {
        let unknown: [PurchaseGatewayState] = [
            .loading, .noOffering, .purchasePending, .purchaseCancelled, .purchaseFailed,
            .signInRequired, .unconfigured
        ]
        for state in unknown {
            XCTAssertEqual(decide(entitlement: state), .capture, "\(state) must not lock the camera")
        }
    }

    /// The one case that may gate: a successful fetch said this Account has no access.
    func testG7ConfirmedNotEntitledStatesAskForThePaywall() {
        let confirmed: [PurchaseGatewayState] = [.notEntitled, .billingRetry, .expired, .revoked]
        for state in confirmed {
            XCTAssertEqual(decide(entitlement: state), .paywall(signIn: false), "\(state)")
        }
    }

    func testConfirmedNotEntitledClassification() {
        XCTAssertTrue(PremiumGate.isConfirmedNotEntitled(.notEntitled))
        XCTAssertTrue(PremiumGate.isConfirmedNotEntitled(.billingRetry))
        XCTAssertTrue(PremiumGate.isConfirmedNotEntitled(.expired))
        XCTAssertTrue(PremiumGate.isConfirmedNotEntitled(.revoked))
        for state: PurchaseGatewayState in [
            .loading, .unconfigured, .noOffering, .entitled, .purchasePending,
            .purchaseCancelled, .purchaseFailed, .signInRequired
        ] {
            XCTAssertFalse(PremiumGate.isConfirmedNotEntitled(state), "\(state) is not a confirmed no")
        }
    }

    // MARK: - The ordering requirement

    /// The reason the gate is a separate decision instead of a guard after readiness: an unentitled
    /// press must reach the paywall even when the camera is not ready (a simulator has no capture
    /// device at all), so it can never be answered by the readiness/`captureError` path first.
    func testPaywallIsDecidedBeforeCameraReadiness() {
        XCTAssertEqual(
            decide(entitlement: .notEntitled, cameraReady: false),
            .paywall(signIn: false)
        )
        XCTAssertEqual(
            decide(entitlement: .expired, cameraReady: false),
            .paywall(signIn: false)
        )
        XCTAssertEqual(
            decide(entitlement: .notEntitled, signedIn: false, cameraReady: false),
            .paywall(signIn: true)
        )
    }

    /// The fail-open states keep today's "an unready camera does nothing" behaviour.
    func testOutageStatesWithAnUnreadyCameraDoNothing() {
        XCTAssertEqual(decide(entitlement: .loading, cameraReady: false), .unchanged)
        XCTAssertEqual(decide(purchasesLinked: false, entitlement: .notEntitled, cameraReady: false), .unchanged)
    }

    // MARK: - Shutter control state (P1-a)

    /// The button has to be pressable for a paywall answer even when the camera is not ready;
    /// otherwise the paywall is unreachable exactly where QA needs to reach it.
    func testShutterAcceptsThePressForAPaywallEvenWhenTheCameraIsNotReady() {
        XCTAssertTrue(
            PremiumGate.shutterAcceptsPress(outcome: .paywall(signIn: false), isBusy: false),
            "a gated press belongs to the gate, not to camera readiness"
        )
        XCTAssertTrue(PremiumGate.shutterAcceptsPress(outcome: .paywall(signIn: true), isBusy: false))
    }

    func testShutterKeepsTodaysRuleForTheOutcomesThatWouldCapture() {
        XCTAssertTrue(PremiumGate.shutterAcceptsPress(outcome: .capture, isBusy: false))
        XCTAssertFalse(PremiumGate.shutterAcceptsPress(outcome: .unchanged, isBusy: false))
    }

    func testShutterIsDisabledWhileACaptureIsInFlight() {
        XCTAssertFalse(PremiumGate.shutterAcceptsPress(outcome: .capture, isBusy: true))
        XCTAssertFalse(PremiumGate.shutterAcceptsPress(outcome: .paywall(signIn: false), isBusy: true))
    }

    // MARK: - Paywall presentation (P2)

    func testASecondShutterPressDoesNotStackASecondSheet() {
        var presentation = PaywallPresentation()
        presentation.send(.shutterRequested)
        presentation.send(.shutterRequested)

        XCTAssertTrue(presentation.isPresented)
        XCTAssertEqual(presentation.automaticDismissals, 0)
    }

    /// A confirmed entitlement closes the sheet once and grants nothing else: no second dismissal when
    /// later pushes repeat the same state, and no capture fired on the user's behalf.
    func testConfirmedEntitlementDismissesTheSheetExactlyOnce() {
        var presentation = PaywallPresentation()
        presentation.send(.shutterRequested)

        presentation.send(.gateSettled(entitlement: .entitled, signedIn: true))
        XCTAssertFalse(presentation.isPresented)
        XCTAssertEqual(presentation.automaticDismissals, 1)

        presentation.send(.gateSettled(entitlement: .entitled, signedIn: true))
        XCTAssertEqual(presentation.automaticDismissals, 1, "a repeated push is not a second dismissal")
    }

    /// Entitlement seen without a signed-in Account, or a snapshot that is merely entitled-and-not yet
    /// confirmed by the session, must not close the sheet.
    func testEntitlementWithoutASessionDoesNotCloseTheSheet() {
        var presentation = PaywallPresentation()
        presentation.send(.shutterRequested)
        presentation.send(.gateSettled(entitlement: .entitled, signedIn: false))

        XCTAssertTrue(presentation.isPresented)
        XCTAssertEqual(presentation.automaticDismissals, 0)
    }

    /// After a dismissal the camera is usable again: the next gated press re-opens the sheet.
    func testTheCameraStaysUsableAfterDismissal() {
        var presentation = PaywallPresentation()
        presentation.send(.shutterRequested)
        presentation.send(.gateSettled(entitlement: .notEntitled, signedIn: true))
        XCTAssertTrue(presentation.isPresented, "an unconfirmed/denied state leaves the sheet up")

        presentation.send(.userDismissed)
        XCTAssertFalse(presentation.isPresented)

        presentation.send(.shutterRequested)
        XCTAssertTrue(presentation.isPresented, "the next gated press still reaches the paywall")
    }

    /// A dismissal the user performs is not an automatic one, and settling the gate while nothing is
    /// presented never counts as a dismissal.
    func testNoPhantomDismissals() {
        var presentation = PaywallPresentation()
        presentation.send(.gateSettled(entitlement: .entitled, signedIn: true))
        XCTAssertEqual(presentation.automaticDismissals, 0)

        presentation.send(.shutterRequested)
        presentation.send(.userDismissed)
        presentation.send(.gateSettled(entitlement: .entitled, signedIn: true))
        XCTAssertEqual(presentation.automaticDismissals, 0)
    }
}
