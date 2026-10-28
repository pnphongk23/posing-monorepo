import XCTest
@testable import iosApp

/// The capture gate is the whole product decision of FEAT-011 M1, so it is proved as a table here:
/// no camera, no store, no session, no simulator. The *order* of the rules is the contract, and the
/// tests are named after the rule they pin (G1/G3/G4/G6 in `phase-02`).
@MainActor
final class PremiumGateTests: XCTestCase {
    private func decide(
        paywallEnabled: Bool = true,
        purchasesConfigured: Bool = true,
        accountsAvailable: Bool = true,
        entitlement: PurchaseGatewayState = .notEntitled,
        signedIn: Bool = true,
        cameraReady: Bool = true
    ) -> CaptureGateOutcome {
        PremiumGate.captureOutcome(
            paywallEnabled: paywallEnabled,
            purchasesConfigured: purchasesConfigured,
            accountsAvailable: accountsAvailable,
            entitlement: entitlement,
            signedIn: signedIn,
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
    /// behaviour is preserved, so the shuffle of where the gate sits did not change the camera.
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

    // MARK: - G4 access

    func testG4EntitledAndSignedInUserCaptures() {
        XCTAssertEqual(decide(entitlement: .entitled, signedIn: true), .capture)
    }

    /// Access needs both halves: a snapshot that says `.entitled` for a context with no Account is not
    /// access (FEAT-011 NFR-001), so it must still ask for the paywall — with the sign-in prompt.
    func testG4EntitlementWithoutASessionIsNotAccess() {
        XCTAssertEqual(decide(entitlement: .entitled, signedIn: false), .paywall(signIn: true))
    }

    // MARK: - G6 everything else

    func testG6EveryUnentitledStateAsksForThePaywall() {
        let states: [PurchaseGatewayState] = [
            .notEntitled, .billingRetry, .expired, .revoked, .loading, .purchasePending,
            .purchaseCancelled, .purchaseFailed, .noOffering, .signInRequired
        ]
        for state in states {
            XCTAssertEqual(decide(entitlement: state, signedIn: true), .paywall(signIn: false), "\(state)")
        }
    }

    func testG6SignedOutUserIsAskedToSignInFirst() {
        XCTAssertEqual(decide(entitlement: .notEntitled, signedIn: false), .paywall(signIn: true))
        XCTAssertEqual(decide(entitlement: .signInRequired, signedIn: false), .paywall(signIn: true))
    }

    // MARK: - The ordering requirement

    /// The reason the gate is a separate decision instead of a guard inside `capture()`: an unentitled
    /// press must reach the paywall even when the camera is not ready (a simulator has no capture
    /// device at all), so it can never be answered by the readiness/`captureError` path first.
    func testPaywallIsDecidedBeforeCameraReadiness() {
        XCTAssertEqual(
            decide(entitlement: .notEntitled, signedIn: true, cameraReady: false),
            .paywall(signIn: false)
        )
        XCTAssertEqual(
            decide(entitlement: .loading, signedIn: true, cameraReady: false),
            .paywall(signIn: false)
        )
        XCTAssertEqual(
            decide(entitlement: .notEntitled, signedIn: false, cameraReady: false),
            .paywall(signIn: true)
        )
    }
}
