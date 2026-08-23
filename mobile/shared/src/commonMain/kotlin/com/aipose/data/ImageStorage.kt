package com.aipose.data

expect class ImageStorage() {
    fun writeJpeg(bytes: ByteArray, captureId: String): String?

    /**
     * Deletes an owned capture file previously created by [writeJpeg].
     * Returns true when the file was removed (or already absent). Additive
     * port for WI-02 compensation; WI-05 hardens idempotency + read-verify.
     */
    fun verify(filename: String): Boolean

    fun delete(filename: String): Boolean
}
