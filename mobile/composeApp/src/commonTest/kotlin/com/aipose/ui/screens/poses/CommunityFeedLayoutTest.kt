package com.aipose.ui.screens.poses

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Focused, platform-agnostic tests for the Community masonry feed layout policy:
 * the deck of card aspect ratios that drive uneven column heights in the two-column
 * [LazyVerticalStaggeredGrid], and the small/calm/low-contrast item loading indicator.
 */
class CommunityFeedLayoutTest {

    // ---- masonry ratio policy ---------------------------------------------

    @Test
    fun aspectRatioCyclesThroughTallSquareShortDeterministically() {
        assertEquals(1f / 1.25f, communityCardAspectRatio(0))
        assertEquals(1f, communityCardAspectRatio(1))
        assertEquals(1.25f / 1f, communityCardAspectRatio(2))
        // Deterministic cycle for later indexes.
        assertEquals(1f / 1.25f, communityCardAspectRatio(3))
        assertEquals(1f, communityCardAspectRatio(4))
        assertEquals(1.25f / 1f, communityCardAspectRatio(5))
    }

    @Test
    fun aspectRatioNeverForcesEqualHeights() {
        // A true masonry feed must not collapse every card to a square (that would
        // force equal aspect ratios just to hide gaps). The deck spans a meaningful
        // height range (tall 0.8 .. short 1.25) — not one flat value.
        val distinct = (0 until 12).map { communityCardAspectRatio(it) }.toSet()
        assertTrue(distinct.size >= 3, "expected ≥3 distinct masonry ratios, got $distinct")
        distinct.forEach { ratio ->
            assertTrue(ratio in 0.75f..1.35f, "ratio $ratio out of masonry range")
        }
    }

    // ---- item loading indicator -------------------------------------------

    @Test
    fun loadingIndicatorIsSmallAndThin() {
        // Replaces the old heavy 28dp indicator: small (16dp) and a thin stroke.
        assertEquals(16, COMMUNITY_LOADING_SIZE)
        assertTrue(COMMUNITY_LOADING_SIZE < 28, "loading must be smaller than the old 28dp")
        assertTrue(COMMUNITY_LOADING_STROKE <= 2f, "loading stroke must be thin")
    }

    @Test
    fun loadingIndicatorIsCalmAndLowContrast() {
        // Muted/low-contrast tone (never a full-contrast diagnostic red): alpha held
        // well below opaque so it reads as a calm placeholder, not an error.
        assertTrue(COMMUNITY_LOADING_ALPHA > 0f)
        assertTrue(COMMUNITY_LOADING_ALPHA <= 0.8f, "alpha must stay low-contrast")
    }
}
