package com.aipose.camera

import androidx.compose.ui.geometry.Offset

enum class CameraFrameRatio(val width: Int, val height: Int) {
    RATIO_4_3(3, 4),
    RATIO_16_9(9, 16),
    RATIO_1_1(1, 1),
}

data class CameraUiState(
    val permissionState: CameraPermissionState = CameraPermissionState.NOT_DETERMINED,
    val cameraFacing: CameraFacing = CameraFacing.BACK,
    val flashMode: FlashMode = FlashMode.OFF,
    val frameRatio: CameraFrameRatio = CameraFrameRatio.RATIO_4_3,
    val isGridVisible: Boolean = false,
    val isMoreMenuVisible: Boolean = false,
    val isOverlayVisible: Boolean = true,
    val overlayOpacity: Float = 0.5f,
    val overlayOffset: Offset = Offset.Zero,
    val overlayScale: Float = 1f,
    val overlaySource: OverlaySourceState = OverlaySourceState.None,
)

sealed interface OverlaySourceState {
    data object None : OverlaySourceState
    data class PlaceholderAsset(val assetName: String) : OverlaySourceState
    data class PoseImage(val poseId: String, val skeletonPath: String) : OverlaySourceState
}

sealed interface ThumbnailState {
    data object Empty : ThumbnailState
    data class Available(val imagePath: String) : ThumbnailState
}

// -------------------------------------------------------------------------
// Pure derivations from CameraCoordinatorState (WI-02) — unit-testable without
// Compose so the UI layer stays a thin renderer over coordinator state.
// -------------------------------------------------------------------------

/** Latest valid thumbnail: most recent successful capture wins, else last persisted path. */
fun CameraCoordinatorState.thumbnailState(): ThumbnailState {
    val current = phase
    if (current is CameraPhase.CaptureSucceeded) {
        return ThumbnailState.Available(current.photo.imagePath)
    }
    return thumbnailPath?.let { ThumbnailState.Available(it) } ?: ThumbnailState.Empty
}

/** Status text shown under the preview; success/failure states and sticky failures produce text. */
fun CameraCoordinatorState.statusText(): String? = when (val current = phase) {
    is CameraPhase.CaptureSucceeded -> "Saved"
    is CameraPhase.CaptureError -> current.failure.userMessage()
    // Sticky failure: survives dismissResult so the status stays visible while
    // controls are re-enabled (UI state matrix: Capture failed → PreviewReady +
    // "Failed to save photo"). Cleared on the next capture attempt.
    else -> lastFailure?.userMessage()
}

/** Failure-only status (success path handled separately). */
fun CameraCoordinatorState.captureStatusText(): String? = lastFailure?.userMessage()
