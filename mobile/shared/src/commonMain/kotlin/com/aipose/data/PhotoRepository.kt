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

    fun insertCapturedPhoto(imagePath: String): Long {
        val createdAt = currentTimestampString()
        queries.insertPhoto(
            imagePath = imagePath,
            poseId = null,
            poseName = "",
            createdAt = createdAt,
            isFavorite = 0,
        )
        return queries.getLatestPhoto().executeAsOne().id
    }

    fun getLatestPhotoPath(): String? {
        return queries.getLatestPhoto().executeAsOneOrNull()?.imagePath
    }

    fun getAllPhotos(): Flow<List<Photo>> = queries
        .getAllPhotos()
        .asFlow()
        .mapToList(Dispatchers.Default)

    /**
     * WI-03: atomic + recoverable photo deletion (Maintainer contract
     * 2026-08-19 / BR-001 / FEAT-002 E). Always removes the Photo row and the
     * owned `imagePath` file. When `Photo.poseId != null` and this Photo is the
     * **last reference** to the linked PersonalPose (`getPhotosByPoseId`
     * count would become 0), the Pose row and its owned assets
     * (`originalImagePath`, `thumbnailPath`, `imagePath`) are also deleted
     * using the `PoseRepository.deletePose` pattern. If other Photo rows still
     * reference the same `poseId`, only this Photo is deleted — the shared Pose
     * and its assets are untouched. FK `ON DELETE SET NULL` (`Photo.sq:5`) is
     * never relied upon. On any owned-file failure the metadata rows are
     * restored (Photo, and Pose if it was cascade-deleted) and the failure is
     * rethrown so the UI reports failure, never success; already-missing owned
     * files are idempotent (not an error).
     */
    suspend fun deletePhoto(id: Long) {
        val photo = queries.getPhotoById(id).executeAsOneOrNull()
            ?: throw NoSuchElementException("Photo with ID $id not found")

        // Decide the cascade BEFORE deleting this row: cascade only when no
        // other Photo rows reference the same poseId after this delete.
        val poseId = photo.poseId
        val cascadePose: Pose? = if (poseId != null) {
            val refsAfterDelete = queries.getPhotosByPoseId(poseId).executeAsList().size - 1
            if (refsAfterDelete <= 0) {
                database.poseQueries.getPoseById(poseId).executeAsOneOrNull()
            } else {
                null
            }
        } else {
            null
        }

        // 1. Delete database metadata first (metadata-first, deletePose pattern).
        queries.deletePhoto(id)

        // 2. Cascade: delete the linked PersonalPose metadata first.
        if (cascadePose != null) {
            database.poseQueries.deletePose(cascadePose.id)
        }

        // 3. Delete every owned local file exactly once. The linked pose's
        // assets follow the deletePose order (primary image last); the photo's
        // own image is deleted last so a partial failure keeps the gallery's
        // main display asset, and the file that failed always survives retry.
        try {
            if (cascadePose != null) {
                deleteOwnedFile(cascadePose.originalImagePath)
                deleteOwnedFile(cascadePose.thumbnailPath)
                deleteOwnedFile(cascadePose.imagePath)
            }
            deleteOwnedFile(photo.imagePath)
        } catch (e: Exception) {
            // 4. Compensation: restore metadata (pose first so the restored
            // Photo row's poseId can reference it), then rethrow — a reported
            // success must never leave owned files (BR-001).
            restoreMetadata(photo, cascadePose)
            throw RuntimeException("Deletion failed: ${e.message}", e)
        }
    }

    suspend fun toggleFavorite(id: Long) {
        queries.toggleFavorite(id)
    }

    /** Deletes an owned local file if present; data URIs and remote URLs are skipped. */
    private fun deleteOwnedFile(path: String?) {
        if (path.isNullOrBlank()) return
        if (!storage.isOwned(path)) return
        if (storage.exists(path)) {
            storage.delete(path)
        }
    }

    /** Restores the Photo row (and, if cascade-deleted, the Pose row) after a partial failure. */
    private fun restoreMetadata(photo: Photo, pose: Pose?) {
        try {
            if (pose != null) {
                database.poseQueries.insertPoseWithId(
                    id = pose.id,
                    name = pose.name,
                    imagePath = pose.imagePath,
                    thumbnailPath = pose.thumbnailPath,
                    originalImagePath = pose.originalImagePath,
                    createdAt = pose.createdAt,
                    isMine = pose.isMine,
                    likes = pose.likes
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

    private fun currentTimestampString(): String {
        return kotlin.system.getTimeMillis().toString()
    }
}