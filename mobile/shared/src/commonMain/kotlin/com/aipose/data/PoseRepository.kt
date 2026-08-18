package com.aipose.data

import app.cash.sqldelight.coroutines.asFlow
import app.cash.sqldelight.coroutines.mapToList
import app.cash.sqldelight.coroutines.mapToOneOrNull
import com.aipose.Pose
import com.aipose.data.remote.CommunityPose
import com.aipose.data.remote.PaginatedResult
import com.aipose.data.remote.PoseApiService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.datetime.Clock

class PoseRepository(
    private val database: AiPoseDatabase,
    private val apiService: PoseApiService? = null,
    private val storage: PoseStorage = getPlatformPoseStorage()
) {
    private val queries = database.poseQueries

    fun getMyPoses(): Flow<List<Pose>> = queries
        .getMyPoses()
        .asFlow()
        .mapToList(Dispatchers.Default)

    fun getPoseById(id: Long): Flow<Pose?> = queries
        .getPoseById(id)
        .asFlow()
        .mapToOneOrNull(Dispatchers.Default)

    /**
     * Deletes the personal pose's metadata and every owned local asset exactly
     * once (FEAT-003 FR-006). Remote URLs and embedded data URIs are never
     * deleted, no server delete request is made, and community state is never
     * mutated (BR-001). On any owned-file failure the metadata row is restored
     * so the item stays usable and the failure is reported (FEAT-003 E3); a
     * reported success leaves neither metadata nor owned files.
     */
    suspend fun deletePose(id: Long) {
        val pose = queries.getPoseById(id).executeAsOneOrNull()
            ?: throw NoSuchElementException("Pose with ID $id not found")

        // 1. Delete database metadata first
        queries.deletePose(id)

        // 2. Delete every owned local asset field exactly once. The primary
        // image is deleted last so a partial failure keeps the main display
        // asset, and the file that failed to delete always survives for retry.
        try {
            deleteOwnedFile(pose.originalImagePath)
            deleteOwnedFile(pose.thumbnailPath)
            deleteOwnedFile(pose.imagePath)
        } catch (e: Exception) {
            // 3. Compensation: restore metadata if any owned-file delete fails
            restorePose(pose)
            throw RuntimeException("Deletion failed: ${e.message}", e)
        }
    }

    /** Deletes an owned local file if present; data URIs and remote URLs are skipped. */
    private fun deleteOwnedFile(path: String?) {
        if (path.isNullOrBlank()) return
        if (!storage.isOwned(path)) return
        if (storage.exists(path)) {
            storage.delete(path)
        }
    }

    /** Restores the metadata row after a partial local deletion failure. */
    private fun restorePose(pose: Pose) {
        try {
            queries.insertPoseWithId(
                id = pose.id,
                name = pose.name,
                imagePath = pose.imagePath,
                thumbnailPath = pose.thumbnailPath,
                originalImagePath = pose.originalImagePath,
                createdAt = pose.createdAt,
                isMine = pose.isMine,
                likes = pose.likes
            )
        } catch (dbEx: Exception) {
            throw IllegalStateException("Deletion failed and database restoration failed: ${dbEx.message}", dbEx)
        }
    }

    suspend fun insertPose(name: String, imagePath: String, isMine: Boolean = true) {
        queries.insertPose(
            name = name,
            imagePath = imagePath,
            thumbnailPath = null,
            originalImagePath = null,
            createdAt = Clock.System.now().toString(),
            isMine = if (isMine) 1L else 0L,
            likes = 0L
        )
    }

    suspend fun getCommunityPoses(
        page: Int = 1,
        pageSize: Int = 20
    ): PaginatedResult<CommunityPose> {
        val service = requireNotNull(apiService) { "PoseApiService must be provided to use getCommunityPoses" }
        return service.getCommunityPoses(page = page, limit = pageSize)
    }

    suspend fun getCommunityPoseDetail(id: String): CommunityPose {
        val service = requireNotNull(apiService) { "PoseApiService must be provided to use getCommunityPoseDetail" }
        return service.getCommunityPoseDetail(id)
    }
}
