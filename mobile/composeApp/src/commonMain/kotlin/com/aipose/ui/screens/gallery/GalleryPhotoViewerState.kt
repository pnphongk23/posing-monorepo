package com.aipose.ui.screens.gallery

import com.aipose.Photo
import com.aipose.data.resolveImagePath
import kotlinx.coroutines.CancellationException

enum class MediaStatus { Loading, Ready, Missing }

sealed interface SaveStatus {
    data object Idle : SaveStatus
    data object Saving : SaveStatus
    data object Saved : SaveStatus
    data class Failed(val message: String) : SaveStatus
}

sealed interface FeedbackMessage {
    data class Info(val text: String) : FeedbackMessage
    data class Error(val text: String, val canRetry: Boolean) : FeedbackMessage
}

sealed interface GalleryPhotoViewerEvent {
    data object ImageLoading : GalleryPhotoViewerEvent
    data object ImageReady : GalleryPhotoViewerEvent
    data object ImageFailed : GalleryPhotoViewerEvent
    data object RetryImage : GalleryPhotoViewerEvent
    data object SaveRequested : GalleryPhotoViewerEvent
    data class SaveResult(val saved: Boolean) : GalleryPhotoViewerEvent
    data object RetrySave : GalleryPhotoViewerEvent
    data object FeedbackAcknowledged : GalleryPhotoViewerEvent
}

data class GalleryPhotoViewerState(
    val photo: Photo,
    val resolvedPath: String?,
    val transitionKey: String,
    val loadAttempt: Int,
    val media: MediaStatus,
    val save: SaveStatus,
    val feedback: FeedbackMessage?,
)

data class GalleryPhotoDateTime(val dateLine: String, val timeLine: String)

fun galleryPhotoTransitionKey(photoId: Long): String = "photo:$photoId"

fun initialGalleryPhotoViewerState(photo: Photo): GalleryPhotoViewerState {
    val resolvedPath = resolveImagePath(photo.imagePath)
        ?: photo.imagePath.takeIf { it.isNotBlank() }
    return GalleryPhotoViewerState(
        photo = photo,
        resolvedPath = resolvedPath,
        transitionKey = galleryPhotoTransitionKey(photo.id),
        loadAttempt = 0,
        media = MediaStatus.Loading,
        save = SaveStatus.Idle,
        feedback = null,
    )
}

/**
 * Parses both timestamp formats that have existed in local gallery rows.
 * Captures are stored as epoch milliseconds, while early builds could persist
 * epoch seconds; treating the latter as milliseconds renders every image in
 * January 1970.
 */
internal fun galleryPhotoEpochMillis(createdAt: String): Long? {
    val value = createdAt.trim().takeIf { it.isNotEmpty() }?.toLongOrNull() ?: return null
    return if (value in -EPOCH_SECONDS_THRESHOLD..EPOCH_SECONDS_THRESHOLD) {
        value * MILLIS_PER_SECOND
    } else {
        value
    }
}

internal fun shouldDismissGalleryDetail(
    offsetPx: Float,
    velocityPxPerSecond: Float,
    viewportHeightPx: Float,
): Boolean {
    if (viewportHeightPx <= 0f) return false
    return offsetPx >= viewportHeightPx * GALLERY_DETAIL_DISMISS_OFFSET_FRACTION ||
        velocityPxPerSecond >= viewportHeightPx * GALLERY_DETAIL_DISMISS_VELOCITY_FACTOR
}

private const val MILLIS_PER_SECOND = 1_000L
private const val EPOCH_SECONDS_THRESHOLD = 10_000_000_000L
private const val GALLERY_DETAIL_DISMISS_OFFSET_FRACTION = 0.25f
private const val GALLERY_DETAIL_DISMISS_VELOCITY_FACTOR = 1.5f

fun reduce(
    state: GalleryPhotoViewerState,
    event: GalleryPhotoViewerEvent,
): GalleryPhotoViewerState = when (event) {
    GalleryPhotoViewerEvent.ImageLoading -> state.copy(media = MediaStatus.Loading)
    GalleryPhotoViewerEvent.ImageReady -> state.copy(media = MediaStatus.Ready)
    GalleryPhotoViewerEvent.ImageFailed -> when (state.media) {
        MediaStatus.Missing -> state
        else -> state.copy(media = MediaStatus.Missing)
    }
    GalleryPhotoViewerEvent.RetryImage -> when (state.media) {
        MediaStatus.Missing -> state.copy(
            media = MediaStatus.Loading,
            loadAttempt = state.loadAttempt + 1,
        )
        else -> state
    }
    GalleryPhotoViewerEvent.SaveRequested -> when {
        state.media != MediaStatus.Ready -> state
        state.save is SaveStatus.Saving -> state
        else -> state.copy(save = SaveStatus.Saving, feedback = null)
    }
    is GalleryPhotoViewerEvent.SaveResult -> when {
        state.save !is SaveStatus.Saving -> state
        event.saved -> state.copy(
            save = SaveStatus.Saved,
            feedback = FeedbackMessage.Info("Saved to Photos."),
        )
        else -> state.copy(
            save = SaveStatus.Failed("Save failed"),
            feedback = FeedbackMessage.Error("Save failed", canRetry = true),
        )
    }
    GalleryPhotoViewerEvent.RetrySave -> when (state.save) {
        is SaveStatus.Failed -> state.copy(save = SaveStatus.Saving, feedback = null)
        else -> state
    }
    GalleryPhotoViewerEvent.FeedbackAcknowledged -> state.copy(feedback = null)
}

