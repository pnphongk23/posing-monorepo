package com.aipose.camera

import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.readBytes
import platform.AVFoundation.AVCaptureDevice
import platform.AVFoundation.AVAuthorizationStatusAuthorized
import platform.AVFoundation.AVAuthorizationStatusDenied
import platform.AVFoundation.AVAuthorizationStatusNotDetermined
import platform.AVFoundation.AVAuthorizationStatusRestricted
import platform.AVFoundation.AVMediaTypeVideo
import platform.AVFoundation.authorizationStatusForMediaType
import platform.Foundation.NSData
import platform.Foundation.NSNotification
import platform.Foundation.NSNotificationCenter
import platform.Foundation.NSUUID
import platform.Foundation.NSOperationQueue
import platform.darwin.NSObjectProtocol
import platform.darwin.dispatch_async
import platform.darwin.dispatch_get_main_queue

@OptIn(ExperimentalForeignApi::class)
internal class IOSCameraController {
    private val bridgeId: String = NSUUID().UUIDString
    private val notificationCenter = NSNotificationCenter.defaultCenter

    private var pendingCaptureCallback: ((CameraCaptureResult) -> Unit)? = null
    private var pendingPermissionCallback: ((CameraPermissionState) -> Unit)? = null
    private var bridgeEventObserver: NSObjectProtocol? = null

    init {
        observeBridgeEvents()
    }

    fun permissionState(): CameraPermissionState {
        val status = AVCaptureDevice.authorizationStatusForMediaType(AVMediaTypeVideo).toLong()
        return when (status) {
            AVAuthorizationStatusNotDetermined -> CameraPermissionState.NOT_DETERMINED
            AVAuthorizationStatusAuthorized -> CameraPermissionState.AUTHORIZED
            AVAuthorizationStatusDenied -> CameraPermissionState.DENIED
            AVAuthorizationStatusRestricted -> CameraPermissionState.RESTRICTED
            else -> CameraPermissionState.DENIED
        }
    }

    fun requestPermission(onResult: (CameraPermissionState) -> Unit) {
        pendingPermissionCallback = onResult
        postBridgeCommand(command = "requestPermission")
    }

    fun startPreview() {
        postBridgeCommand(command = "start")
    }

    fun stopPreview() {
        postBridgeCommand(command = "stop")
    }

    fun attachPreviewHost(hostView: platform.UIKit.UIView) {
        postBridgeCommand(
            command = "attach",
            payload = mapOf(KEY_HOST_VIEW to hostView),
        )
    }

    fun detachPreviewHost() {
        postBridgeCommand(command = "detach")
    }

    fun switchCamera() {
        postBridgeCommand(command = "switch")
    }

    fun setFlashMode(mode: FlashMode) {
        postBridgeCommand(
            command = "setFlash",
            payload = mapOf(KEY_FLASH_MODE to mode.name),
        )
    }

    fun setGridVisible(isVisible: Boolean) {
        postBridgeCommand(
            command = "setGrid",
            payload = mapOf(KEY_GRID_VISIBLE to isVisible),
        )
    }

    fun setZoomFactor(zoomFactor: Float) {
        postBridgeCommand(
            command = "setZoom",
            payload = mapOf(KEY_ZOOM_FACTOR to zoomFactor.toDouble()),
        )
    }

    fun capture(captureId: String, onResult: (CameraCaptureResult) -> Unit) {
        if (pendingCaptureCallback != null) {
            // A capture is already in flight; report an explicit failure instead
            // of an undifferentiated empty-bytes signal (WI-04).
            dispatch_async(dispatch_get_main_queue()) {
                onResult(CameraCaptureResult.Failure(CameraCaptureFailureReason.CaptureFailed))
            }
            return
        }

        pendingCaptureCallback = onResult
        // captureId is bound by the calling closure, preserving capture identity
        // without a separate native round-trip (single outstanding capture).
        postBridgeCommand(command = "capture")
    }

    /**
     * Clears the pending capture callback so a stale native "captured" event
     * or a subsequent capture request cannot propagate an invalid result.
     * WI-02 cancellation hook; WI-04 wires the native session cancellation.
     */
    fun cancelCapture() {
        pendingCaptureCallback = null
    }

    private fun observeBridgeEvents() {
        bridgeEventObserver = notificationCenter.addObserverForName(
            name = EVENT_NAME,
            `object` = null,
            queue = NSOperationQueue.mainQueue,
        ) { notification: NSNotification? ->
            handleBridgeEvent(notification)
        }
    }


    private fun handleBridgeEvent(notification: NSNotification?) {
        val userInfo = notification?.userInfo ?: return

        val eventBridgeId = userInfo[KEY_BRIDGE_ID] as? String ?: return
        if (eventBridgeId != bridgeId) {
            return
        }

        val event = userInfo[KEY_EVENT] as? String ?: return
        when (event) {
            "captured" -> {
                val data = userInfo[KEY_IMAGE_DATA] as? NSData
                val callback = pendingCaptureCallback
                pendingCaptureCallback = null
                val result = if (data == null || data.length.toInt() == 0) {
                    // Explicit failure — never an undifferentiated empty payload (WI-04).
                    CameraCaptureResult.Failure(CameraCaptureFailureReason.CaptureFailed)
                } else {
                    CameraCaptureResult.Success(data.toByteArray())
                }
                callback?.invoke(result)
            }

            "permissionState" -> {
                val permissionRaw = userInfo[KEY_PERMISSION_STATE] as? String
                val callback = pendingPermissionCallback
                pendingPermissionCallback = null
                callback?.invoke(permissionRaw.toPermissionStateOrFallback())
            }
        }
    }

    private fun postBridgeCommand(command: String, payload: Map<String, Any> = emptyMap()) {
        val userInfo = mutableMapOf<Any?, Any?>(
            KEY_BRIDGE_ID to bridgeId,
            KEY_COMMAND to command,
        )
        payload.forEach { (key, value) ->
            userInfo[key] = value
        }

        notificationCenter.postNotificationName(
            aName = COMMAND_NAME,
            `object` = null,
            userInfo = userInfo,
        )
    }

    private fun String?.toPermissionStateOrFallback(): CameraPermissionState {
        return when (this) {
            "AUTHORIZED" -> CameraPermissionState.AUTHORIZED
            "DENIED" -> CameraPermissionState.DENIED
            "RESTRICTED" -> CameraPermissionState.RESTRICTED
            "NOT_DETERMINED" -> CameraPermissionState.NOT_DETERMINED
            else -> permissionState()
        }
    }

    companion object {
        private const val COMMAND_NAME = "AIPoseCameraBridgeCommand"
        private const val EVENT_NAME = "AIPoseCameraBridgeEvent"

        private const val KEY_BRIDGE_ID = "bridgeId"
        private const val KEY_COMMAND = "command"
        private const val KEY_HOST_VIEW = "hostView"
        private const val KEY_FLASH_MODE = "flashMode"
        private const val KEY_GRID_VISIBLE = "gridVisible"
        private const val KEY_ZOOM_FACTOR = "zoomFactor"

        private const val KEY_EVENT = "event"
        private const val KEY_PERMISSION_STATE = "permissionState"
        private const val KEY_IMAGE_DATA = "imageData"
    }
}

@OptIn(ExperimentalForeignApi::class)
private fun NSData.toByteArray(): ByteArray {
    val lengthValue = length.toInt()
    if (lengthValue == 0) {
        return ByteArray(0)
    }
    val bytesPtr = bytes ?: return ByteArray(0)
    return bytesPtr.readBytes(lengthValue)
}
