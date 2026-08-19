package com.aipose.platform

import platform.Photos.PHAssetChangeRequest
import platform.Photos.PHPhotoLibrary
import platform.Foundation.NSURL
import kotlinx.cinterop.ExperimentalForeignApi

@OptIn(ExperimentalForeignApi::class)
actual fun saveImageToPhotos(imagePath: String, context: Any?): Boolean {
    val url = NSURL.fileURLWithPath(imagePath)
    // performChangesAndWait returns true only when the change block was
    // successfully applied to the shared photo library, so we surface that
    // real outcome instead of assuming success inside the change block.
    return PHPhotoLibrary.sharedPhotoLibrary().performChangesAndWait({
        PHAssetChangeRequest.creationRequestForAssetFromImageAtFileURL(url)
    }, null)
}
