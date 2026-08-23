package com.aipose.camera

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * WI-02 (Plan 260819-2355) — Camera capture coordinator.
 *
 * Owns the approved capture state machine and captures the persistence
 * orchestration behind explicit ports. The UI renders [state] and dispatches
 * actions only; no file/database transaction lives in the composable.
 *
 * State transition table (phase × event → next phase, side effects):
 *
 * | Current                   | Event                         | Next                          | Side effects                  |
 * |---------------------------|-------------------------------|-------------------------------|-------------------------------|
 * | PermissionRequired        | onPermissionResult(AUTHORIZED)| PreviewReady                  | —                             |
 * | PermissionRequired        | onPermissionResult(denied)    | PermissionRequired            | —                             |
 * | PreviewReady              | onCaptureRequested           | Capturing(id)                 | controller.capture(id)        |
 * | Capturing(id)             | bytes (non-empty)            | Persisting(id)                | persist bytes                 |
 * | Capturing(id)             | bytes (empty)                | CaptureError(id, EmptyBytes)  | — (no file)                   |
 * | Capturing(id)             | timeout tick                 | CaptureError(id, Timeout)     | —                             |
 * | Persisting(id)            | write ok, insert ok          | CaptureSucceeded(id, record)  | thumbnail = record.imagePath  |
 * | Persisting(id)            | write failed                 | CaptureError(id, WriteFailed) | — (nothing written)           |
 * | Persisting(id)            | insert failed                | CaptureError(id, InsFailed)   | imageStorage.delete(file)     |
 * | CaptureSucceeded(id, rec) | dismissResult                | PreviewReady                  | — (thumbnail kept)            |
 * | CaptureError(id, why)     | dismissResult                | PreviewReady                  | — (status text kept via lastFailure) |
 * | any                       | onBackground                 | PreviewReady + Inactive       | in-flight capture dropped     |
 * | any                       | onForeground                 | same phase + Active           | —                             |
 *
 * Orthogonal lifecycle: only one capture may be in flight; stale/late
 * callbacks for a non-active captureId are ignored and cleaned up.
 *
 * Dispatch ownership: state mutations happen on whichever thread invokes an
 * action. The iOS bridge delivers native callbacks on the main queue (see
 * IOSCameraController), so production state updates are main-confined; WI-04
 * hardens explicit marshalling. Tests drive every transition synchronously.
 */
sealed interface CameraPhase {
    data object PermissionRequired : CameraPhase
    data object PreviewReady : CameraPhase
    data class Capturing(val captureId: String) : CameraPhase
    data class Persisting(val captureId: String) : CameraPhase
    data class CaptureSucceeded(val captureId: String, val photo: CapturedPhotoRecord) : CameraPhase
    data class CaptureError(val captureId: String, val failure: CaptureFailure) : CameraPhase
}

enum class CameraLifecycle {
    Active,
    Inactive,
}

data class CameraCoordinatorState(
    val phase: CameraPhase = CameraPhase.PermissionRequired,
    val permission: CameraPermissionState = CameraPermissionState.NOT_DETERMINED,
    val lifecycle: CameraLifecycle = CameraLifecycle.Active,
    /** Latest known valid photo path for the thumbnail (survives phase transitions). */
    val thumbnailPath: String? = null,
    /** Sticky last failure for status text; cleared on next capture attempt. */
    val lastFailure: CaptureFailure? = null,
) {
    val isCaptureInFlight: Boolean
        get() = phase is CameraPhase.Capturing || phase is CameraPhase.Persisting

    /** Shutter enabled only when preview is live, permission granted and not in flight. */
    val captureEnabled: Boolean
        get() = phase is CameraPhase.PreviewReady && lifecycle == CameraLifecycle.Active
}

