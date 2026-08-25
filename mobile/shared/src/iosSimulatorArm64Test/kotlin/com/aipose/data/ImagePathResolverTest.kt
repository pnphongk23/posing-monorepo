package com.aipose.data

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class ImagePathResolverTest {
    @Test
    fun resolveImagePath_handlesBlankPath() {
        assertNull(resolveImagePath(""))
        assertNull(resolveImagePath("   "))
    }

    @Test
    fun resolveImagePath_preservesRemoteHttpUrls() {
        val httpUrl = "http://pub-xxxx.r2.dev/poses/sample.jpg"
        val httpsUrl = "https://pub-xxxx.r2.dev/poses/sample.jpg"
        assertEquals(httpUrl, resolveImagePath(httpUrl))
        assertEquals(httpsUrl, resolveImagePath(httpsUrl))
    }

    @Test
    fun resolveImagePath_handlesAbsolutePaths() {
        val path = "/var/mobile/Containers/Data/Application/test.jpg"
        assertEquals(path, resolveImagePath(path))
    }

    @Test
    fun resolveImagePath_returnsNullForNonExistentRelativePath() {
        assertNull(resolveImagePath("nonexistent_relative_file.png"))
    }
}
