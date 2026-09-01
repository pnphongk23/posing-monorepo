package com.aipose.purchases

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest

class PurchaseCoreTest {
    @Test
    fun `only confirmed entitlement grants the three paid capabilities`() = runTest {
        val gateway = FakePurchaseGateway()
        gateway.nextPurchaseState = PurchaseState.PURCHASE_PENDING
        gateway.loadOffering()
        assertFalse(gateway.snapshot.value.canUse(PurchaseCapability.TRY_POSE))
        gateway.purchase("premium_annual")
        assertFalse(gateway.snapshot.value.hasConfirmedPremium)

        gateway.nextPurchaseState = PurchaseState.ENTITLED
        gateway.purchase("premium_annual")
        assertTrue(gateway.snapshot.value.canUse(PurchaseCapability.TRY_POSE))
        assertTrue(gateway.snapshot.value.canUse(PurchaseCapability.CAMERA_CAPTURE))
        assertTrue(gateway.snapshot.value.canUse(PurchaseCapability.GALLERY_SAVE_SHARE))
    }

    @Test
    fun `offering has one default and annual is highlighted`() = runTest {
        val gateway = FakePurchaseGateway()
        val loaded = gateway.loadOffering()
        assertTrue(gateway.loadCount == 1)
        assertTrue(loaded.state == PurchaseState.READY)
        assertTrue(loaded.offering?.identifier == PurchaseConfiguration.DEFAULT_OFFERING)
        assertTrue(loaded.offering?.products?.map { it.identifier } == listOf("premium_monthly", "premium_annual"))
        assertTrue(PurchaseConfiguration.PRODUCT_IDS.toSet() == setOf("premium_annual", "premium_monthly"))
        assertTrue(loaded.offering?.products?.single { it.identifier == "premium_annual" }?.isAnnualHighlight == true)
        gateway.restore()
        assertTrue(gateway.restoreCount == 1)
        gateway.purchase("not_a_store_product")
        assertFalse(gateway.snapshot.value.hasConfirmedPremium)
    }

    @Test
    fun `cancel expiry retry grace revocation and no offering never grant access`() = runTest {
        val gateway = FakePurchaseGateway()
        for (state in listOf(
            PurchaseState.PURCHASE_CANCELLED,
            PurchaseState.PURCHASE_FAILED,
            PurchaseState.EXPIRED,
            PurchaseState.BILLING_RETRY,
            PurchaseState.GRACE_PERIOD,
            PurchaseState.REVOKED,
        )) {
            gateway.nextPurchaseState = state
            gateway.purchase("premium_monthly")
            assertFalse(gateway.snapshot.value.hasConfirmedPremium)
        }
        val unavailable = FakePurchaseGateway(offering = null)
        assertTrue(unavailable.loadOffering().state == PurchaseState.NO_OFFERING)
        assertFalse(unavailable.snapshot.value.hasConfirmedPremium)
    }
}
