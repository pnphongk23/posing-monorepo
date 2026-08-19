package com.aipose.platform

import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * DEL-UI-01: delete-outcome copy mirrors the save path (SaveToPhotosTest).
 * A successful deletion needs no snackbar (detail dialog dismisses); a failed
 * deletion reports "Delete failed" so the user is never shown false success.
 */
class DeletePhotoConfirmationTest {

    @Test
    fun `successful delete yields no snackbar message`() {
        assertEquals("", deletePhotoConfirmation(true))
    }

    @Test
    fun `failed delete yields Delete failed confirmation`() {
        assertEquals("Delete failed", deletePhotoConfirmation(false))
    }
}
