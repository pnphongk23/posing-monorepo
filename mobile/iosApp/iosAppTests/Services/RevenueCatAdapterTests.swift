import XCTest
@testable import iosApp

@MainActor
final class RevenueCatAdapterTests: XCTestCase {
    func testUnconfiguredLoadOfferingFailsClosed() async {
        let adapter = RevenueCatAdapter.shared
        // Dev xcconfig uses REPLACE_WITH_DEV_PUBLIC_SDK_KEY — configureFromEnvironment must no-op.
        adapter.configureFromEnvironment()
        if adapter.isConfigured {
            // Real key present in local env; skip strict unconfigured assertion.
            return
        }
        let snapshot = await adapter.loadOffering()
        XCTAssertEqual(snapshot.state, .unconfigured)
        XCTAssertTrue(snapshot.products.isEmpty)
    }

    func testInvalidProductPurchaseFailsClosed() async {
        let adapter = RevenueCatAdapter.shared
        guard adapter.isConfigured else {
            let snapshot = await adapter.purchase(productId: "premium_yearly")
            XCTAssertEqual(snapshot.state, .unconfigured)
            return
        }
        let snapshot = await adapter.purchase(productId: "invalid_product")
        XCTAssertEqual(snapshot.state, .purchaseFailed)
        XCTAssertEqual(snapshot.errorCode, "invalid_product")
    }

    func testRestoreUnconfiguredFailsClosed() async {
        let adapter = RevenueCatAdapter.shared
        guard !adapter.isConfigured else { return }
        let snapshot = await adapter.restore()
        XCTAssertEqual(snapshot.state, .unconfigured)
    }
}

extension RevenueCatAdapterTests {
    /// `linkAccount` must never invent a provider identity while the SDK is unconfigured, and it
    /// must be idempotent so repeated session events cannot re-link the same Account forever.
    func testLinkAccountIsInertWhileUnconfiguredAndIdempotent() async {
        let adapter = RevenueCatAdapter.shared
        guard !adapter.isConfigured else { return }

        await adapter.linkAccount("account-a")
        XCTAssertNil(adapter.linkedAccountID)
        await adapter.linkAccount("account-a")
        XCTAssertNil(adapter.linkedAccountID)
    }

    /// Sign-out must drop the local provider context (`FEAT-011` E4) even without a provider call.
    func testClearAccountDropsLocalProviderContext() async {
        let adapter = RevenueCatAdapter.shared
        guard !adapter.isConfigured else { return }

        await adapter.clearAccount()
        XCTAssertNil(adapter.linkedAccountID)
        XCTAssertEqual(adapter.snapshot.state, .unconfigured)
        XCTAssertFalse(adapter.snapshot.state == .entitled)
    }

    func testSnapshotMirrorsPublishedState() {
        let adapter = RevenueCatAdapter.shared
        XCTAssertEqual(adapter.snapshot, adapter.lastSnapshot)
    }
}
