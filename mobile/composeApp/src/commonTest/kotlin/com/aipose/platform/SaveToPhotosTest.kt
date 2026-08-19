package com.aipose.platform

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class SaveToPhotosTest {

    @Test
    fun `successful save yields Saved to Photos confirmation`() {
        assertEquals("Saved to Photos.", saveToPhotosConfirmation(true))
    }

    @Test
    fun `failed save yields Save failed confirmation`() {
        assertEquals("Save failed", saveToPhotosConfirmation(false))
    }

    @Test
    fun `saveToPhotos reports true when platform perform succeeds`() {
        val result = saveToPhotos("/tmp/photo.jpg", null) { _, _ -> true }
        assertTrue(result)
    }

    @Test
    fun `saveToPhotos reports false when platform perform fails`() {
        val result = saveToPhotos("/tmp/photo.jpg", null) { _, _ -> false }
        assertFalse(result)
    }
}
