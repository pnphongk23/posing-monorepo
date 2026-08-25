package com.aipose.ui.components

import platform.Foundation.NSCachesDirectory
import platform.Foundation.NSSearchPathForDirectoriesInDomains
import platform.Foundation.NSTemporaryDirectory
import platform.Foundation.NSUserDomainMask

/**
 * NSCachesDirectory on iOS, namespaced under this app so Coil's DiskCache stays
 * sandbox-scoped and is cleaned up as the OS reclaims space.
 */
actual fun communityDiskCacheDirectory(): String {
    val caches = NSSearchPathForDirectoriesInDomains(
        NSCachesDirectory,
        NSUserDomainMask,
        true
    )?.firstOrNull() as? String
    val base = caches ?: NSTemporaryDirectory()
    return "$base/coil-community"
}