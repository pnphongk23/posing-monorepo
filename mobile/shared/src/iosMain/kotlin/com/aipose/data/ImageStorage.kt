package com.aipose.data

import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.addressOf
import kotlinx.cinterop.usePinned
import platform.Foundation.NSApplicationSupportDirectory
import platform.Foundation.NSData
import platform.Foundation.NSNumber
import platform.Foundation.NSFileManager
import platform.Foundation.NSString
import platform.Foundation.NSURL
import platform.Foundation.NSUserDomainMask
import platform.Foundation.create
import platform.Foundation.stringByAppendingPathComponent
import platform.Foundation.writeToFile

@OptIn(ExperimentalForeignApi::class)
actual class ImageStorage actual constructor() {
    actual fun writeJpeg(bytes: ByteArray, captureId: String): String? {
        if (bytes.isEmpty()) return null

        val aiposePath = captureDirectoryPath() ?: return null
        val filename = "capture_${captureId}.jpg"
        val fullPath = (aiposePath as NSString).stringByAppendingPathComponent(filename)

        val data = bytes.toNSData()
        val written = data.writeToFile(fullPath, atomically = true)
        return if (written) filename else null
    }

    actual fun verify(filename: String): Boolean {
        val aiposePath = captureDirectoryPath() ?: return false
        val fullPath = (aiposePath as NSString).stringByAppendingPathComponent(filename)
        val attributes = NSFileManager.defaultManager.attributesOfItemAtPath(fullPath, error = null)
        val size = attributes?.get("NSFileSize") as? NSNumber
        return size != null && size.longLongValue > 0L
    }

    actual fun delete(filename: String): Boolean {
        val aiposePath = captureDirectoryPath() ?: return false
        val fullPath = (aiposePath as NSString).stringByAppendingPathComponent(filename)
        return NSFileManager.defaultManager.removeItemAtPath(fullPath, error = null)
    }

    private fun captureDirectoryPath(): String? {
        val directoryUrl = NSFileManager.defaultManager.URLForDirectory(
            directory = NSApplicationSupportDirectory,
            inDomain = NSUserDomainMask,
            appropriateForURL = null,
            create = true,
            error = null,
        ) ?: return null

        val folderPath = directoryUrl.path ?: return null
        val aiposePath = (folderPath as NSString).stringByAppendingPathComponent("aipose")

        NSFileManager.defaultManager.createDirectoryAtPath(
            path = aiposePath,
            withIntermediateDirectories = true,
            attributes = null,
            error = null,
        )
        return aiposePath
    }
}

@OptIn(ExperimentalForeignApi::class)
private fun ByteArray.toNSData(): NSData {
    return this.usePinned {
        NSData.create(
            bytes = it.addressOf(0),
            length = this.size.toULong(),
        )
    }
}
