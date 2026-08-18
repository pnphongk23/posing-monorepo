package com.aipose.data

import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * WI-05: repository + storage deletion coverage for every owned local asset
 * field (imagePath, thumbnailPath, originalImagePath), mixed owned/embedded
 * references, idempotent missing files, partial-file-failure compensation,
 * and iOS ownership/canonical-path checks. No server request is involved and
 * community state is never touched (BR-001).
 */
class PoseRepositoryDeletionTest {

    private fun clearDatabase(database: AiPoseDatabase) {
        database.poseQueries.getAllPoses().executeAsList().forEach {
            database.poseQueries.deletePose(it.id)
        }
    }

    private class TrackingStorage : PoseStorage {
        val deleted = mutableListOf<String>()
        val existed = mutableListOf<String>()
        var isOwnedImpl: (String) -> Boolean = { path ->
            path.isNotBlank() &&
                !path.startsWith("http://") && !path.startsWith("https://") && !path.startsWith("data:") &&
                !path.contains("..") && !path.contains("//")
        }
        var existsImpl: (String) -> Boolean = { true }
        var deleteImpl: (String) -> Unit = { deleted.add(it) }

        override fun delete(path: String) = deleteImpl(path)
        override fun exists(path: String): Boolean {
            existed.add(path)
            return existsImpl(path)
        }
        override fun isOwned(path: String): Boolean = isOwnedImpl(path)
    }

    private fun insertFullPose(
        database: AiPoseDatabase,
        name: String = "Full Pose",
        imagePath: String = "/documents/full.jpg",
        thumbnailPath: String? = "/documents/full_thumb.jpg",
        originalImagePath: String? = "/documents/full_orig.jpg"
    ): Long {
        database.poseQueries.insertPose(
            name = name,
            imagePath = imagePath,
            thumbnailPath = thumbnailPath,
            originalImagePath = originalImagePath,
            createdAt = "2026-01-01T00:00:00Z",
            isMine = 1L,
            likes = 0L
        )
        return database.poseQueries.getAllPoses().executeAsOne().id
    }

    @Test
    fun testDeletionRemovesEveryOwnedAssetFieldExactlyOnce() = runTest {
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val storage = TrackingStorage()
            val repository = PoseRepository(database, null, storage)

            val id = insertFullPose(database)

            repository.deletePose(id)

            assertEquals(0, database.poseQueries.getAllPoses().executeAsList().size)
            // The primary image is deleted last; every owned file is removed exactly once.
            assertEquals(
                listOf("/documents/full_orig.jpg", "/documents/full_thumb.jpg", "/documents/full.jpg"),
                storage.deleted
            )
        } finally {
            driver.close()
        }
    }

    @Test
    fun testDeletionSkipsEmbeddedDataAndRemoteUrls() = runTest {
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val storage = TrackingStorage()
            val repository = PoseRepository(database, null, storage)

            val id = insertFullPose(
                database,
                imagePath = "/documents/mixed.jpg",
                thumbnailPath = "data:image/png;base64,aaaa",
                originalImagePath = "https://cdn.example.com/orig.png"
            )

            repository.deletePose(id)

            assertEquals(0, database.poseQueries.getAllPoses().executeAsList().size)
            assertEquals(listOf("/documents/mixed.jpg"), storage.deleted)
        } finally {
            driver.close()
        }
    }

    @Test
    fun testDeletionMissingOwnedFilesIsIdempotent() = runTest {
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val storage = TrackingStorage()
            storage.existsImpl = { path -> path != "/documents/full_thumb.jpg" }
            val repository = PoseRepository(database, null, storage)

            val id = insertFullPose(database)

            repository.deletePose(id) // must not throw

            assertEquals(0, database.poseQueries.getAllPoses().executeAsList().size)
            assertEquals(
                listOf("/documents/full_orig.jpg", "/documents/full.jpg"),
                storage.deleted
            )
        } finally {
            driver.close()
        }
    }

    @Test
    fun testDeletionPartialFileFailureRestoresUsableMetadata() = runTest {
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val storage = TrackingStorage()
            storage.deleteImpl = { path ->
                if (path == "/documents/full_thumb.jpg") throw RuntimeException("Permission Denied")
                storage.deleted.add(path)
            }
            val repository = PoseRepository(database, null, storage)

            val id = insertFullPose(database)

            assertFailsWith<RuntimeException> { repository.deletePose(id) }

            // Metadata is restored with every field so the item stays usable (E3).
            val restored = database.poseQueries.getPoseById(id).executeAsOneOrNull()
            assertTrue(restored != null)
            assertEquals("/documents/full.jpg", restored!!.imagePath)
            assertEquals("/documents/full_thumb.jpg", restored!!.thumbnailPath)
            assertEquals("/documents/full_orig.jpg", restored!!.originalImagePath)
            // Only the files deleted before the failure are gone; the failed
            // thumbnail and the untouched primary image still exist.
            assertEquals(listOf("/documents/full_orig.jpg"), storage.deleted)
        } finally {
            driver.close()
        }
    }
}

/**
 * WI-05 risk 3: ownership/canonical-path checks must precede deletion. Remote
 * URLs, embedded data URIs, blank values, path traversal (`..`) and protocol
 * separators (`//`) are never owned and never reach the filesystem.
 */
class IosPoseStorageOwnershipTest {

    private val storage = IosPoseStorage()

    @Test
    fun testIsOwnedRejectsRemoteAndEmbeddedReferences() {
        assertFalse(storage.isOwned("http://example.com/a.jpg"))
        assertFalse(storage.isOwned("https://example.com/a.jpg"))
        assertFalse(storage.isOwned("data:image/png;base64,abc"))
    }

    @Test
    fun testIsOwnedRejectsPathTraversalAndProtocolSeparators() {
        assertFalse(storage.isOwned(""))
        assertFalse(storage.isOwned("/documents/../etc/passwd"))
        assertFalse(storage.isOwned("../escape.jpg"))
        assertFalse(storage.isOwned("/documents/a//b.jpg"))
    }

    @Test
    fun testIsOwnedAcceptsLocalFilenamesAndAbsolutePaths() {
        assertTrue(storage.isOwned("/documents/pose_a.jpg"))
        assertTrue(storage.isOwned("pose_a.jpg"))
    }

    @Test
    fun testDeleteAndExistsShortCircuitBeforeFilesystemForUnowned() {
        // Unowned references must never reach the filesystem (no throw, no lookup).
        storage.delete("http://example.com/a.jpg")
        storage.delete("data:image/png;base64,abc")
        storage.delete("/documents/../etc/passwd")
        assertFalse(storage.exists("https://example.com/a.jpg"))
        assertFalse(storage.exists("data:image/png;base64,abc"))
    }
}
