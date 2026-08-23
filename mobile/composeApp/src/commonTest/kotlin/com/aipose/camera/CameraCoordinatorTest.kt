package com.aipose.camera

import io.ktor.util.decodeBase64Bytes
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * WI-02 (Plan 260819-2355) — deterministic state-machine coverage for the
 * Camera coordinator. All ports are fakes; no real file system, database, or
 * native camera is touched.
 */
class CameraCoordinatorTest {

    // ------------------------------------------------------------------ fakes

    private class FakeCameraController(
        initialPermission: CameraPermissionState = CameraPermissionState.NOT_DETERMINED,
    ) : CameraControllerPort {
        var permission: CameraPermissionState = initialPermission
        var requestPermissionCalls = 0
        var captureCalls = 0
        var cancelCaptureCalls = 0
        private var permissionCallback: ((CameraPermissionState) -> Unit)? = null
        private var captureCallback: ((CameraCaptureResult) -> Unit)? = null

        override fun currentPermissionState(): CameraPermissionState = permission

        override fun requestPermission(onResult: (CameraPermissionState) -> Unit) {
            requestPermissionCalls += 1
            permissionCallback = onResult
        }

        override fun capture(captureId: String, onResult: (CameraCaptureResult) -> Unit) {
            captureCalls += 1
            if (captureCallback != null) {
                // Faithful to IOSCameraController: a second capture request
                // while a callback is pending is rejected with an explicit failure.
                onResult(CameraCaptureResult.Failure(CameraCaptureFailureReason.CaptureFailed))
                return
            }
            captureCallback = onResult
        }

        override fun cancelCapture() {
            cancelCaptureCalls += 1
            captureCallback = null
        }

        override fun switchCamera() = Unit
        override fun setFlashMode(mode: FlashMode) = Unit
        override fun setGridVisible(isVisible: Boolean) = Unit
        override fun setZoomFactor(zoomFactor: Float) = Unit
        override fun openAppSettings() = Unit

        /** Fake user grants/denies permission after a request. */
        fun grantPermission(result: CameraPermissionState) {
            permission = result
            permissionCallback?.invoke(result)
            permissionCallback = null
        }

        /** Fake native layer delivers a successful capture (late callbacks are testable). */
        fun deliverSuccess(bytes: ByteArray) {
            captureCallback?.invoke(CameraCaptureResult.Success(bytes))
            captureCallback = null
        }

        /** Fake native layer reports a capture failure. */
        fun deliverFailure() {
            captureCallback?.invoke(CameraCaptureResult.Failure(CameraCaptureFailureReason.CaptureFailed))
            captureCallback = null
        }
    }

    private class FakeImageWriter : CaptureImageWriter {
        val files = mutableMapOf<String, ByteArray>()
        var failNextWrite = false
        var failNextVerify = false
        val deleted = mutableListOf<String>()

        override fun writeJpeg(bytes: ByteArray, captureId: String): String? {
            if (failNextWrite) {
                failNextWrite = false
                return null
            }
            val name = "capture_${files.size + 1}.jpg"
            files[name] = bytes
            return name
        }

        override fun verify(filename: String): Boolean {
            if (failNextVerify) {
                failNextVerify = false
                return false
            }
            return files[filename]?.isNotEmpty() == true
        }

        override fun delete(filename: String) {
            files.remove(filename)
            deleted += filename
        }
    }

    private class FakePhotoMetadata : CapturePhotoMetadata {
        val rows = mutableListOf<CapturedPhotoRecord>()
        var nextId = 1L
        var failNextInsert = false
        var insertZeroNext = false

        override fun insertCapturedPhoto(imagePath: String): Long {
            if (failNextInsert) {
                failNextInsert = false
                throw RuntimeException("db failure")
            }
            if (insertZeroNext) {
                insertZeroNext = false
                return 0L
            }
            val id = nextId++
            rows += CapturedPhotoRecord(id = id, imagePath = imagePath)
            return id
        }

