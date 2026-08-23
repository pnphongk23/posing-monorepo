package com.aipose.camera

import com.aipose.data.ImageStorage
import com.aipose.data.PhotoRepository

/**
 * WI-02 (Plan 260819-2355) — explicit ports for the Camera coordinator.
 *
 * These interfaces are the test seams for the coordinator: production wires the
 * real shared-module classes through the small adapters at the bottom of this
 * file, while unit tests inject fakes. No camera code may depend on concrete
 * storage/metadata classes directly — the UI layer only dispatches actions.
 */

/** Native camera bridge surface required by the capture state machine. */
interface CameraControllerPort {
    fun currentPermissionState(): CameraPermissionState
    fun requestPermission(onResult: (CameraPermissionState) -> Unit)

    /** Requests one capture; [onResult] reports an explicit success/failure result. */
    fun capture(captureId: String, onResult: (CameraCaptureResult) -> Unit)

    /**
     * Drops an in-flight native capture: clears the pending bridge callback so
     * a later capture request is not rejected with a failure result. Safe to
     * call with no capture in flight.
     */
    fun cancelCapture()

    fun switchCamera()
    fun setFlashMode(mode: FlashMode)
    fun setGridVisible(isVisible: Boolean)
    fun setZoomFactor(zoomFactor: Float)
    fun openAppSettings()
}

/** Port for writing/removing captured JPEG files (ImageStorage seam). */
interface CaptureImageWriter {
    /**
     * Writes JPEG bytes to owned storage using the capture identity. Returns
     * the relative filename on success or null when the write failed.
     */
    fun writeJpeg(bytes: ByteArray, captureId: String): String?

    /** Verifies that the newly written file is readable and non-empty. */
    fun verify(filename: String): Boolean

    /**
     * Deletes a file previously created by [writeJpeg]. Used for compensation
     * when metadata insertion fails (WI-05 hardens idempotency + read-verify).
     */
    fun delete(filename: String)
}

/** Port for Photo metadata reads/writes (PhotoRepository seam). */
interface CapturePhotoMetadata {
    /** Inserts a captured-photo row; returns the new row id (0 on failure). */
    fun insertCapturedPhoto(imagePath: String): Long

    /** Latest known photo path, used to seed the thumbnail on (re-)entry. */
    fun getLatestPhotoPath(): String?
}

/** Deterministic-time seam for capture timeout detection. */
interface CameraClock {
    fun nowMillis(): Long
}

/** Collision-resistant capture identity seam. */
interface CameraIdGenerator {
    fun nextCaptureId(): String
}

/** A successfully persisted capture: metadata record returned to UI state directly. */
data class CapturedPhotoRecord(
    val id: Long,
    val imagePath: String,
)

/** Typed failure kinds surfaced to the UI. */
sealed interface CaptureFailure {
    data object EmptyBytes : CaptureFailure
    data object Timeout : CaptureFailure
    data object WriteFailed : CaptureFailure
    data object MetadataInsertFailed : CaptureFailure

    fun userMessage(): String = when (this) {
        EmptyBytes, Timeout -> "Capture unavailable"
        WriteFailed, MetadataInsertFailed -> "Failed to save photo"
    }
}

// ---------------------------------------------------------------------------
// Production adapters (shared module → camera ports)
// ---------------------------------------------------------------------------

/** Adapts the shared [ImageStorage] to [CaptureImageWriter]. */
class ImageStorageWriterAdapter(
    private val storage: ImageStorage,
) : CaptureImageWriter {
    override fun writeJpeg(bytes: ByteArray, captureId: String): String? = storage.writeJpeg(bytes, captureId)
    override fun verify(filename: String): Boolean = storage.verify(filename)
    override fun delete(filename: String) {
        storage.delete(filename)
    }
}

/** Adapts the shared [PhotoRepository] to [CapturePhotoMetadata]. */
class PhotoMetadataAdapter(
    private val repository: PhotoRepository,
) : CapturePhotoMetadata {
    override fun insertCapturedPhoto(imagePath: String): Long = repository.insertCapturedPhoto(imagePath)
    override fun getLatestPhotoPath(): String? = repository.getLatestPhotoPath()
}

/** Adapts the native [CameraController] expect class to [CameraControllerPort]. */
class CameraControllerAdapter(
    private val controller: CameraController,
) : CameraControllerPort {
    override fun currentPermissionState(): CameraPermissionState = controller.currentPermissionState()
    override fun requestPermission(onResult: (CameraPermissionState) -> Unit) {
        controller.requestPermission(onResult)
    }

    override fun capture(captureId: String, onResult: (CameraCaptureResult) -> Unit) {
        controller.capture(captureId, onResult)
    }

    override fun cancelCapture() {
        controller.cancelCapture()
    }

    override fun switchCamera() = controller.switchCamera()
    override fun setFlashMode(mode: FlashMode) = controller.setFlashMode(mode)
    override fun setGridVisible(isVisible: Boolean) = controller.setGridVisible(isVisible)
    override fun setZoomFactor(zoomFactor: Float) = controller.setZoomFactor(zoomFactor)
    override fun openAppSettings() = controller.openAppSettings()
}

/** Wall-clock [CameraClock]. */
class SystemClock : CameraClock {
    override fun nowMillis(): Long = kotlin.system.getTimeMillis()
}

/** Monotonic in-process capture id: `<epochMillis>-<counter>`, collision-resistant per process. */
class TimestampCounterIdGenerator(
    private val clock: CameraClock,
) : CameraIdGenerator {
    private var counter = 0L

    override fun nextCaptureId(): String = "${clock.nowMillis()}-${counter++}"
}