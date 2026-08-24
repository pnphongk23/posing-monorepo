package com.aipose.camera

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull

class CameraStateTest {
    @Test
    fun poseLineColorDefaultsToBlack() {
        assertEquals(PoseLineColor.Black, CameraUiState().poseLineColor)
    }

    @Test
    fun whiteLineColorProducesColorFilter() {
        assertNotNull(PoseLineColor.White.toColorFilter())
    }

    @Test
    fun blackLineColorProducesColorFilter() {
        assertNotNull(PoseLineColor.Black.toColorFilter())
    }

    @Test
    fun everyLineColorMapsToARenderTint() {
        PoseLineColor.entries.forEach { color ->
            assertNotNull(color.toColorFilter(), "$color should map to a ColorFilter")
        }
    }
}