        override fun getLatestPhotoPath(): String? = rows.lastOrNull()?.imagePath
    }

    private class FakeClock(var now: Long = 0L) : CameraClock {
        override fun nowMillis(): Long = now
        fun advance(ms: Long) {
            now += ms
        }
    }

    private class IncrementingIdGenerator : CameraIdGenerator {
        private var n = 0
        override fun nextCaptureId(): String = "id-${n++}"
    }

    private class Harness(
        val controller: FakeCameraController = FakeCameraController(),
        val writer: FakeImageWriter = FakeImageWriter(),
        val metadata: FakePhotoMetadata = FakePhotoMetadata(),
        val clock: FakeClock = FakeClock(now = 1_000L),
        val ids: IncrementingIdGenerator = IncrementingIdGenerator(),
    ) {
        val coordinator = CameraCoordinator(
            controller = controller,
            imageStorage = writer,
            photoMetadata = metadata,
            clock = clock,
            idGenerator = ids,
        )

        fun enterPreviewReady() {
            coordinator.onLaunch()
            controller.grantPermission(CameraPermissionState.AUTHORIZED)
        }
    }

    // ------------------------------------------------------------- permission

    @Test
    fun notDetermined_requestsPermission_thenAuthorizedTransitionsToPreviewReady() {
        val h = Harness()
        h.coordinator.onLaunch()

        assertEquals(CameraPermissionState.NOT_DETERMINED, h.coordinator.currentState.permission)
        assertEquals(1, h.controller.requestPermissionCalls)

        h.controller.grantPermission(CameraPermissionState.AUTHORIZED)

        assertEquals(CameraPhase.PreviewReady, h.coordinator.currentState.phase)
        assertTrue(h.coordinator.currentState.captureEnabled)
    }

    @Test
    fun permissionDenied_staysPermissionRequired_andDisablesCapture() {
        val h = Harness()
        h.coordinator.onLaunch()
        h.controller.grantPermission(CameraPermissionState.DENIED)

        assertEquals(CameraPhase.PermissionRequired, h.coordinator.currentState.phase)
        assertEquals(CameraPermissionState.DENIED, h.coordinator.currentState.permission)
        assertFalse(h.coordinator.currentState.captureEnabled)
    }

    @Test
    fun alreadyAuthorized_onLaunch_goesStraightToPreviewReady() {
        val h = Harness(controller = FakeCameraController(initialPermission = CameraPermissionState.AUTHORIZED))

        h.coordinator.onLaunch()

        assertEquals(CameraPhase.PreviewReady, h.coordinator.currentState.phase)
        assertEquals(0, h.controller.requestPermissionCalls)
    }

    // -------------------------------------------------------------- capture

    @Test
    fun captureFlow_idleToCapturingToPersistingToSucceeded() {
        val h = Harness()
        h.enterPreviewReady()

        val accepted = h.coordinator.onCaptureRequested()

        assertTrue(accepted)
        assertEquals(CameraPhase.Capturing("id-0"), h.coordinator.currentState.phase)
        assertEquals(1, h.controller.captureCalls)

        h.controller.deliverSuccess(byteArrayOf(1, 2, 3))
        // Persisting is synchronous with the callback and completes immediately.
        val after = h.coordinator.currentState
        assertEquals("id-0", (after.phase as CameraPhase.CaptureSucceeded).captureId)
        assertEquals(1L, (after.phase as CameraPhase.CaptureSucceeded).photo.id)
        assertEquals("capture_1.jpg", (after.phase as CameraPhase.CaptureSucceeded).photo.imagePath)
        assertFalse(after.isCaptureInFlight)
        assertNull(after.lastFailure)
    }

