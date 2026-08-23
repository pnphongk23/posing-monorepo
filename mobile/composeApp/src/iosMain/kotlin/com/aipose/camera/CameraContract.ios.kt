package com.aipose.camera

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import platform.Foundation.NSNotificationCenter
import platform.Foundation.NSOperationQueue
import platform.Foundation.NSURL
import platform.UIKit.UIApplication
import platform.UIKit.UIApplicationDidEnterBackgroundNotification
import platform.UIKit.UIApplicationOpenSettingsURLString
import platform.UIKit.UIApplicationWillEnterForegroundNotification
import platform.darwin.NSObjectProtocol

actual class CameraController {
    internal val impl = IOSCameraController()

    actual fun currentPermissionState(): CameraPermissionState {
        return impl.permissionState()
    }

    actual fun requestPermission(onResult: (CameraPermissionState) -> Unit) {
        impl.requestPermission(onResult)
    }

    actual fun startPreview() {
        impl.startPreview()
    }

    actual fun stopPreview() {
        impl.stopPreview()
    }

    actual fun capture(captureId: String, onResult: (CameraCaptureResult) -> Unit) {
        impl.capture(captureId, onResult)
    }

    actual fun cancelCapture() {
        impl.cancelCapture()
    }

    actual fun switchCamera() {
        impl.switchCamera()
    }

    actual fun setFlashMode(mode: FlashMode) {
        impl.setFlashMode(mode)
    }

    actual fun setGridVisible(isVisible: Boolean) {
        impl.setGridVisible(isVisible)
    }

    actual fun setZoomFactor(zoomFactor: Float) {
        impl.setZoomFactor(zoomFactor)
    }

    actual fun openAppSettings() {
        val url = NSURL.URLWithString(UIApplicationOpenSettingsURLString)
        if (url != null) {
            UIApplication.sharedApplication.openURL(url)
        }
    }
}

@Composable
actual fun CameraPreview(
    modifier: Modifier,
    controller: CameraController,
) {
    val cameraController = remember(controller) { controller }
    IOSCameraPreview(
        modifier = modifier,
        cameraController = cameraController.impl,
    )
}

/**
 * WI-04: observes UIKit DidEnterBackground / WillEnterForeground so the
 * coordinator can cancel an in-flight capture and stop/restart the preview.
 * Callbacks arrive on the main queue. Returns a cancel function.
 */
actual fun observeAppLifecycle(
    onBackground: () -> Unit,
    onForeground: () -> Unit,
): () -> Unit {
    val center = NSNotificationCenter.defaultCenter
    val backgroundObserver: NSObjectProtocol = center.addObserverForName(
        name = UIApplicationDidEnterBackgroundNotification,
        `object` = null,
        queue = NSOperationQueue.mainQueue,
    ) { _ -> onBackground() }
    val foregroundObserver: NSObjectProtocol = center.addObserverForName(
        name = UIApplicationWillEnterForegroundNotification,
        `object` = null,
        queue = NSOperationQueue.mainQueue,
    ) { _ -> onForeground() }
    return {
        center.removeObserver(backgroundObserver)
        center.removeObserver(foregroundObserver)
    }
}
