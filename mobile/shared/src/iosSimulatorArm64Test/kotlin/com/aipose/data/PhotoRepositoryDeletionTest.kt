package com.aipose.data

import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue

class PhotoRepositoryDeletionTest {
    private val owner = "00000000-0000-0000-0000-000000000001"
    private fun clear(db: AiPoseDatabase) {
        db.photoQueries.getAllPhotos().executeAsList().forEach { db.photoQueries.deletePhoto(it.id) }
        db.poseQueries.getAllPoses().executeAsList().forEach { db.poseQueries.deletePose(it.poseId) }
    }
    private class Storage : PoseStorage {
        val deleted = mutableListOf<String>(); val missing = mutableSetOf<String>(); var fail = false
        override fun delete(path: String) { if (fail) error("denied"); deleted += path }
        override fun exists(path: String) = path !in missing
        override fun isOwned(path: String) = path.startsWith("/documents/")
    }
    private fun pose(db: AiPoseDatabase): String {
        val id = "22222222-2222-4222-8222-222222222222"
        db.poseQueries.insertPose(id, owner, "Pose", null, "[]", null, "[]", "local", "/documents/original.jpg", "/documents/skeleton.jpg", "/documents/thumb.jpg", null, "now", "now")
        return id
    }
    private fun photo(db: AiPoseDatabase, poseId: String? = null, imagePath: String = "/documents/photo.jpg"): Long {
        db.photoQueries.insertPhoto(imagePath, poseId, "Pose", "now", 0)
        return db.photoQueries.getLatestPhoto().executeAsOne().id
    }
    @Test fun deletesPhotoAndLastPose() = runTest {
        val driver = DatabaseDriverFactory().createDriver(); try {
            val db = AiPoseDatabase(driver); clear(db); val storage = Storage(); val repo = PhotoRepository(db, storage)
            val poseId = pose(db); val photoId = photo(db, poseId); repo.deletePhoto(photoId)
            assertNull(db.photoQueries.getPhotoById(photoId).executeAsOneOrNull()); assertNull(db.poseQueries.getPoseById(poseId).executeAsOneOrNull())
            assertEquals(listOf("/documents/original.jpg", "/documents/skeleton.jpg", "/documents/thumb.jpg", "/documents/photo.jpg"), storage.deleted)
        } finally { driver.close() }
    }
    @Test fun deletingPhotoWithMissingFileIsIdempotent() = runTest {
        val driver = DatabaseDriverFactory().createDriver(); try {
            val db = AiPoseDatabase(driver); clear(db); val storage = Storage(); val repo = PhotoRepository(db, storage)
            val photoId = photo(db, imagePath = "/documents/missing.jpg")
            storage.missing += "/documents/missing.jpg"

            repo.deletePhoto(photoId)

            assertNull(db.photoQueries.getPhotoById(photoId).executeAsOneOrNull())
            assertTrue(storage.deleted.isEmpty())
        } finally { driver.close() }
    }
    @Test fun deletingOnePhotoRetainsPoseReferencedByAnotherPhoto() = runTest {
        val driver = DatabaseDriverFactory().createDriver(); try {
            val db = AiPoseDatabase(driver); clear(db); val storage = Storage(); val repo = PhotoRepository(db, storage)
            val poseId = pose(db)
            val firstPhotoId = photo(db, poseId, "/documents/first.jpg")
            val secondPhotoId = photo(db, poseId, "/documents/second.jpg")

            repo.deletePhoto(firstPhotoId)

            assertNull(db.photoQueries.getPhotoById(firstPhotoId).executeAsOneOrNull())
            assertTrue(db.photoQueries.getPhotoById(secondPhotoId).executeAsOneOrNull() != null)
            assertTrue(db.poseQueries.getPoseById(poseId).executeAsOneOrNull() != null)
            assertEquals(listOf("/documents/first.jpg"), storage.deleted)
        } finally { driver.close() }
    }
    @Test fun deletingPhotoDoesNotAffectUnrelatedNonOwnedPoseReference() = runTest {
        val driver = DatabaseDriverFactory().createDriver(); try {
            val db = AiPoseDatabase(driver); clear(db); val storage = Storage(); val repo = PhotoRepository(db, storage)
            val unrelatedPoseId = pose(db)
            val photoId = photo(db, imagePath = "/external/photo.jpg")

            repo.deletePhoto(photoId)

            assertNull(db.photoQueries.getPhotoById(photoId).executeAsOneOrNull())
            assertTrue(db.poseQueries.getPoseById(unrelatedPoseId).executeAsOneOrNull() != null)
            assertTrue(storage.deleted.isEmpty())
        } finally { driver.close() }
    }
    @Test fun restoresPhotoWhenFileDeletionFails() = runTest {
        val driver = DatabaseDriverFactory().createDriver(); try {
            val db = AiPoseDatabase(driver); clear(db); val storage = Storage(); val repo = PhotoRepository(db, storage); val id = photo(db)
            storage.fail = true; assertFailsWith<RuntimeException> { repo.deletePhoto(id) }; assertTrue(db.photoQueries.getPhotoById(id).executeAsOneOrNull() != null)
        } finally { driver.close() }
    }
}
