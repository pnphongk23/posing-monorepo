package com.aipose.camera

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class CameraGuideAssetTest {
    private val onePixelPng =
        "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="

    @Test
    fun validDataUriSelectsByteArrayModel() {
        val asset = cameraGuideAsset(onePixelPng)

        assertTrue(asset is CameraGuideAsset.Bytes)
        assertTrue((asset as CameraGuideAsset.Bytes).value.isNotEmpty())
    }

    @Test
    fun absoluteLocalPathRemainsFileModel() {
        assertEquals(
            CameraGuideAsset.LocalFile("/documents/guide.png"),
            cameraGuideAsset("/documents/guide.png"),
        )
    }

    @Test
    fun invalidDataUriSelectsVisibleFallbackModel() {
        val asset = cameraGuideAsset("data:image/png;base64,not-valid")

        assertTrue(asset is CameraGuideAsset.Invalid)
        assertEquals("Pose guide image could not be decoded.", (asset as CameraGuideAsset.Invalid).message)
    }
}
