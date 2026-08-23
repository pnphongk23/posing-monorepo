package com.aipose.data

/**
 * Storage boundary for the local assets of local poses.
 *
 * Ownership contract (FEAT-003 FR-006 / BR-001): a path is *owned* only when it
 * is an app-local file reference. Remote URLs and embedded data URIs are never
 * owned and must never reach the filesystem. Ownership and canonical-path checks
 * must precede any deletion; paths containing `..` (traversal) or `//`
 * (protocol separators) are never owned.
 */
interface PoseStorage {
    /** Deletes the owned local file at [path]; a no-op for non-owned references. */
    fun delete(path: String)

    /** True when the owned local file at [path] exists; false for non-owned references. */
    fun exists(path: String): Boolean

    /** True when [path] is an app-owned local file reference, not remote or embedded. */
    fun isOwned(path: String): Boolean
}

expect fun getPlatformPoseStorage(): PoseStorage