class CameraCoordinator(
    private val controller: CameraControllerPort,
    private val imageStorage: CaptureImageWriter,
    private val photoMetadata: CapturePhotoMetadata,
    private val clock: CameraClock,
    private val idGenerator: CameraIdGenerator,
    val captureTimeoutMillis: Long = CAPTURE_TIMEOUT_MILLIS_DEFAULT,
) {
    private val _state = MutableStateFlow(CameraCoordinatorState())
    val state: StateFlow<CameraCoordinatorState> = _state.asStateFlow()
    val currentState: CameraCoordinatorState get() = _state.value

    private var captureStartedAtMillis: Long = 0L

    init {
        // Seed the current permission so the first rendered frame is accurate.
        _state.value = _state.value.copy(permission = controller.currentPermissionState())
    }

    /** App-entry: request permission when not determined, else adopt current state. */
    fun onLaunch() {
        val initialPermission = controller.currentPermissionState()
        _state.value = _state.value.copy(permission = initialPermission)
        when (initialPermission) {
            CameraPermissionState.NOT_DETERMINED -> controller.requestPermission(::onPermissionResult)
            CameraPermissionState.AUTHORIZED -> _state.value = _state.value.copy(phase = CameraPhase.PreviewReady)
            CameraPermissionState.DENIED, CameraPermissionState.RESTRICTED ->
                _state.value = _state.value.copy(phase = CameraPhase.PermissionRequired)
        }
    }

    /** Permission callback from the native bridge or settings re-entry. */
    fun onPermissionResult(permission: CameraPermissionState) {
        val nextPhase = if (permission == CameraPermissionState.AUTHORIZED) {
            CameraPhase.PreviewReady
        } else {
            CameraPhase.PermissionRequired
        }
        _state.value = _state.value.copy(permission = permission, phase = nextPhase)
    }

    /**
     * Shutter press. No-op unless the shutter is enabled (PreviewReady +
     * Active), which both guards duplicate taps and ignores pre-permission
     * presses. Returns true when the capture was accepted.
     */
    fun onCaptureRequested(): Boolean {
        val current = currentState
        if (!current.captureEnabled) return false

        val captureId = idGenerator.nextCaptureId()
        captureStartedAtMillis = clock.nowMillis()
        _state.value = current.copy(
            phase = CameraPhase.Capturing(captureId),
            lastFailure = null,
        )
        controller.capture(captureId) { result -> onCaptureResult(captureId, result) }
        return true
    }

    /** Native capture callback. Stale callbacks (wrong id / no active capture) are ignored. */
    fun onCaptureResult(captureId: String, result: CameraCaptureResult) {
        val current = currentState
        val phase = current.phase
        if (phase !is CameraPhase.Capturing || phase.captureId != captureId) return

        when (result) {
            is CameraCaptureResult.Failure ->
                failCapture(current, captureId, CaptureFailure.EmptyBytes)

            is CameraCaptureResult.Success -> {
                if (result.bytes.isEmpty()) {
                    failCapture(current, captureId, CaptureFailure.EmptyBytes)
                } else {
                    _state.value = current.copy(phase = CameraPhase.Persisting(captureId))
                    persist(captureId, result.bytes)
                }
            }
        }
    }

    private fun failCapture(current: CameraCoordinatorState, captureId: String, failure: CaptureFailure) {
        _state.value = current.copy(
            phase = CameraPhase.CaptureError(captureId, failure),
            lastFailure = failure,
        )
    }

    /** UI-originated tick after [captureTimeoutMillis] spent in Capturing. */
    fun onCaptureTimeoutTick() {
        val current = currentState
        val phase = current.phase
        if (phase !is CameraPhase.Capturing) return
        if (clock.nowMillis() - captureStartedAtMillis < captureTimeoutMillis) return

        // Invalidate the capture AND drop the native pending callback so a
        // later capture request is not rejected with the stale slot (see
        // IOSCameraController.capture). A late native "captured" event for the
        // stale id is then discarded by onCaptureBytes' id guard.
        controller.cancelCapture()
        _state.value = current.copy(
            phase = CameraPhase.CaptureError(phase.captureId, CaptureFailure.Timeout),
            lastFailure = CaptureFailure.Timeout,
        )
    }

    /** App backgrounds: cancel the in-flight capture and disable controls. */
    fun onBackground() {
        val current = currentState
        val dropped = current.phase is CameraPhase.Capturing || current.phase is CameraPhase.Persisting
        if (dropped) {
            controller.cancelCapture()
        }
        _state.value = current.copy(
            phase = if (dropped) CameraPhase.PreviewReady else current.phase,
            lifecycle = CameraLifecycle.Inactive,
        )
    }

    /** App foreground re-entry: restore control state; preview restarts on the platform layer. */
    fun onForeground() {
        _state.value = currentState.copy(lifecycle = CameraLifecycle.Active)
    }

    /** UI acknowledges a terminal result; back to PreviewReady (thumbnail/status persist). */
    fun dismissResult() {
        val current = currentState
        if (current.phase is CameraPhase.CaptureSucceeded || current.phase is CameraPhase.CaptureError) {
            _state.value = current.copy(phase = CameraPhase.PreviewReady)
        }
    }

    /** Seeds the thumbnail from the latest persisted photo (app / tab re-entry). */
    fun refreshLatestThumbnail() {
        val path = photoMetadata.getLatestPhotoPath()
        if (path != null) {
            _state.value = currentState.copy(thumbnailPath = path)
        }
    }

    private fun persist(captureId: String, bytes: ByteArray) {
        val filename = imageStorage.writeJpeg(bytes, captureId)
        if (filename == null) {
            _state.value = currentState.copy(
                phase = CameraPhase.CaptureError(captureId, CaptureFailure.WriteFailed),
                lastFailure = CaptureFailure.WriteFailed,
            )
            return
        }

        if (!imageStorage.verify(filename)) {
            imageStorage.delete(filename)
            _state.value = currentState.copy(
                phase = CameraPhase.CaptureError(captureId, CaptureFailure.WriteFailed),
                lastFailure = CaptureFailure.WriteFailed,
            )
            return
        }

        val id = try {
            photoMetadata.insertCapturedPhoto(filename)
        } catch (e: Exception) {
            // Metadata failed → compensation: remove the freshly written file.
            imageStorage.delete(filename)
            _state.value = currentState.copy(
                phase = CameraPhase.CaptureError(captureId, CaptureFailure.MetadataInsertFailed),
                lastFailure = CaptureFailure.MetadataInsertFailed,
            )
            return
        }

        if (id <= 0L) {
            imageStorage.delete(filename)
            _state.value = currentState.copy(
                phase = CameraPhase.CaptureError(captureId, CaptureFailure.MetadataInsertFailed),
                lastFailure = CaptureFailure.MetadataInsertFailed,
            )
            return
        }

        _state.value = currentState.copy(
            phase = CameraPhase.CaptureSucceeded(captureId, CapturedPhotoRecord(id = id, imagePath = filename)),
            thumbnailPath = filename,
            lastFailure = null,
        )
    }

    companion object {
        const val CAPTURE_TIMEOUT_MILLIS_DEFAULT = 10_000L
    }
}