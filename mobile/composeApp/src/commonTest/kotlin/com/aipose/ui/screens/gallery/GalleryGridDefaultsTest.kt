package com.aipose.ui.screens.gallery

import androidx.compose.ui.unit.dp
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse

/**
 * WI-05 (E-GAL-UI): dense grid + dense card constants must track the
 * prototype tokens they mirror so parity regressions fail loudly.
 *
 * Prototype refs:
 * - `docs/prototype/styles/components/grid.css:213-219` `.nb-gallery-grid-dense`
 *   → `grid-template-columns: repeat(3, minmax(0, 1fr))`, `gap: 3px`.
 * - `docs/prototype/styles/components/card.css:174-189` `.nb-card--gallery-dense`
 *   → `aspect-ratio: 1 / 1`, hairline border (`--nb-border-width-hairline: 1px`),
 *   `border-radius: var(--nb-radius-small)` (6px), `box-shadow: none`, no caption
 *   chrome.
 */
class GalleryGridDefaultsTest {

    // ── Dense 3-column grid (grid.css:213-219) ─────────────────────────────

    @Test
    fun denseGridUsesThreeColumns() {
        assertEquals(3, GalleryGridDefaults.DENSE_COLUMN_COUNT)
    }

    @Test
    fun denseGridGapIsThreePixels() {
        assertEquals(3.dp, GalleryGridDefaults.DENSE_GAP)
    }

    // ── Dense card (card.css:174-189) ──────────────────────────────────────

    @Test
    fun denseCardIsSquare() {
        assertEquals(1f, DensePhotoCardDefaults.ASPECT_RATIO)
    }

    @Test
    fun denseCardUsesHairlineBorderWidth() {
        // --nb-border-width-hairline: 1px
        assertEquals(1.dp, DensePhotoCardDefaults.BORDER_WIDTH)
    }

    @Test
    fun denseCardUsesSmallRadius() {
        // --nb-radius-small: 6px
        assertEquals(6.dp, DensePhotoCardDefaults.BORDER_RADIUS)
    }

    @Test
    fun denseCardHasNoShadow() {
        assertFalse(DensePhotoCardDefaults.HAS_SHADOW)
    }
}