    @Test
    fun captureCannotStart_withoutPermission() {
        val h = Harness()
        h.coordinator.onLaunch() // still NOT_DETERMINED; no grant

        val accepted = h.coordinator.onCaptureRequested()

        assertFalse(accepted)
        assertEquals(0, h.controller.captureCalls)
        assertEquals(CameraPhase.PermissionRequired, h.coordinator.currentState.phase)
    }

    @Test
    fun duplicateTap_whileCapturing_isIgnored() {
        val h = Harness()
        h.enterPreviewReady()

        h.coordinator.onCaptureRequested()
        val secondAccepted = h.coordinator.onCaptureRequested()

        assertFalse(secondAccepted)
        assertEquals(1, h.controller.captureCalls)
        assertEquals(CameraPhase.Capturing("id-0"), h.coordinator.currentState.phase)
    }

    // ------------------------------------------------------------ failures

    @Test
    fun emptyBytes_leadsToCaptureUnavailableError_noFileNoMetadata() {
        val h = Harness()
        h.enterPreviewReady()

        h.coordinator.onCaptureRequested()
        h.controller.deliverSuccess(ByteArray(0))

        val after = h.coordinator.currentState
        val error = assertIs<CameraPhase.CaptureError>(after.phase)
        assertEquals(CaptureFailure.EmptyBytes, error.failure)
        assertEquals(CaptureFailure.EmptyBytes, after.lastFailure)
        assertEquals("Capture unavailable", after.captureStatusText())
        assertTrue(h.writer.files.isEmpty())
        assertTrue(h.metadata.rows.isEmpty())
    }

    @Test
    fun explicitNativeFailureResult_leadsToCaptureUnavailableError_noFileNoMetadata() {
        val h = Harness()
        h.enterPreviewReady()

        h.coordinator.onCaptureRequested()
        h.controller.deliverFailure()

        val after = h.coordinator.currentState
        val error = assertIs<CameraPhase.CaptureError>(after.phase)
        assertEquals(CaptureFailure.EmptyBytes, error.failure)
        assertEquals("Capture unavailable", after.statusText())
        assertTrue(h.writer.files.isEmpty())
        assertTrue(h.metadata.rows.isEmpty())
    }

    @Test
    fun writeFailure_leadsToWriteError_noMetadataRow() {
        val h = Harness()
        h.enterPreviewReady()
        h.writer.failNextWrite = true

        h.coordinator.onCaptureRequested()
        h.controller.deliverSuccess(byteArrayOf(1))

        val after = h.coordinator.currentState
        val error = assertIs<CameraPhase.CaptureError>(after.phase)
        assertEquals(CaptureFailure.WriteFailed, error.failure)
        assertTrue(h.writer.files.isEmpty())
        assertTrue(h.metadata.rows.isEmpty())
        assertEquals("Failed to save photo", after.captureStatusText())
    }

    @Test
    fun readVerificationFailure_compensatesByDeletingFile() {
        val h = Harness()
        h.enterPreviewReady()
        h.writer.failNextVerify = true

        h.coordinator.onCaptureRequested()
        h.controller.deliverSuccess(byteArrayOf(1, 2))

        val error = assertIs<CameraPhase.CaptureError>(h.coordinator.currentState.phase)
        assertEquals(CaptureFailure.WriteFailed, error.failure)
        assertTrue(h.writer.files.isEmpty())
        assertEquals(listOf("capture_1.jpg"), h.writer.deleted)
        assertTrue(h.metadata.rows.isEmpty())
    }

    @Test
    fun metadataInsertException_compensatesByDeletingFile() {
        val h = Harness()
        h.enterPreviewReady()
        h.metadata.failNextInsert = true

        h.coordinator.onCaptureRequested()
        h.controller.deliverSuccess(byteArrayOf(1, 2))

        val after = h.coordinator.currentState
        val error = assertIs<CameraPhase.CaptureError>(after.phase)
        assertEquals(CaptureFailure.MetadataInsertFailed, error.failure)
        assertTrue(h.writer.files.isEmpty(), "compensation must remove the written file")
        assertEquals(listOf("capture_1.jpg"), h.writer.deleted)
        assertTrue(h.metadata.rows.isEmpty())
        assertNull(after.thumbnailPath)
    }

