package com.aipose.data

import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * WI-03: atomic + recoverable photo deletion integration coverage (Maintainer
 * contract 2026-08-19 / BR-001 / FEAT-002 E). Covers: success removes row +
 * owned imagePath; owned-file failure restores metadata and rethrows; missing
 * owned files are idempotent; last-reference cascade deletes the linked
 * PersonalPose + owned assets; shared Pose is retained when other Photo rows
 * still reference it; non-owned references never reach the filesystem.
 * E-GAL-DELETE evidence.
 */
class PhotoRepositoryDeletionTest {

    private fun clearDatabase(database: AiPoseDatabase) {
        database.photoQueries.getAllPhotos().executeAsList().forEach {
            database.photoQueries.deletePhoto(it.id)
        }
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

    private fun insertPhoto(
        database: AiPoseDatabase,
        imagePath: String = "/documents/photo.jpg",
        poseId: Long? = null,
        poseName: String = ""
    ): Long {
        database.photoQueries.insertPhoto(
            imagePath = imagePath,
            poseId = poseId,
            poseName = poseName,
            createdAt = "2026-01-01T00:00:00Z",
            isFavorite = 0
        )
        return database.photoQueries.getLatestPhoto().executeAsOne().id
    }

    private fun insertPose(
        database: AiPoseDatabase,
        name: String = "Linked Pose",
        imagePath: String = "/documents/pose.jpg",
        thumbnailPath: String? = "/documents/pose_thumb.jpg",
        originalImagePath: String? = "/documents/pose_orig.jpg"
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
    fun testDeletionSuccessRemovesRowAndOwnedImageFile() = runTest {
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val storage = TrackingStorage()
            val repository = PhotoRepository(database, storage)

            val photoId = insertPhoto(database)

            repository.deletePhoto(photoId)

            assertNull(database.photoQueries.getPhotoById(photoId).executeAsOneOrNull())
            assertEquals(0, database.photoQueries.getAllPhotos().executeAsList().size)
            assertEquals(listOf("/documents/photo.jpg"), storage.deleted)
        } finally {
            driver.close()
        }
    }

    @Test
    fun testDeletionFileFailureRestoresMetadataAndRethrows() = runTest {
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val storage = TrackingStorage()
            storage.deleteImpl = { path ->
                if (path == "/documents/photo.jpg") throw RuntimeException("Permission Denied")
                storage.deleted.add(path)
            }
            val repository = PhotoRepository(database, storage)

            val photoId = insertPhoto(database)

            assertFailsWith<RuntimeException> { repository.deletePhoto(photoId) }

            // Photo metadata is restored so the item stays usable; nothing was
            // deleted because the photo's own file fails first.
            val restored = database.photoQueries.getPhotoById(photoId).executeAsOneOrNull()
            assertTrue(restored != null)
            assertEquals("/documents/photo.jpg", restored!!.imagePath)
            assertTrue(storage.deleted.isEmpty())
        } finally {
            driver.close()
        }
    }

