package com.aipose.data.remote

import com.aipose.data.auth.SessionBoundary
import com.aipose.data.auth.SessionCredentials
import io.ktor.client.*
import io.ktor.client.call.*
import io.ktor.client.request.*
import io.ktor.client.request.forms.*
import io.ktor.client.statement.readBytes
import io.ktor.client.statement.*
import io.ktor.http.*
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonNames
import kotlinx.serialization.json.Json

val sharedJson = Json {
    ignoreUnknownKeys = true
    coerceInputValues = true
    encodeDefaults = true
    isLenient = true
}

@Serializable
data class ExtractPoseData(
    val imageBase64: String,
    val mimeType: String,
    val processingTimeMs: Long
)

@Serializable
data class PoseExtractionStartResponse(
    val success: Boolean,
    val data: PoseExtractionJob,
    val meta: PoseExtractionMeta? = null
)

@Serializable
data class PoseExtractionJob(
    val jobId: String,
    val status: String
)

@Serializable
data class PoseExtractionMeta(
    val pollUrl: String? = null
)

@Serializable
data class PoseExtractionJobStatus(
    val success: Boolean = true,
    val data: PoseExtractionJobData
)

@Serializable
data class PoseExtractionJobData(
    val jobId: String,
    val status: String,
    val result: ExtractPoseData? = null,
    val error: ApiErrorResponse? = null
)

/** Published-only DTO/view over the canonical Pose entity. */
@Serializable
data class CommunityPose(
    @SerialName("poseId") @JsonNames("id") val poseId: String = "",
    val name: String = "",
    @SerialName("skeletonUrl") @JsonNames("imagePath") val skeletonUrl: String = "",
    @SerialName("thumbnailUrl") @JsonNames("thumbnailPath") val thumbnailUrl: String = "",
    val difficulty: String? = null,
    val tags: List<String> = emptyList(),
    val description: String? = null,
    val bodyParts: List<String> = emptyList(),
    val status: String = "published",
    val uploadedAt: String? = null,
    val downloadCount: Int? = null
)

@Serializable
data class PaginationInfo(
    val page: Int,
    val limit: Int,
    val total: Int
)

@Serializable
data class PaginatedResult<T>(
    val data: List<T>,
    val pagination: PaginationInfo
)

@Serializable
data class ApiErrorEnvelope(
    val error: ApiErrorResponse? = null
)

@Serializable
data class ApiErrorResponse(
    val code: String? = null,
    val message: String? = null
)

@Serializable
data class RefreshRequest(
    val refreshToken: String,
)

@Serializable
data class RefreshResponse(
    val accessToken: String,
    val refreshToken: String,
)

private fun RefreshResponse.toCredentials() = SessionCredentials(
    accessToken = accessToken,
    refreshToken = refreshToken,
)

@Serializable
data class CommunityPoseDetailResponse(
    val data: CommunityPose
)

private fun mimeTypeFromFileName(fileName: String): String = when {
    fileName.endsWith(".png", ignoreCase = true) -> "image/png"
    fileName.endsWith(".webp", ignoreCase = true) -> "image/webp"
    fileName.endsWith(".gif", ignoreCase = true) -> "image/gif"
    else -> "image/jpeg"
}

