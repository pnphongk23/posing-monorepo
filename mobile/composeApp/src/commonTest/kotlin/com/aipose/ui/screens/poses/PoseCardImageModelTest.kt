package com.aipose.ui.screens.poses

import androidx.compose.ui.layout.ContentScale
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Focused test for the shared pose-card image fill policy (crop fill, no
 * letterbox white strips, no distortion). The former network-model classification
 * and post-cache fallback helpers were removed from the Community Coil lane, so
 * their tests were dropped rather than kept as dead coverage.
 */
class PoseCardImageModelTest {

    @Test
    fun fillPolicyIsCrop() {
        assertEquals(ContentScale.Crop, poseThumbnailContentScale())
    }
}