    @Test
    fun testDeletionMissingOwnedImageFileIsIdempotent() = runTest {
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val storage = TrackingStorage()
            storage.existsImpl = { path -> path != "/documents/photo.jpg" }
            val repository = PhotoRepository(database, storage)

            val photoId = insertPhoto(database)

            repository.deletePhoto(photoId) // must not throw

            assertNull(database.photoQueries.getPhotoById(photoId).executeAsOneOrNull())
            assertTrue(storage.deleted.isEmpty())
        } finally {
            driver.close()
        }
    }

    @Test
    fun testDeletionLastReferenceCascadesToLinkedPoseAndAssets() = runTest {
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val storage = TrackingStorage()
            val repository = PhotoRepository(database, storage)

            val poseId = insertPose(database)
            val photoId = insertPhoto(database, poseId = poseId, poseName = "Warrior")

            repository.deletePhoto(photoId)

            // Both metadata rows are gone; every owned file is removed exactly
            // once — pose assets in deletePose order, then the photo's image.
            assertNull(database.photoQueries.getPhotoById(photoId).executeAsOneOrNull())
            assertNull(database.poseQueries.getPoseById(poseId).executeAsOneOrNull())
            assertEquals(0, database.photoQueries.getAllPhotos().executeAsList().size)
            assertEquals(0, database.poseQueries.getAllPoses().executeAsList().size)
            assertEquals(
                listOf("/documents/pose_orig.jpg", "/documents/pose_thumb.jpg", "/documents/pose.jpg", "/documents/photo.jpg"),
                storage.deleted
            )
        } finally {
            driver.close()
        }
    }

    @Test
    fun testDeletionCascadeFileFailureRestoresPhotoAndPoseMetadata() = runTest {
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val storage = TrackingStorage()
            storage.deleteImpl = { path ->
                if (path == "/documents/pose_thumb.jpg") throw RuntimeException("Permission Denied")
                storage.deleted.add(path)
            }
            val repository = PhotoRepository(database, storage)

            val poseId = insertPose(database)
            val photoId = insertPhoto(database, poseId = poseId, poseName = "Warrior")

            assertFailsWith<RuntimeException> { repository.deletePhoto(photoId) }

            // Photo AND cascade-deleted Pose metadata are both restored; the
            // photo's own display asset survives the partial failure.
            val restoredPhoto = database.photoQueries.getPhotoById(photoId).executeAsOneOrNull()
            assertTrue(restoredPhoto != null)
            assertEquals(poseId, restoredPhoto!!.poseId)
            assertEquals("Warrior", restoredPhoto.poseName)
            assertTrue(database.poseQueries.getPoseById(poseId).executeAsOneOrNull() != null)
            // Only the files deleted before the failure are gone: pose_orig
            // was deleted, pose_thumb failed, pose.jpg and photo.jpg untouched.
            assertEquals(listOf("/documents/pose_orig.jpg"), storage.deleted)
        } finally {
            driver.close()
        }
    }

    @Test
    fun testDeletionNoCascadeWhenOtherPhotosStillReferencePoseId() = runTest {
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val storage = TrackingStorage()
            val repository = PhotoRepository(database, storage)

            val poseId = insertPose(database)
            val photo1 = insertPhoto(database, imagePath = "/documents/photo1.jpg", poseId = poseId, poseName = "Warrior")
            val photo2 = insertPhoto(database, imagePath = "/documents/photo2.jpg", poseId = poseId, poseName = "Warrior")

            repository.deletePhoto(photo1)

            // Only this Photo is removed; the shared Pose and its assets stay.
            assertNull(database.photoQueries.getPhotoById(photo1).executeAsOneOrNull())
            assertTrue(database.photoQueries.getPhotoById(photo2).executeAsOneOrNull() != null)
            assertTrue(database.poseQueries.getPoseById(poseId).executeAsOneOrNull() != null)
            assertEquals(listOf("/documents/photo1.jpg"), storage.deleted)
        } finally {
            driver.close()
        }
    }

    @Test
    fun testDeletionSkipsNonOwnedReferences() = runTest {
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val storage = TrackingStorage()
            val repository = PhotoRepository(database, storage)

            val photoId = insertPhoto(database, imagePath = "https://cdn.example.com/photo.jpg", poseId = null)

            repository.deletePhoto(photoId)

            assertNull(database.photoQueries.getPhotoById(photoId).executeAsOneOrNull())
            assertTrue(storage.deleted.isEmpty())
        } finally {
            driver.close()
        }
    }

    @Test
    fun testDeletionLastReferenceCascadeSkipsNonOwnedPoseAssets() = runTest {
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val storage = TrackingStorage()
            val repository = PhotoRepository(database, storage)

            val poseId = insertPose(
                database,
                imagePath = "/documents/pose.jpg",
                thumbnailPath = "https://cdn.example.com/pose_thumb.png",
                originalImagePath = "/documents/pose_orig.jpg"
            )
            val photoId = insertPhoto(database, poseId = poseId, poseName = "Warrior")

            repository.deletePhoto(photoId)

            // Both rows gone; remote thumbnail never reaches the filesystem.
            assertNull(database.photoQueries.getPhotoById(photoId).executeAsOneOrNull())
            assertNull(database.poseQueries.getPoseById(poseId).executeAsOneOrNull())
            assertEquals(
                listOf("/documents/pose_orig.jpg", "/documents/pose.jpg", "/documents/photo.jpg"),
                storage.deleted
            )
        } finally {
            driver.close()
        }
    }
}