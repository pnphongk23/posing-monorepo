package com.aipose.data

import app.cash.sqldelight.coroutines.asFlow
import app.cash.sqldelight.coroutines.mapToList
import com.aipose.Photo
import com.aipose.Pose
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow

class PhotoRepository(
    private val database: AiPoseDatabase,
    private val storage: PoseStorage = getPlatformPoseStorage(),
) {
    private val queries = database.photoQueries

    /** Stores the captured original locally, before any extraction or Pose exists. */
    fun insertCapturedPhoto(imagePath: String): Long {
        queries.insertPhoto(
            imagePath = imagePath,
            poseId = null,
            poseName = "",
            createdAt = currentTimestampString(),
            isFavorite = 0,
        )
        return queries.getLatestPhoto().executeAsOne().id
    }

    fun getLatestPhotoPath(): String? = queries.getLatestPhoto().executeAsOneOrNull()?.imagePath

    fun getAllPhotos(): Flow<List<Photo>> = queries
        .getAllPhotos()
        .asFlow()
        .mapToList(Dispatchers.Default)

    suspend fun deletePhoto(id: Long) {
        val photo = queries.getPhotoById(id).executeAsOneOrNull()
            ?: throw NoSuchElementException("Photo with ID $id not found")

        val poseId = photo.poseId
        val cascadePose: Pose? = poseId?.let {
            val refsAfterDelete = queries.getPhotosByPoseId(it).executeAsList().size - 1
            if (refsAfterDelete <= 0) database.poseQueries.getPoseById(it).executeAsOneOrNull() else null
        }

        queries.deletePhoto(id)
        if (cascadePose != null) database.poseQueries.deletePose(cascadePose.poseId)

        try {
            if (cascadePose != null) {
                deleteOwnedFile(cascadePose.originalPath)
                deleteOwnedFile(cascadePose.skeletonPath)
                deleteOwnedFile(cascadePose.thumbnailPath)
            }
            deleteOwnedFile(photo.imagePath)
        } catch (e: Exception) {
            restoreMetadata(photo, cascadePose)
            throw RuntimeException("Deletion failed: ${e.message}", e)
        }
    }

    suspend fun toggleFavorite(id: Long) = queries.toggleFavorite(id)

    private fun deleteOwnedFile(path: String?) {
        if (path.isNullOrBlank() || !storage.isOwned(path)) return
        if (storage.exists(path)) storage.delete(path)
    }

    private fun restoreMetadata(photo: Photo, pose: Pose?) {
        try {
            if (pose != null) {
                database.poseQueries.insertPoseWithId(
                    poseId = pose.poseId,
                    ownerAccountId = pose.ownerAccountId,
                    name = pose.name,
                    description = pose.description,
                    tags = pose.tags,
                    difficulty = pose.difficulty,
                    bodyParts = pose.bodyParts,
                    status = pose.status,
                    originalPath = pose.originalPath,
                    skeletonPath = pose.skeletonPath,
                    thumbnailPath = pose.thumbnailPath,
                    currentJobId = pose.currentJobId,
                    createdAt = pose.createdAt,
                    updatedAt = pose.updatedAt
                )
            }
            queries.insertPhotoWithId(
                id = photo.id,
                imagePath = photo.imagePath,
                poseId = photo.poseId,
                poseName = photo.poseName,
                createdAt = photo.createdAt,
                isFavorite = photo.isFavorite
            )
        } catch (dbEx: Exception) {
            throw IllegalStateException("Deletion failed and database restoration failed: ${dbEx.message}", dbEx)
        }
    }

    private fun currentTimestampString(): String = kotlin.system.getTimeMillis().toString()
}
