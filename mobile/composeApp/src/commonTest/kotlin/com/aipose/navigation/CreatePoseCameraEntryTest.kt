package com.aipose.navigation

import cafe.adriel.voyager.navigator.tab.Tab
import kotlin.test.Test
import kotlin.test.assertEquals

/** Evidence ID E-CAM-ENTRY: Create Pose (+) / empty-state CTA → CameraTab. */
class CreatePoseCameraEntryTest {

    @Test
    fun eCamEntry_createPoseActionSwitchesToCameraTab() {
        var currentTab: Tab? = null
        val onExtractPoseClick = createPoseCameraEntryAction { currentTab = it }

        onExtractPoseClick()

        assertEquals(CameraTab, currentTab)
    }
}
