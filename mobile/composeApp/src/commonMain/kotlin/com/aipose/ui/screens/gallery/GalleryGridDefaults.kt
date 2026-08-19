package com.aipose.ui.screens.gallery

import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Dense 3-column gallery grid parity with the prototype `.nb-gallery-grid-dense`
 * (`docs/prototype/styles/components/grid.css:213-219`):
 * `grid-template-columns: repeat(3, minmax(0, 1fr))`, `gap: 3px`.
 *
 * WI-05 (E-GAL-UI): wire `LazyVerticalGrid` to these values so a parity
 * regression (back to 2 cols / wide gap) fails the unit tests.
 */
object GalleryGridDefaults {
    /** Prototype `repeat(3, minmax(0, 1fr))`. */
    const val DENSE_COLUMN_COUNT = 3

    /** Prototype `gap: 3px` (2-4px per the dense grid comment). */
    val DENSE_GAP: Dp = 3.dp
}

/**
 * Dense gallery card parity with the prototype `.nb-card--gallery-dense`
 * (`docs/prototype/styles/components/card.css:174-189`): a square cover image,
 * hairline border (`--nb-border-width-hairline: 1px`), small radius
 * (`--nb-radius-small: 6px`), `box-shadow: none`, and no caption chrome
 * (the dense prototype card is a bare image / placeholder — see `app.js`).
 */
object DensePhotoCardDefaults {
    /** `--nb-radius-small: 6px`. */
    val BORDER_RADIUS: Dp = 6.dp

    /** `--nb-border-width-hairline: 1px`. */
    val BORDER_WIDTH: Dp = 1.dp

    /** `box-shadow: none`. */
    const val HAS_SHADOW = false

    /** `aspect-ratio: 1 / 1`. */
    const val ASPECT_RATIO = 1f
}