    @Test
    fun metadataInsertReturningZero_compensatesByDeletingFile() {
        val h = Harness()
        h.enterPreviewReady()
        h.metadata.insertZeroNext = true

        h.coordinator.onCaptureRequested()
        h.controller.deliverSuccess(byteArrayOf(1, 2))

        val after = h.coordinator.currentState
        assertIs<CameraPhase.CaptureError>(after.phase)
        assertEquals(listOf("capture_1.jpg"), h.writer.deleted)
        assertTrue(h.writer.files.isEmpty())
        assertTrue(h.metadata.rows.isEmpty())
    }

    // --------------------------------------------------------------- timeout

    @Test
    fun timeout_invalidatesActiveCapture_lateBytesIgnored() {
        val h = Harness()
        h.enterPreviewReady()

        h.coordinator.onCaptureRequested() // at t=1_000
        h.clock.advance(h.coordinator.captureTimeoutMillis + 1)
        h.coordinator.onCaptureTimeoutTick()

        val after = h.coordinator.currentState
        val error = assertIs<CameraPhase.CaptureError>(after.phase)
        assertEquals(CaptureFailure.Timeout, error.failure)
        assertEquals(1, h.controller.cancelCaptureCalls, "timeout must cancel the native pending callback")

        // Late native callback for the expired capture is discarded.
        h.controller.deliverSuccess(byteArrayOf(9, 9))
        assertIs<CameraPhase.CaptureError>(h.coordinator.currentState.phase)
        assertTrue(h.writer.files.isEmpty())
        assertTrue(h.metadata.rows.isEmpty())
    }

    @Test
    fun timeoutTick_beforeWindow_doesNotInvalidate() {
        val h = Harness()
        h.enterPreviewReady()

        h.coordinator.onCaptureRequested()
        h.clock.advance(h.coordinator.captureTimeoutMillis - 1)
        h.coordinator.onCaptureTimeoutTick()

        assertIs<CameraPhase.Capturing>(h.coordinator.currentState.phase)
    }

    // ---------------------------------------------------- background / fore

    @Test
    fun backgrounding_cancelsCapture_disablesControls_foregroundRestores() {
        val h = Harness()
        h.enterPreviewReady()

        h.coordinator.onCaptureRequested()
        h.coordinator.onBackground()

        val bg = h.coordinator.currentState
        assertEquals(CameraPhase.PreviewReady, bg.phase)
        assertEquals(CameraLifecycle.Inactive, bg.lifecycle)
        assertFalse(bg.captureEnabled)
        assertEquals(1, h.controller.cancelCaptureCalls, "backgrounding must cancel the in-flight capture")

        // Late bytes after backgrounding are ignored.
        h.controller.deliverSuccess(byteArrayOf(5))
        assertEquals(CameraPhase.PreviewReady, h.coordinator.currentState.phase)
        assertTrue(h.writer.files.isEmpty())

        h.coordinator.onForeground()
        assertTrue(h.coordinator.currentState.captureEnabled)
        assertEquals(CameraLifecycle.Active, h.coordinator.currentState.lifecycle)
    }

    // ------------------------------------------------- late/duplicate callback

    @Test
    fun staleCallbackForPreviousCapture_isIgnored_whileNewCaptureProceeds() {
        val h = Harness()
        h.enterPreviewReady()

        h.coordinator.onCaptureRequested() // id-0
        h.clock.advance(h.coordinator.captureTimeoutMillis + 1)
        h.coordinator.onCaptureTimeoutTick()
        h.coordinator.dismissResult() // back to PreviewReady

        h.coordinator.onCaptureRequested() // id-1
        // The stale id-0 closure fires late with a payload.
        h.coordinator.onCaptureResult("id-0", CameraCaptureResult.Success(byteArrayOf(1, 2, 3)))

        val after = h.coordinator.currentState
        assertEquals(CameraPhase.Capturing("id-1"), after.phase)
        assertTrue(h.writer.files.isEmpty())
        assertTrue(h.metadata.rows.isEmpty())
    }

