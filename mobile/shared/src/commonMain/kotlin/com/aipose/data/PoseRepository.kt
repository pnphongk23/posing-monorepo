package com.aipose.data

import app.cash.sqldelight.coroutines.asFlow
import app.cash.sqldelight.coroutines.mapToList
import app.cash.sqldelight.coroutines.mapToOneOrNull
import com.aipose.Pose
import com.aipose.data.remote.PaginatedResult
import com.aipose.data.remote.PoseApiService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.datetime.Clock
import kotlin.random.Random

private const val LOCAL_OWNER_ACCOUNT_ID = "00000000-0000-0000-0000-000000000001"

private fun newPoseId(): String {
    val bytes = ByteArray(16).also { Random.nextBytes(it) }
    bytes[6] = ((bytes[6].toInt() and 0x0f) or 0x40).toByte()
    bytes[8] = ((bytes[8].toInt() and 0x3f) or 0x80).toByte()
    val hexChars = "0123456789abcdef"
    val hex = buildString(32) {
        bytes.forEach { byte ->
            val value = byte.toInt() and 0xff
            append(hexChars[value ushr 4])
            append(hexChars[value and 0x0f])
        }
    }
    return "${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}"
}

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

    fun getPoseById(poseId: String): Flow<Pose?> = queries
        .getPoseById(poseId)
        .asFlow()
        .mapToOneOrNull(Dispatchers.Default)

    suspend fun deletePose(poseId: String) {
        val pose = queries.getPoseById(poseId).executeAsOneOrNull()
            ?: throw NoSuchElementException("Pose $poseId not found")
        queries.deletePose(poseId)
        try {
            deleteOwnedFile(pose.originalPath)
            deleteOwnedFile(pose.skeletonPath)
            deleteOwnedFile(pose.thumbnailPath)
        } catch (e: Exception) {
            restorePose(pose)
            throw RuntimeException("Deletion failed: ${e.message}", e)
        }
    }

    private fun deleteOwnedFile(path: String?) {
        if (path.isNullOrBlank() || !storage.isOwned(path)) return
        if (storage.exists(path)) storage.delete(path)
    }

    private fun restorePose(pose: Pose) {
        try {
            queries.insertPoseWithId(
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
        } catch (dbEx: Exception) {
            throw IllegalStateException("Deletion failed and database restoration failed: ${dbEx.message}", dbEx)
        }
    }

    /** Creates the canonical Pose only after extraction has succeeded. */
    suspend fun createPoseAfterExtraction(
        name: String,
        originalPath: String,
        skeletonPath: String,
        thumbnailPath: String,
        ownerAccountId: String = LOCAL_OWNER_ACCOUNT_ID
    ): String {
        val now = Clock.System.now().toString()
        val poseId = newPoseId()
        queries.insertPose(
            poseId = poseId,
            ownerAccountId = ownerAccountId,
            name = name,
            description = null,
            tags = "[]",
            difficulty = null,
            bodyParts = "[]",
            status = "local",
            originalPath = originalPath,
            skeletonPath = skeletonPath,
            thumbnailPath = thumbnailPath,
            currentJobId = null,
            createdAt = now,
            updatedAt = now
        )
        return poseId
    }

    suspend fun getCommunityPoses(page: Int = 1, pageSize: Int = 20) =
        requireNotNull(apiService) { "PoseApiService must be provided to use getCommunityPoses" }
            .getCommunityPoses(page = page, limit = pageSize)

    suspend fun getCommunityPoseDetail(poseId: String) =
        requireNotNull(apiService) { "PoseApiService must be provided to use getCommunityPoseDetail" }
            .getCommunityPoseDetail(poseId)
}
