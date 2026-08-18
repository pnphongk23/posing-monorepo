package com.aipose.data

import io.ktor.util.decodeBase64Bytes
import io.ktor.util.encodeBase64
import kotlinx.serialization.Serializable

/**
 * Typed prepared-reference contract emitted when "Try Pose" succeeds (WI-04).
 *
 * Consumed by the dependent Camera handoff Plan (260809-2241): the app must
 * prepare and verify the render asset *before* leaving detail, then hand the
 * selection to the handoff instead of discarding it with a bare tab change.
 * WI-04 does not render the Camera overlay and does not persist the reference
 * across relaunch.
 *
 * @param key source-qualified key of the selected pose (Personal or Community).
 * @param name display name of the selected pose.
 * @param renderLocator verified render asset locator: the original data URI for
 *   personal data-URI assets, the resolved absolute local path for personal
 *   file assets, or a fresh `data:` URI built from the just-downloaded
 *   community image bytes. Never a remote URL, so the handoff cannot consume a
 *   stale or unreachable asset.
 */
@Serializable
data class PreparedPoseReference(
    val key: PoseReferenceKey,
    val name: String,
    val renderLocator: String
)

/**
 * Structural image verification used by the Try Pose prepare step (E4).
 *
 * Full pixel decoding happens at render time (Coil / the Camera handoff). This
 * boundary guarantees the render asset is present, readable, and a supported
 * image format before the app leaves detail, so Try Pose never navigates to
 * Camera with a missing, stale, or wrong overlay.
 */
object PoseImageVerification {

    private val PNG_SIGNATURE = byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
    private val JPEG_SIGNATURE = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte())
    private val GIF_SIGNATURE = byteArrayOf(0x47, 0x49, 0x46, 0x38) // "GIF8"
    private val RIFF_SIGNATURE = byteArrayOf(0x52, 0x49, 0x46, 0x46) // "RIFF"
    private val WEBP_SIGNATURE = byteArrayOf(0x57, 0x45, 0x42, 0x50) // "WEBP"

    /** Detects the mime type of [bytes], or null when they are not a supported image. */
    fun detectImageMimeType(bytes: ByteArray): String? = when {
        bytes.size >= PNG_SIGNATURE.size && bytes.startsWithBytes(PNG_SIGNATURE) -> "image/png"
        bytes.size >= JPEG_SIGNATURE.size && bytes.startsWithBytes(JPEG_SIGNATURE) -> "image/jpeg"
        bytes.size >= GIF_SIGNATURE.size && bytes.startsWithBytes(GIF_SIGNATURE) -> "image/gif"
        bytes.size >= 12 && bytes.startsWithBytes(RIFF_SIGNATURE) &&
            bytes.copyOfRange(8, 12).contentEquals(WEBP_SIGNATURE) -> "image/webp"
        else -> null
    }

    fun isValidImage(bytes: ByteArray): Boolean = detectImageMimeType(bytes) != null

    /**
     * Decodes the payload of a `data:<mime>;base64,<payload>` URI, or returns
     * null when the URI is not a base64 data URI or its payload cannot be
     * decoded into bytes.
     */
    fun decodeDataUriPayload(uri: String): ByteArray? {
        if (!uri.startsWith("data:")) return null
        val comma = uri.indexOf(',')
        if (comma <= "data:".length) return null
        val header = uri.substring("data:".length, comma)
        if (!header.contains("base64")) return null
        val payload = uri.substring(comma + 1)
        if (payload.isBlank()) return null
        return try {
            payload.decodeBase64Bytes()
        } catch (_: Exception) {
            null
        }
    }

    /** Builds a self-contained `data:` URI from verified image [bytes]. */
    fun toDataUri(bytes: ByteArray, mimeType: String): String =
        "data:$mimeType;base64,${bytes.encodeBase64()}"

    private fun ByteArray.startsWithBytes(prefix: ByteArray): Boolean {
        if (size < prefix.size) return false
        for (i in prefix.indices) {
            if (this[i] != prefix[i]) return false
        }
        return true
    }
}
