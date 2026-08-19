package com.aipose.platform

expect fun saveImageToPhotos(imagePath: String, context: Any?): Boolean

/**
 * User-facing confirmation for a save-to-photos outcome.
 *
 * Matches the prototype copy "Saved to Photos." on success (and the existing
 * "Save failed" on failure) so the gallery only reports success after the
 * platform write has actually completed.
 */
fun saveToPhotosConfirmation(saved: Boolean): String =
    if (saved) "Saved to Photos." else "Save failed"

/**
 * Testable seam for the save-to-photos flow.
 *
 * Passes the platform write through an injectable [perform] so the
 * success/failure decision can be unit-tested without a live PHPhotoLibrary.
 * The default delegates to the platform [saveImageToPhotos] actual.
 *
 * @return the real write outcome: `true` only when the platform save
 *         completed successfully.
 */
fun saveToPhotos(
    imagePath: String,
    context: Any?,
    perform: (String, Any?) -> Boolean = ::saveImageToPhotos,
): Boolean = perform(imagePath, context)
