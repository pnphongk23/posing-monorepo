package com.aipose.camera

import com.aipose.data.PoseImageVerification

/** Camera-owned render model for a prepared pose guide. */
sealed interface CameraGuideAsset {
    data class Bytes(val value: ByteArray) : CameraGuideAsset
    data class LocalFile(val path: String) : CameraGuideAsset
    data class Invalid(val message: String) : CameraGuideAsset
}

/**
 * Converts the prepared-reference contract into models supported by Coil.
 * Data URIs become ByteArray models; absolute local paths stay file models.
 */
fun cameraGuideAsset(path: String): CameraGuideAsset {
    if (path.isBlank()) return CameraGuideAsset.Invalid("Pose guide is empty.")
    if (path.startsWith("data:")) {
        val bytes = PoseImageVerification.decodeDataUriPayload(path)
        return if (bytes != null && PoseImageVerification.isValidImage(bytes)) {
            CameraGuideAsset.Bytes(bytes)
        } else {
            CameraGuideAsset.Invalid("Pose guide image could not be decoded.")
        }
    }
    if (path.startsWith("/")) return CameraGuideAsset.LocalFile(path)
    return CameraGuideAsset.Invalid("Pose guide uses an unsupported asset path.")
}
