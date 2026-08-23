package com.aipose.data

import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class PoseRepositoryDeletionTest {
    private val owner = "00000000-0000-0000-0000-000000000001"

    private fun clearDatabase(database: AiPoseDatabase) {
        database.poseQueries.getAllPoses().executeAsList().forEach { database.poseQueries.deletePose(it.poseId) }
    }

    private class TrackingStorage : PoseStorage {
        val deleted = mutableListOf<String>()
        var existsImpl: (String) -> Boolean = { true }
        var deleteImpl: (String) -> Unit = { deleted += it }
        override fun delete(path: String) = deleteImpl(path)
        override fun exists(path: String) = existsImpl(path)
        override fun isOwned(path: String) = path.startsWith("/documents/") && !path.contains("..") && !path.contains("//")
    }

    private fun insertPose(database: AiPoseDatabase, original: String = "/documents/original.jpg", skeleton: String = "/documents/skeleton.jpg", thumbnail: String = "/documents/thumb.jpg"): String {
        val id = "11111111-1111-4111-8111-111111111111"
        database.poseQueries.insertPose(
            poseId = id, ownerAccountId = owner, name = "Pose", description = null,
            tags = "[]", difficulty = null, bodyParts = "[]", status = "local",
            originalPath = original, skeletonPath = skeleton, thumbnailPath = thumbnail,
            currentJobId = null, createdAt = "2026-01-01T00:00:00Z", updatedAt = "2026-01-01T00:00:00Z"
        )
        return id
    }

    @Test
    fun deletionRemovesAllOwnedCanonicalMedia() = runTest {
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver); clearDatabase(database)
            val storage = TrackingStorage(); val repository = PoseRepository(database, null, storage)
            val id = insertPose(database)
            repository.deletePose(id)
            assertTrue(database.poseQueries.getAllPoses().executeAsList().isEmpty())
            assertEquals(listOf("/documents/original.jpg", "/documents/skeleton.jpg", "/documents/thumb.jpg"), storage.deleted)
        } finally { driver.close() }
    }

    @Test
    fun deletionSkipsNonOwnedMedia() = runTest {
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver); clearDatabase(database)
            val storage = TrackingStorage(); val repository = PoseRepository(database, null, storage)
            val id = insertPose(database, skeleton = "data:image/png;base64,abc", thumbnail = "https://cdn.example/thumb.png")
            repository.deletePose(id)
            assertEquals(listOf("/documents/original.jpg"), storage.deleted)
        } finally { driver.close() }
    }

    @Test
    fun failedDeletionRestoresCanonicalPose() = runTest {
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver); clearDatabase(database)
            val storage = TrackingStorage(); storage.deleteImpl = { if (it.endsWith("skeleton.jpg")) error("denied") else storage.deleted += it }
            val repository = PoseRepository(database, null, storage); val id = insertPose(database)
            assertFailsWith<RuntimeException> { repository.deletePose(id) }
            val restored = database.poseQueries.getPoseById(id).executeAsOneOrNull()
            assertEquals("/documents/original.jpg", restored?.originalPath)
            assertEquals("/documents/skeleton.jpg", restored?.skeletonPath)
        } finally { driver.close() }
    }
}

class IosPoseStorageOwnershipTest {
    private val storage = IosPoseStorage()
    @Test fun rejectsRemoteAndEmbeddedReferences() {
        assertFalse(storage.isOwned("http://example.com/a.jpg")); assertFalse(storage.isOwned("data:image/png;base64,abc"))
    }
    @Test fun rejectsTraversalAndProtocolSeparators() {
        assertFalse(storage.isOwned("/documents/../etc/passwd")); assertFalse(storage.isOwned("/documents/a//b.jpg"))
    }
}
