package com.aipose.ui.components

/**
 * Absolute path to the platform cache directory used to back Coil's bounded
 * [coil3.disk.DiskCache] for Community media. Kept off the library so the
 * singleton ImageLoader is the single owner of image caching (no per-card
 * fetch-and-stage to a local path).
 */
expect fun communityDiskCacheDirectory(): String