    @Test
    fun duplicateDeliveryForSameCapture_isIdempotent() {
        val h = Harness()
        h.enterPreviewReady()

        h.coordinator.onCaptureRequested()
        // Callback fires once; the fake clears its slot. Deliver again through
        // the same path would be a second onCaptureBytes with the same id.
        h.controller.deliverSuccess(byteArrayOf(1))
        val first = h.coordinator.currentState
        assertIs<CameraPhase.CaptureSucceeded>(first.phase)

        // Same id re-delivered after success: ignored, no duplicate rows.
        h.coordinator.onCaptureResult("id-0", CameraCaptureResult.Success(byteArrayOf(1)))
        val second = h.coordinator.currentState
        assertEquals(first, second)
        assertEquals(1, h.metadata.rows.size)
        assertEquals(1, h.writer.files.size)
    }

    // ----------------------------------------------------------- dismiss

    @Test
    fun dismissResult_returnsToPreviewReady_keepingThumbnailAndStatus() {
        val h = Harness()
        h.enterPreviewReady()

        h.coordinator.onCaptureRequested()
        h.controller.deliverSuccess(byteArrayOf(1))
        assertIs<CameraPhase.CaptureSucceeded>(h.coordinator.currentState.phase)

        h.coordinator.dismissResult()

        val after = h.coordinator.currentState
        assertEquals(CameraPhase.PreviewReady, after.phase)
        assertEquals("capture_1.jpg", after.thumbnailPath)
        assertTrue(after.captureEnabled)
        assertEquals(ThumbnailState.Available("capture_1.jpg"), after.thumbnailState())
    }

    @Test
    fun errorPhase_dismissesBackToPreviewReady_statusTextPersists() {
        val h = Harness()
        h.enterPreviewReady()

        h.coordinator.onCaptureRequested()
        h.controller.deliverSuccess(ByteArray(0))
        assertIs<CameraPhase.CaptureError>(h.coordinator.currentState.phase)

        h.coordinator.dismissResult()

        val after = h.coordinator.currentState
        assertEquals(CameraPhase.PreviewReady, after.phase)
        assertEquals("Capture unavailable", after.captureStatusText())
        assertEquals(CaptureFailure.EmptyBytes, after.lastFailure)
    }

    // --------------------------------------------------- pipeline + thumbnail

    @Test
    fun captureToGalleryPipeline_producesReadableFileAndMetadataRecordGalleryWouldShow() {
        val h = Harness()
        h.enterPreviewReady()

        h.coordinator.onCaptureRequested()
        val jpegBytes = "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////2wBDAf//////////////////////////////////////////////////////////////////////////////////////wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAX/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAH/AP/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAT8Af//EABQRAQAAAAAAAAAAAAAAAAAAABD/2gAIAQIBAT8Af//EABQRAQAAAAAAAAAAAAAAAAAAABD/2gAIAQMBAT8Af//Z".decodeBase64Bytes()
        h.controller.deliverSuccess(jpegBytes)

        val after = h.coordinator.currentState
        val succeeded = assertIs<CameraPhase.CaptureSucceeded>(after.phase)

        // File written and non-empty (readable by Gallery).
        val file = h.writer.files[succeeded.photo.imagePath]
        assertNotNull(file)
        assertTrue(file.isNotEmpty())

        // Exactly one metadata record pointing at the created file.
        assertEquals(1, h.metadata.rows.size)
        val record = h.metadata.rows.single()
        assertEquals(succeeded.photo.imagePath, record.imagePath)
        assertEquals(succeeded.photo, record)
        assertEquals(record.imagePath, h.metadata.getLatestPhotoPath())

        // Thumbnail state resolves to the captured image path.
        assertEquals(ThumbnailState.Available(succeeded.photo.imagePath), after.thumbnailState())
    }

