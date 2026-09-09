package com.aipose.navigation

import com.aipose.auth.SignInIntent
import com.aipose.settings.SettingsDestinationResult
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class SettingsNavigationWiringTest {

    @Test
    fun `account sign-in success dismisses prompt before reloading`() {
        var dismissals = 0
        var reloads = 0

        handleAccountSignInSuccess(
            intent = SignInIntent.OPEN_ACCOUNT,
            dismissPrompt = { dismissals++ },
            reloadAccount = { reloads++ },
        )

        assertEquals(1, dismissals)
        assertEquals(1, reloads)
    }

    @Test
    fun `saved sign-in success dismisses prompt and resumes saved`() {
        var dismissals = 0
        var opens = 0

        handleSavedSignInSuccess(
            intent = SignInIntent.OPEN_SAVED,
            dismissPrompt = { dismissals++ },
            openSaved = { opens++ },
        )

        assertEquals(1, dismissals)
        assertEquals(1, opens)
    }

    @Test
    fun `reverse settings push is exactly once until it returns`() {
        val gate = SettingsNavigationGate()
        var pushes = 0

        assertTrue(gate.tryOpen { pushes++ })
        assertFalse(gate.tryOpen { pushes++ })
        assertEquals(1, pushes)

        gate.reset()
        assertTrue(gate.tryOpen { pushes++ })
        assertEquals(2, pushes)
    }

    @Test
    fun `premium settings action pushes paywall and returns opened`() {
        var pushes = 0
        val action = createPremiumPaywallNavigationAction { pushes++ }

        assertEquals(SettingsDestinationResult.Opened, action())
        assertEquals(1, pushes)
    }
}