/**
 * Route adapter: maps hoisted repository delete to the detail [onDelete] boolean seam.
 * Rethrows [CancellationException]; every other [Exception] becomes `false`.
 */
suspend fun mapGalleryDeletePhotoResult(
    onDeletePhoto: suspend (Long) -> Unit,
    photoId: Long,
): Boolean = try {
    onDeletePhoto(photoId)
    true
} catch (ce: CancellationException) {
    throw ce
} catch (_: Exception) {
    false
}

data class GalleryDeleteCoordinationResult(
    val detailVisible: Boolean,
    val dismissInvocations: Int,
    val deleteAttempts: Int,
    val failureSnackbarPresentations: Int,
)

/**
 * Production delete coordination: one attempt, optional failure snackbar loop with Retry,
 * dismiss exactly once on success. [executeDelete] is the guarded production seam.
 */
suspend fun coordinateGalleryDeleteWithRetry(
    executeDelete: suspend () -> Boolean,
    onDismiss: () -> Unit,
    presentFailureSnackbar: suspend () -> Boolean,
): GalleryDeleteCoordinationResult {
    var dismissInvocations = 0
    var deleteAttempts = 0
    var failureSnackbarPresentations = 0
    val dismissOnce = {
        dismissInvocations++
        onDismiss()
    }

    deleteAttempts++
    if (executeDelete()) {
        dismissOnce()
        return GalleryDeleteCoordinationResult(
            detailVisible = false,
            dismissInvocations = dismissInvocations,
            deleteAttempts = deleteAttempts,
            failureSnackbarPresentations = failureSnackbarPresentations,
        )
    }

    while (true) {
        failureSnackbarPresentations++
        if (!presentFailureSnackbar()) {
            return GalleryDeleteCoordinationResult(
                detailVisible = true,
                dismissInvocations = dismissInvocations,
                deleteAttempts = deleteAttempts,
                failureSnackbarPresentations = failureSnackbarPresentations,
            )
        }
        deleteAttempts++
        if (executeDelete()) {
            dismissOnce()
            return GalleryDeleteCoordinationResult(
                detailVisible = false,
                dismissInvocations = dismissInvocations,
                deleteAttempts = deleteAttempts,
                failureSnackbarPresentations = failureSnackbarPresentations,
            )
        }
    }
}

/** Save/Share/Trash are unavailable while media is not Ready or an action is in flight. */
fun viewerActionsEnabled(
    media: MediaStatus,
    deleteInFlight: Boolean,
    save: SaveStatus,
): Boolean = media == MediaStatus.Ready && !deleteInFlight && save !is SaveStatus.Saving

fun viewerBackEnabled(deleteInFlight: Boolean, save: SaveStatus): Boolean =
    !deleteInFlight && save !is SaveStatus.Saving

/** Whole-flow guard: blocks a second delete confirmation while snackbar/retry is active. */
fun canLaunchGalleryDeleteFlow(deleteFlowActive: Boolean): Boolean = !deleteFlowActive

fun viewerTrashEnabled(
    media: MediaStatus,
    deleteFlowActive: Boolean,
    deleteInFlight: Boolean,
    save: SaveStatus,
): Boolean = viewerActionsEnabled(media, deleteInFlight, save) && !deleteFlowActive

fun formatGalleryPhotoCreatedAt(createdAt: String): GalleryPhotoDateTime? {
    val millis = galleryPhotoEpochMillis(createdAt) ?: return null
    val totalSeconds = millis / 1000
    val secondsOfDay = ((totalSeconds % SECONDS_PER_DAY) + SECONDS_PER_DAY) % SECONDS_PER_DAY
    val totalDays = (totalSeconds / SECONDS_PER_DAY).toInt()
    val (year, month, day) = epochDaysToYearMonthDay(totalDays)
    val hour24 = (secondsOfDay / 3600).toInt()
    val minute = ((secondsOfDay % 3600) / 60).toInt()
    val (hour12, amPm) = to12Hour(hour24)
    val monthStr = MONTHS[month - 1]
    val dayStr = day.toString().padStart(2, '0')
    val minuteStr = minute.toString().padStart(2, '0')
    return GalleryPhotoDateTime(
        dateLine = "$monthStr $dayStr, $year",
        timeLine = "$hour12:$minuteStr $amPm",
    )
}

private const val SECONDS_PER_DAY = 86_400L

private val MONTHS = arrayOf(
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
)

private fun to12Hour(hour24: Int): Pair<Int, String> {
    val amPm = if (hour24 < 12) "AM" else "PM"
    val hour12 = when {
        hour24 == 0 -> 12
        hour24 > 12 -> hour24 - 12
        else -> hour24
    }
    return hour12 to amPm
}

/** Decomposes days-since-epoch (UTC, 1970-01-01) into (year, month, day). */
private fun epochDaysToYearMonthDay(daysSinceEpoch: Int): Triple<Int, Int, Int> {
    val z = daysSinceEpoch + 719468
    val era = (if (z >= 0) z else z - 146096) / 146097
    val doe = z - era * 146097
    val yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
    val y = yoe + era * 400
    val doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
    val mp = (5 * doy + 2) / 153
    val d = doy - (153 * mp + 2) / 5 + 1
    val m = if (mp < 10) mp + 3 else mp - 9
    val yr = if (m <= 2) y + 1 else y
    return Triple(yr.toInt(), m.toInt(), d.toInt())
}
