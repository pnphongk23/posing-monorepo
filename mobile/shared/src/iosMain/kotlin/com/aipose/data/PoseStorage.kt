package com.aipose.data

import kotlinx.cinterop.ExperimentalForeignApi
import platform.Foundation.NSApplicationSupportDirectory
import platform.Foundation.NSFileManager
import platform.Foundation.NSString
import platform.Foundation.NSUserDomainMask
import platform.Foundation.stringByAppendingPathComponent

@OptIn(ExperimentalForeignApi::class)
class IosPoseStorage : PoseStorage {

    override fun delete(path: String) {
        // Ownership/canonical-path checks always precede filesystem mutation.
        val target = canonicalOwnedPath(path) ?: return
        val success = NSFileManager.defaultManager.removeItemAtPath(target, error = null)
        if (!success) {
            throw RuntimeException("Failed to delete local file at: $target")
        }
    }

    override fun exists(path: String): Boolean {
        val target = canonicalOwnedPath(path) ?: return false
        return NSFileManager.defaultManager.fileExistsAtPath(target)
    }

    override fun isOwned(path: String): Boolean {
        if (path.isBlank()) return false
        // Remote URLs and embedded data URIs are never owned (BR-001).
        if (path.startsWith("http://") || path.startsWith("https://") || path.startsWith("data:")) {
            return false
        }
        // Path traversal and protocol separators are never owned (WI-05 risk 3):
        // deletion must never target `..`-containing or scheme-like paths.
        if (path.contains("..") || path.contains("//")) {
            return false
        }
        return true
    }

    /**
     * Resolves the canonical app-owned path before any filesystem operation.
     * Bare filenames are resolved against the same base directory the readers
     * use (Application Support/aipose) so deletion cannot target a different
     * directory than the one the pose image is read from.
     */
    private fun canonicalOwnedPath(path: String): String? {
        if (!isOwned(path)) return null
        if (path.startsWith("/")) return path
        val base = ownedBasePath() ?: return null
        return (base as NSString).stringByAppendingPathComponent(path)
    }

    private fun ownedBasePath(): String? {
        val directoryUrl = NSFileManager.defaultManager.URLForDirectory(
            directory = NSApplicationSupportDirectory,
            inDomain = NSUserDomainMask,
            appropriateForURL = null,
            create = false,
            error = null,
        ) ?: return null
        val folderPath = directoryUrl.path ?: return null
        return (folderPath as NSString).stringByAppendingPathComponent("aipose")
    }
}

actual fun getPlatformPoseStorage(): PoseStorage = IosPoseStorage()
