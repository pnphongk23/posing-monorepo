package com.aipose.navigation

import kotlin.test.Test
import kotlin.test.assertEquals

/** Evidence ID E-DOCK: MainDock test-tag contract (UI assertions rely on these). */
class MainDockTest {

    @Test
    fun eDock_testTagContract() {
        assertEquals("main-dock", MAIN_DOCK_TEST_TAG)
        assertEquals("main-dock-poses", MAIN_DOCK_POSES_TEST_TAG)
        assertEquals("main-dock-gallery", MAIN_DOCK_GALLERY_TEST_TAG)
        assertEquals("main-dock-camera", MAIN_DOCK_CAMERA_TEST_TAG)
    }
}