    @Test
    fun refreshLatestThumbnail_seedsThumbnailFromMetadata() {
        val h = Harness()
        h.enterPreviewReady()
        h.metadata.rows += CapturedPhotoRecord(id = 7L, imagePath = "capture_7.jpg")

        h.coordinator.refreshLatestThumbnail()

        assertEquals("capture_7.jpg", h.coordinator.currentState.thumbnailPath)
        assertEquals(ThumbnailState.Available("capture_7.jpg"), h.coordinator.currentState.thumbnailState())
    }

    @Test
    fun failureNeverUpdatesThumbnail() {
        val h = Harness()
        h.enterPreviewReady()

        h.coordinator.onCaptureRequested()
        h.controller.deliverSuccess(ByteArray(0)) // failure path

        assertNull(h.coordinator.currentState.thumbnailPath)
        assertEquals(ThumbnailState.Empty, h.coordinator.currentState.thumbnailState())
    }

    // ------------------------------------------------------------- idempotence

    @Test
    fun captureRecordingGeneration_neverReusesAnId() {
        val h = Harness()
        val first = h.ids.nextCaptureId()
        val second = h.ids.nextCaptureId()
        val third = h.ids.nextCaptureId()

        assertTrue(first != second && second != third && first != third)
    }

    // ---------------------------------------------------- WI-03 UI derivations

    @Test
    fun statusText_showsSavedOnSuccess_andFailureMessageOnError() {
        // Success → "Saved"
        val success = CameraCoordinatorState(
            phase = CameraPhase.CaptureSucceeded("id-1", CapturedPhotoRecord(id = 1, imagePath = "capture_1.jpg")),
            thumbnailPath = "capture_1.jpg",
        )
        assertEquals("Saved", success.statusText())

        // Error → typed message
        val error = CameraCoordinatorState(
            phase = CameraPhase.CaptureError("id-2", CaptureFailure.EmptyBytes),
            lastFailure = CaptureFailure.EmptyBytes,
        )
        assertEquals("Capture unavailable", error.statusText())
        assertEquals("Capture unavailable", error.captureStatusText())

        // Ready → no status
        val ready = CameraCoordinatorState(phase = CameraPhase.PreviewReady)
        assertNull(ready.statusText())
        assertNull(ready.captureStatusText())
    }

    @Test
    fun statusText_persistsAfterErrorDismissalThenClearsOnNextCaptureAttempt() {
        val h = Harness()
        h.enterPreviewReady()

        h.coordinator.onCaptureRequested()
        h.controller.deliverSuccess(ByteArray(0))
        h.coordinator.dismissResult()
        assertEquals("Capture unavailable", h.coordinator.currentState.statusText())

        // Next capture attempt clears the sticky failure and shows no status.
        h.coordinator.onCaptureRequested()
        assertEquals(null, h.coordinator.currentState.statusText())
    }

    @Test
    fun thumbnailDerivation_prefersLatestCaptureOverStoredPath() {
        val readyWithOld = CameraCoordinatorState(
            phase = CameraPhase.PreviewReady,
            thumbnailPath = "old.jpg",
        )
        assertEquals(ThumbnailState.Available("old.jpg"), readyWithOld.thumbnailState())

        val succeededWithNew = CameraCoordinatorState(
            phase = CameraPhase.CaptureSucceeded("id-3", CapturedPhotoRecord(id = 3, imagePath = "new.jpg")),
            thumbnailPath = "new.jpg",
        )
        assertEquals(ThumbnailState.Available("new.jpg"), succeededWithNew.thumbnailState())

        val empty = CameraCoordinatorState(phase = CameraPhase.PermissionRequired)
        assertEquals(ThumbnailState.Empty, empty.thumbnailState())
    }
}