package com.aipose.ui.screens.gallery

import com.aipose.Photo
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class GalleryPhotoViewerStateTest {

    private val photo = Photo(
        id = 42L,
        imagePath = "img-test.jpg",
        poseId = null,
        poseName = "Test Pose",
        createdAt = "1704067200000",
        isFavorite = 0L,
    )

    private fun baseState(
        media: MediaStatus = MediaStatus.Loading,
        loadAttempt: Int = 0,
        save: SaveStatus = SaveStatus.Idle,
        feedback: FeedbackMessage? = null,
    ) = GalleryPhotoViewerState(
        photo = photo,
        resolvedPath = "/resolved/img-test.jpg",
        transitionKey = "photo:42",
        loadAttempt = loadAttempt,
        media = media,
        save = save,
        feedback = feedback,
    )

    @Test
    fun totalReducerGuards() {
        val initial = initialGalleryPhotoViewerState(photo)
        assertEquals(MediaStatus.Loading, initial.media)
        assertEquals(0, initial.loadAttempt)
        assertEquals(SaveStatus.Idle, initial.save)
        assertNull(initial.feedback)
        assertEquals("photo:42", initial.transitionKey)

        val ready = reduce(initial, GalleryPhotoViewerEvent.ImageReady)
        assertEquals(MediaStatus.Ready, ready.media)

        val missing = reduce(ready, GalleryPhotoViewerEvent.ImageFailed)
        assertEquals(MediaStatus.Missing, missing.media)
        assertEquals(ready.resolvedPath, missing.resolvedPath)
        assertEquals(ready.transitionKey, missing.transitionKey)

        val missingNoop = reduce(missing, GalleryPhotoViewerEvent.ImageFailed)
        assertEquals(missing, missingNoop)

        val retry = reduce(missing, GalleryPhotoViewerEvent.RetryImage)
        assertEquals(MediaStatus.Loading, retry.media)
        assertEquals(1, retry.loadAttempt)
        assertEquals(missing.resolvedPath, retry.resolvedPath)

        val retryNoop = reduce(ready, GalleryPhotoViewerEvent.RetryImage)
        assertEquals(ready, retryNoop)

        val saving = reduce(ready, GalleryPhotoViewerEvent.SaveRequested)
        assertEquals(SaveStatus.Saving, saving.save)
        assertNull(saving.feedback)

        val saveNoopWhileLoading = reduce(initial, GalleryPhotoViewerEvent.SaveRequested)
        assertEquals(initial, saveNoopWhileLoading)

        val saved = reduce(saving, GalleryPhotoViewerEvent.SaveResult(true))
        assertEquals(SaveStatus.Saved, saved.save)
        assertEquals(FeedbackMessage.Info("Saved to Photos."), saved.feedback)

        val saveResultNoop = reduce(ready, GalleryPhotoViewerEvent.SaveResult(true))
        assertEquals(ready, saveResultNoop)

        val failed = reduce(saving, GalleryPhotoViewerEvent.SaveResult(false))
        assertEquals(SaveStatus.Failed("Save failed"), failed.save)
        assertEquals(FeedbackMessage.Error("Save failed", canRetry = true), failed.feedback)

        val retrySave = reduce(failed, GalleryPhotoViewerEvent.RetrySave)
        assertEquals(SaveStatus.Saving, retrySave.save)
        assertNull(retrySave.feedback)

        val retrySaveNoop = reduce(ready, GalleryPhotoViewerEvent.RetrySave)
        assertEquals(ready, retrySaveNoop)

        val acknowledged = reduce(saved, GalleryPhotoViewerEvent.FeedbackAcknowledged)
        assertNull(acknowledged.feedback)
        assertEquals(SaveStatus.Saved, acknowledged.save)
    }

    @Test
    fun viewerActionsEnabledRespectsMediaAndInFlightGuards() {
        assertFalse(viewerActionsEnabled(MediaStatus.Loading, deleteInFlight = false, save = SaveStatus.Idle))
        assertFalse(viewerActionsEnabled(MediaStatus.Missing, deleteInFlight = false, save = SaveStatus.Idle))
        assertTrue(viewerActionsEnabled(MediaStatus.Ready, deleteInFlight = false, save = SaveStatus.Idle))
        assertFalse(viewerActionsEnabled(MediaStatus.Ready, deleteInFlight = true, save = SaveStatus.Idle))
        assertFalse(viewerActionsEnabled(MediaStatus.Ready, deleteInFlight = false, save = SaveStatus.Saving))
        assertFalse(viewerBackEnabled(deleteInFlight = true, save = SaveStatus.Idle))
        assertFalse(viewerBackEnabled(deleteInFlight = false, save = SaveStatus.Saving))
        assertTrue(viewerBackEnabled(deleteInFlight = false, save = SaveStatus.Idle))
    }

    @Test
    fun formatGalleryPhotoCreatedAtHandlesNullBlankAndNonNumeric() {
        assertNull(formatGalleryPhotoCreatedAt(""))
        assertNull(formatGalleryPhotoCreatedAt("   "))
        assertNull(formatGalleryPhotoCreatedAt("not-a-number"))

        val formatted = formatGalleryPhotoCreatedAt("1704067200000")
        assertEquals("Jan 01, 2024", formatted?.dateLine)
        assertEquals("12:00 AM", formatted?.timeLine)
    }

    @Test
    fun formatGalleryPhotoCreatedAtNormalizesLegacyEpochSeconds() {
        val formatted = formatGalleryPhotoCreatedAt("1704067200")

        assertEquals(1_704_067_200_000L, galleryPhotoEpochMillis("1704067200"))
        assertEquals("Jan 01, 2024", formatted?.dateLine)
        assertEquals("12:00 AM", formatted?.timeLine)
    }

    @Test
    fun initialGalleryPhotoIndexStartsOnSelectedPhoto() {
        val nextPhoto = photo.copy(id = 43L)
        val photos = listOf(photo, nextPhoto)

        assertEquals(1, initialGalleryPhotoIndex(photos, nextPhoto.id))
        assertEquals(0, initialGalleryPhotoIndex(photos, 999L))
    }

    @Test
    fun galleryDetailDismissRequiresDownwardProgressOrVelocity() {
        assertFalse(
            shouldDismissGalleryDetail(
                offsetPx = 180f,
                velocityPxPerSecond = 0f,
                viewportHeightPx = 800f,
            ),
        )
        assertTrue(
            shouldDismissGalleryDetail(
                offsetPx = 200f,
                velocityPxPerSecond = 0f,
                viewportHeightPx = 800f,
            ),
        )
        assertTrue(
            shouldDismissGalleryDetail(
                offsetPx = 40f,
                velocityPxPerSecond = 1_300f,
                viewportHeightPx = 800f,
            ),
        )
        assertFalse(
            shouldDismissGalleryDetail(
                offsetPx = 40f,
                velocityPxPerSecond = -1_300f,
                viewportHeightPx = 800f,
            ),
        )
    }
}
