package com.aipose.data

import kotlinx.cinterop.ExperimentalForeignApi
import platform.Foundation.NSApplicationSupportDirectory
import platform.Foundation.NSFileManager
import platform.Foundation.NSString
import platform.Foundation.NSUserDomainMask
import platform.Foundation.stringByAppendingPathComponent
import platform.Foundation.lastPathComponent

@OptIn(ExperimentalForeignApi::class)
actual fun resolveImagePath(storedPath: String): String? {
    if (storedPath.isBlank()) return null

    // 1. Remote HTTP/HTTPS URLs: return as-is
    if (storedPath.startsWith("http://", ignoreCase = true) ||
        storedPath.startsWith("https://", ignoreCase = true)
    ) {
        return storedPath
    }

    val fileManager = NSFileManager.defaultManager

    // 2. Handle file:// URIs
    if (storedPath.startsWith("file://", ignoreCase = true)) {
        val rawPath = storedPath.substring(7)
        if (fileManager.fileExistsAtPath(rawPath)) {
            return rawPath
        }
    }

    // 3. Absolute local file path (starts with /)
    if (storedPath.startsWith("/")) {
        if (fileManager.fileExistsAtPath(storedPath)) {
            return storedPath
        }
    }

    // 4. Look inside Application Support / aipose directory
    val directoryUrl = fileManager.URLForDirectory(
        directory = NSApplicationSupportDirectory,
        inDomain = NSUserDomainMask,
        appropriateForURL = null,
        create = false,
        error = null,
    )
    val folderPath = directoryUrl?.path
    if (folderPath != null) {
        val aiposePath = (folderPath as NSString).stringByAppendingPathComponent("aipose")

        val filename = if (storedPath.contains("/")) {
            (storedPath as NSString).lastPathComponent
        } else {
            storedPath
        }
        val fullPath = (aiposePath as NSString).stringByAppendingPathComponent(filename)
        if (fileManager.fileExistsAtPath(fullPath)) {
            return fullPath
        }
    }

    // 5. Fallback for non-blank stored paths
    return if (storedPath.startsWith("/")) storedPath else null
}