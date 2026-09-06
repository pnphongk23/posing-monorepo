package com.aipose.navigation

import cafe.adriel.voyager.core.screen.Screen
import com.aipose.ui.screens.poses.POSES_SEARCH_BUTTON_TEST_TAG
import com.aipose.ui.screens.poses.SearchScreen
import com.aipose.settings.SettingsDestinationResult
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** Evidence ID E-SEARCH-WIRED: search affordance retained and wired to SearchScreen. */
class SearchNavigationWiringTest {

    @Test
    fun eSearchWired_posesSearchButtonTestTagContract() {
        assertEquals("poses-search-button", POSES_SEARCH_BUTTON_TEST_TAG)
    }

    @Test
    fun eSearchWired_searchActionPushesSearchScreen() {
        val pushed = mutableListOf<Screen>()
        val onSearchClick = createSearchNavigationAction(
            pushScreen = { pushed.add(it) },
            popBack = {},
        )

        onSearchClick()

        assertEquals(1, pushed.size)
        assertTrue(pushed[0] is SearchScreen)
    }

    @Test
    fun settingsSavedDestination_gatesGuestBeforePushingSaved() {
        var opened = 0
        var signInRequests = 0
        val result = resolveSettingsSavedDestination(
            hasSession = { false },
            openSaved = { opened++; SettingsDestinationResult.Opened },
            requestSignIn = { signInRequests++ },
        )

        assertTrue(result is SettingsDestinationResult.Opened)

        assertEquals(0, opened)
        assertEquals(1, signInRequests)
    }

    @Test
    fun settingsSavedDestination_pushesOnlyWithSession() {
        var opened = 0
        var signInRequests = 0
        val result = resolveSettingsSavedDestination(
            hasSession = { true },
            openSaved = { opened++; SettingsDestinationResult.Opened },
            requestSignIn = { signInRequests++ },
        )

        assertTrue(result is SettingsDestinationResult.Opened)

        assertEquals(1, opened)
        assertEquals(0, signInRequests)
    }
}