class PoseApiService(
    private val httpClient: HttpClient,
    private val baseUrl: String,
    private val sessionBoundary: SessionBoundary? = null,
) {
    private suspend fun requestWithSession(request: suspend () -> HttpResponse): HttpResponse {
        val response = request()
        if (response.status.value != HttpStatusCode.Unauthorized.value || sessionBoundary == null) {
            return response
        }
        val refreshed = sessionBoundary.refresh(::refreshSession)
        if (!refreshed) return response
        val retry = request()
        if (retry.status.value == HttpStatusCode.Unauthorized.value) {
            sessionBoundary.clearForUnauthorized()
        }
        return retry
    }

    private suspend fun refreshSession(refreshToken: String): SessionCredentials? {
        return try {
            val response = httpClient.post("$baseUrl/api/auth/refresh") {
                contentType(ContentType.Application.Json)
                setBody(RefreshRequest(refreshToken))
            }
            if (response.status != HttpStatusCode.OK) return null
            response.body<RefreshResponse>().toCredentials()
        } catch (_: Exception) {
            null
        }
    }
    /**
     * Enqueues canonical async extraction. HTTP 202 means only that the job
     * started; no Pose exists until the caller polls the job to `succeeded`
     * and finalizes Pose creation with the returned jobId.
     */
    suspend fun startPoseExtraction(imageBytes: ByteArray, fileName: String): PoseExtractionStartResponse {
        val mimeType = mimeTypeFromFileName(fileName)
        val httpResponse: HttpResponse = requestWithSession { httpClient.submitFormWithBinaryData(
            url = "$baseUrl/api/extract-pose",
            formData = formData {
                append("image", imageBytes, Headers.build {
                    append(HttpHeaders.ContentType, mimeType)
                    append(HttpHeaders.ContentDisposition, "filename=$fileName")
                })
            }
        ) }
          if (httpResponse.status != HttpStatusCode.Accepted) {
            val errorEnvelope = try {
                httpResponse.body<ApiErrorEnvelope>()
            } catch (_: Exception) {
                null
            }
            throw PoseApiException(
                code = errorEnvelope?.error?.code ?: httpResponse.status.value.toString(),
                message = errorEnvelope?.error?.message ?: "Server error: ${httpResponse.status}"
            )
        }
        return httpResponse.body()
    }

    suspend fun getPoseExtractionJob(jobId: String): PoseExtractionJobStatus {
          val httpResponse: HttpResponse = requestWithSession { httpClient.get("$baseUrl/api/extract-jobs/$jobId") }
          if (!httpResponse.status.isSuccess()) {
            val errorEnvelope = try { httpResponse.body<ApiErrorEnvelope>() } catch (_: Exception) { null }
            throw PoseApiException(
                code = errorEnvelope?.error?.code ?: httpResponse.status.value.toString(),
                message = errorEnvelope?.error?.message ?: "Server error: ${httpResponse.status}"
            )
        }
        return httpResponse.body()
    }

    suspend fun getCommunityPoses(
        page: Int = 1,
        limit: Int = 20,
        difficulty: String? = null,
        tag: String? = null,
        q: String? = null,
    ): PaginatedResult<CommunityPose> {
          val httpResponse: HttpResponse = requestWithSession { httpClient.get("$baseUrl/api/community/poses") {
            parameter("page", page)
            parameter("limit", limit)
            difficulty?.let { parameter("difficulty", it) }
            tag?.let { parameter("tag", it) }
            q?.let { parameter("q", it) }
          } }
          if (!httpResponse.status.isSuccess()) {
            val errorEnvelope = try {
                httpResponse.body<ApiErrorEnvelope>()
            } catch (_: Exception) {
                null
            }
            throw PoseApiException(
                code = errorEnvelope?.error?.code ?: httpResponse.status.value.toString(),
                message = errorEnvelope?.error?.message ?: "Server error: ${httpResponse.status}"
            )
        }
        return httpResponse.body()
    }

    /**
     * Lists the signed-in Account's saved published poses (WI-03/WI-04).
     * Auth: bearer session with one refresh attempt through [requestWithSession];
     * 401 that survives refresh throws [PoseApiException] with code UNAUTHORIZED.
     * Contract: page >= 1, 1 <= limit <= 100, newest saved first.
     */
    suspend fun getSavedPoses(
        page: Int = 1,
        limit: Int = 20,
    ): PaginatedResult<CommunityPose> {
        require(page >= 1) { "page must be >= 1" }
        require(limit in 1..100) { "limit must be in 1..100" }
        val httpResponse: HttpResponse = requestWithSession { httpClient.get("$baseUrl/api/me/saved") {
            parameter("page", page)
            parameter("limit", limit)
        } }
        if (!httpResponse.status.isSuccess()) {
            val errorEnvelope = try {
                httpResponse.body<ApiErrorEnvelope>()
            } catch (_: Exception) {
                null
            }
            throw PoseApiException(
                code = errorEnvelope?.error?.code ?: httpResponse.status.value.toString(),
                message = errorEnvelope?.error?.message ?: "Server error: ${httpResponse.status}"
            )
        }
        return httpResponse.body()
    }

    /**
     * Saves a published pose to the signed-in Account's collection. Idempotent;
     * returns 200 {data: CommunityPose} on success, 404 for invalid/unpublished/
     * unusable targets, 401 for missing/invalid/expired/cross-account auth.
     */
    suspend fun savePose(poseId: String): CommunityPose {
        val httpResponse: HttpResponse = requestWithSession { httpClient.put("$baseUrl/api/me/saved/$poseId") }
        if (httpResponse.status != HttpStatusCode.OK) {
            val errorEnvelope = try {
                httpResponse.body<ApiErrorEnvelope>()
            } catch (_: Exception) {
                null
            }
            throw PoseApiException(
                code = errorEnvelope?.error?.code ?: httpResponse.status.value.toString(),
                message = errorEnvelope?.error?.message ?: "Server error: ${httpResponse.status}"
            )
        }
        return httpResponse.body<CommunityPoseDetailResponse>().data
    }

    /**
     * Removes a pose from the signed-in Account's saved collection. Idempotent;
     * returns 204 with an empty body on success. Never deletes the pose itself.
     */
    suspend fun unsavePose(poseId: String) {
        val httpResponse: HttpResponse = requestWithSession { httpClient.delete("$baseUrl/api/me/saved/$poseId") }
        if (httpResponse.status != HttpStatusCode.NoContent) {
            val errorEnvelope = try {
                httpResponse.body<ApiErrorEnvelope>()
            } catch (_: Exception) {
                null
            }
            throw PoseApiException(
                code = errorEnvelope?.error?.code ?: httpResponse.status.value.toString(),
                message = errorEnvelope?.error?.message ?: "Server error: ${httpResponse.status}"
            )
        }
    }

    /**
     * Downloads the bytes of a community pose render asset (WI-04 Try Pose
     * prepare step). Relative paths (e.g. `community/pose.png`) are resolved
     * against [baseUrl]; absolute URLs are used as-is. Non-2xx responses throw
     * [PoseApiException] with the same code mapping as the other endpoints.
     */
    suspend fun downloadImageBytes(url: String): ByteArray {
        val resolvedUrl = if (url.startsWith("http://") || url.startsWith("https://")) {
            url
        } else {
            "${baseUrl.trimEnd('/')}/${url.removePrefix("/")}"
        }
          val httpResponse: HttpResponse = requestWithSession { httpClient.get(resolvedUrl) }
          if (!httpResponse.status.isSuccess()) {
            val errorEnvelope = try {
                httpResponse.body<ApiErrorEnvelope>()
            } catch (_: Exception) {
                null
            }
            throw PoseApiException(
                code = errorEnvelope?.error?.code ?: httpResponse.status.value.toString(),
                message = errorEnvelope?.error?.message ?: "Failed to download image: ${httpResponse.status}"
            )
        }
        return httpResponse.readBytes()
    }
}
