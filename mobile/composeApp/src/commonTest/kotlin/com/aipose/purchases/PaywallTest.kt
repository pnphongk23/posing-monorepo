package com.aipose.purchases

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class PaywallTest {
    @Test
    fun `all approved triggers show one gate without confirmed entitlement`() {
        PaidAccessTrigger.entries.forEach { trigger ->
            val decision = decidePaidAccess(trigger, PurchaseSnapshot(state = PurchaseState.NOT_ENTITLED))
            assertTrue(decision.showPaywall, trigger.name)
            assertFalse(decision.allowAction, trigger.name)
        }
    }

    @Test
    fun `only confirmed premium allows approved capabilities`() {
        val decision = decidePaidAccess(PurchaseSnapshot(state = PurchaseState.ENTITLED))
        assertFalse(decision.showPaywall)
        assertTrue(decision.allowAction)
    }

    @Test
    fun `failure cancellation pending and unavailable never allow`() {
        listOf(PurchaseState.PURCHASE_FAILED, PurchaseState.PURCHASE_CANCELLED, PurchaseState.PURCHASE_PENDING, PurchaseState.NO_OFFERING, PurchaseState.EXPIRED, PurchaseState.REVOKED).forEach { state ->
            assertFalse(decidePaidAccess(PurchaseSnapshot(state = state)).allowAction)
        }
    }
}
