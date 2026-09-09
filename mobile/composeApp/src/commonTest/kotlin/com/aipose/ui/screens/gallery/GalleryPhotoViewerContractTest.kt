package com.aipose.ui.screens.gallery

import com.aipose.Photo
import com.aipose.platform.deletePhotoConfirmation
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Pure contract tests for the gallery photo viewer v2 seams (no live Coil host).
 */
class GalleryPhotoViewerContractTest {

    private val photo = Photo(
        id = 7L,
        imagePath = "missing.jpg",
        poseId = null,
        poseName = "Pose",
        createdAt = "1704067200000",
        isFavorite = 0L,
    )

    @Test
    fun missingImageRetryKeepsPathAndIncrementsAttempt() {
        var state = initialGalleryPhotoViewerState(photo)
        val originalPath = state.resolvedPath
        val originalKey = state.transitionKey

        state = reduce(state, GalleryPhotoViewerEvent.ImageFailed)
        assertEquals(MediaStatus.Missing, state.media)
        assertEquals(originalPath, state.resolvedPath)
        assertEquals(originalKey, state.transitionKey)
        assertFalse(viewerActionsEnabled(state.media, deleteInFlight = false, state.save))

        state = reduce(state, GalleryPhotoViewerEvent.RetryImage)
        assertEquals(MediaStatus.Loading, state.media)
        assertEquals(1, state.loadAttempt)
        assertEquals(originalPath, state.resolvedPath)
        assertEquals(originalKey, state.transitionKey)
        assertEquals(photo.id, state.photo.id)
    }

    @Test
    fun deleteFailureShowsRetryAndRetainsDetail() {
        runBlocking {
        var deleteAttempts = 0
        var dismissCount = 0
        var snackbarShows = 0

        val failTwice = coordinateGalleryDeleteWithRetry(
            executeDelete = {
                deleteAttempts++
                mapGalleryDeletePhotoResult(
                    onDeletePhoto = { throw RuntimeException("delete failed") },
                    photoId = photo.id,
                )
            },
            onDismiss = { dismissCount++ },
            presentFailureSnackbar = {
                snackbarShows++
                snackbarShows == 1
            },
        )

        assertTrue(failTwice.detailVisible)
        assertEquals(0, dismissCount)
        assertEquals(2, failTwice.deleteAttempts)
        assertEquals(2, failTwice.failureSnackbarPresentations)
        assertEquals("Delete failed", deletePhotoConfirmation(false))

        var successDismissCount = 0
        val success = coordinateGalleryDeleteWithRetry(
            executeDelete = {
                mapGalleryDeletePhotoResult(
                    onDeletePhoto = { },
                    photoId = photo.id,
                )
            },
            onDismiss = { successDismissCount++ },
            presentFailureSnackbar = { error("should not present") },
        )

        assertFalse(success.detailVisible)
        assertEquals(1, successDismissCount)
        assertEquals(1, success.deleteAttempts)
        assertEquals(0, success.failureSnackbarPresentations)

        var retryThenSuccessAttempts = 0
        var retryDismissCount = 0
        val retrySuccess = coordinateGalleryDeleteWithRetry(
            executeDelete = {
                retryThenSuccessAttempts++
                mapGalleryDeletePhotoResult(
                    onDeletePhoto = {
                        if (retryThenSuccessAttempts == 1) throw RuntimeException("first fail")
                    },
                    photoId = photo.id,
                )
            },
            onDismiss = { retryDismissCount++ },
            presentFailureSnackbar = { true },
        )

        assertFalse(retrySuccess.detailVisible)
        assertEquals(1, retryDismissCount)
        assertEquals(2, retrySuccess.deleteAttempts)
        assertEquals(1, retrySuccess.failureSnackbarPresentations)

        assertFailsWith<CancellationException> {
            mapGalleryDeletePhotoResult(
                onDeletePhoto = { throw CancellationException("cancelled") },
                photoId = photo.id,
            )
        }

        assertTrue(canLaunchGalleryDeleteFlow(deleteFlowActive = false))
        assertFalse(canLaunchGalleryDeleteFlow(deleteFlowActive = true))
        var flowActive = false
        var launches = 0
        fun tryLaunch(): Boolean {
            if (!canLaunchGalleryDeleteFlow(flowActive)) return false
            flowActive = true
            launches++
            return true
        }
        assertTrue(tryLaunch())
        assertFalse(tryLaunch())
        flowActive = false
        assertTrue(tryLaunch())
        assertEquals(2, launches)

        assertTrue(viewerBackEnabled(deleteInFlight = false, save = SaveStatus.Idle))
        assertFalse(
            viewerTrashEnabled(
                media = MediaStatus.Ready,
                deleteFlowActive = true,
                deleteInFlight = false,
                save = SaveStatus.Idle,
            ),
        )
        assertTrue(
            viewerTrashEnabled(
                media = MediaStatus.Ready,
                deleteFlowActive = false,
                deleteInFlight = false,
                save = SaveStatus.Idle,
            ),
        )
        }
    }

    @Test
    fun saveCallbackResultMapsThroughReducer() {
        var state = reduce(
            initialGalleryPhotoViewerState(photo).let { reduce(it, GalleryPhotoViewerEvent.ImageReady) },
            GalleryPhotoViewerEvent.SaveRequested,
        )
        assertEquals(SaveStatus.Saving, state.save)

        state = reduce(state, GalleryPhotoViewerEvent.SaveResult(false))
        assertEquals(SaveStatus.Failed("Save failed"), state.save)
        assertEquals(FeedbackMessage.Error("Save failed", canRetry = true), state.feedback)

        state = reduce(state, GalleryPhotoViewerEvent.RetrySave)
        state = reduce(state, GalleryPhotoViewerEvent.SaveResult(true))
        assertEquals(SaveStatus.Saved, state.save)
        assertEquals(FeedbackMessage.Info("Saved to Photos."), state.feedback)

        state = reduce(state, GalleryPhotoViewerEvent.FeedbackAcknowledged)
        assertNull(state.feedback)
    }
}
