package com.aipose.platform

/**
 * User-facing confirmation for a delete outcome.
 *
 * Mirrors [saveToPhotosConfirmation]: a failed deletion reports "Delete failed"
 * (never a silent success — FEAT-002 E2 / DEL-UI-01). A successful deletion
 * needs no snackbar (the detail dialog simply dismisses), so it yields the
 * empty string.
 */
fun deletePhotoConfirmation(success: Boolean): String =
    if (success) "" else "Delete failed"
