package com.aipose.navigation

import cafe.adriel.voyager.navigator.tab.Tab
import com.aipose.data.PreparedPoseReference
import kotlin.test.Test
import kotlin.test.assertEquals

/** Evidence ID E-TRY-EMIT: Try Pose success → preparedReference + CameraTab. */
class TryPoseCameraHandoffTest {

    @Test
    fun eTryEmit_successSetsPreparedReferenceAndSwitchesToCameraTab() {
        var prepared: PreparedPoseReference? = null
        var currentTab: Tab? = null
        val handoff = createTryPoseCameraHandoffAction(
            setPreparedReference = { prepared = it },
            setCurrentTab = { currentTab = it },
        )
        val reference = PreparedPoseReference(
            poseId = "00000000-0000-0000-0000-000000000042",
            poseName = "Test Pose",
            skeletonPath = "data:image/png;base64,abc",
        )

        handoff(reference)

        assertEquals(reference, prepared)
        assertEquals(CameraTab, currentTab)
    }
}
