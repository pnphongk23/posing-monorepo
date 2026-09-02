package com.aipose.purchases

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class PremiumTestBypassTest {
    private val devDebug = AppEnvironmentDescriptor(AppEnvironmentName.DEV, "Debug", isDebug = true)
    private val devRelease = AppEnvironmentDescriptor(AppEnvironmentName.DEV, "Release", isDebug = false)
    private val prodDebug = AppEnvironmentDescriptor(AppEnvironmentName.PROD, "Debug", isDebug = true)

    @Test
    fun `bypass requires debug dev and enabled runtime flag`() {
        assertTrue(isPremiumBypassAllowed(devDebug, "1"))
        assertFalse(isPremiumBypassAllowed(devDebug, null))
        assertFalse(isPremiumBypassAllowed(devDebug, "0"))
    }

    @Test
    fun `release dev cannot bypass`() {
        assertFalse(isPremiumBypassAllowed(devRelease, "1"))
    }

    @Test
    fun `prod stays gated even in debug with runtime flag`() {
        assertFalse(isPremiumBypassAllowed(prodDebug, "1"))
    }
}
