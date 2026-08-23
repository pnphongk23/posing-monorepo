package com.aipose.camera

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier

enum class CameraPermissionState {
    NOT_DETERMINED,
    AUTHORIZED,
    DENIED,
    RESTRICTED,
}

enum class CameraFacing {
    BACK,
    FRONT,
}

enum class FlashMode {
    OFF,
    ON,
    AUTO,
}

/**
 * WI-04: explicit capture outcome with no undifferentiated empty-bytes signal.
 * [Success] carries the encoded image bytes; [Failure] reports a native
 * capture/config failure. Capture identity is preserved by the coordinator's
 * closure binding (only one capture is outstanding at a time).
 */
sealed interface CameraCaptureResult {
    data class Success(val bytes: ByteArray) : CameraCaptureResult
    data class Failure(val reason: CameraCaptureFailureReason) : CameraCaptureResult
}

enum class CameraCaptureFailureReason {
    CaptureFailed,
}

expect class CameraController() {
    fun currentPermissionState(): CameraPermissionState
    fun requestPermission(onResult: (CameraPermissionState) -> Unit)

    fun startPreview()
    fun stopPreview()

    fun capture(captureId: String, onResult: (CameraCaptureResult) -> Unit)
    fun cancelCapture()

    fun switchCamera()
    fun setFlashMode(mode: FlashMode)
    fun setGridVisible(isVisible: Boolean)
    fun setZoomFactor(zoomFactor: Float)
    fun openAppSettings()
}

@Composable
expect fun CameraPreview(
    modifier: Modifier,
    controller: CameraController,
)

/**
 * WI-04: observe app background/foreground transitions (iOS: UIKit
 * notifications). Returns a cancel function. Callbacks arrive on the main queue.
 */
expect fun observeAppLifecycle(
    onBackground: () -> Unit,
    onForeground: () -> Unit,
): () -> Unit
