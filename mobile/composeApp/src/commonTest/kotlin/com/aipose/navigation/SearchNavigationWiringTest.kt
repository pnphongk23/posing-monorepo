package com.aipose.navigation

import cafe.adriel.voyager.core.screen.Screen
import com.aipose.ui.screens.poses.POSES_SEARCH_BUTTON_TEST_TAG
import com.aipose.ui.screens.poses.SearchScreen
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
}
