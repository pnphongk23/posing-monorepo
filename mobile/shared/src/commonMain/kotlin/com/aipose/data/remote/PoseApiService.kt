package com.aipose.data.remote

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
    private val baseUrl: String
) {
    /**
     * Enqueues canonical async extraction. HTTP 202 means only that the job
     * started; no Pose exists until the caller polls the job to `succeeded`
     * and finalizes Pose creation with the returned jobId.
     */
    suspend fun startPoseExtraction(imageBytes: ByteArray, fileName: String): PoseExtractionStartResponse {
        val mimeType = mimeTypeFromFileName(fileName)
        val httpResponse: HttpResponse = httpClient.submitFormWithBinaryData(
            url = "$baseUrl/api/extract-pose",
            formData = formData {
                append("image", imageBytes, Headers.build {
                    append(HttpHeaders.ContentType, mimeType)
                    append(HttpHeaders.ContentDisposition, "filename=$fileName")
                })
            }
        )
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
        val httpResponse: HttpResponse = httpClient.get("$baseUrl/api/extract-jobs/$jobId")
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
        val httpResponse: HttpResponse = httpClient.get("$baseUrl/api/community/poses") {
            parameter("page", page)
            parameter("limit", limit)
            difficulty?.let { parameter("difficulty", it) }
            tag?.let { parameter("tag", it) }
            q?.let { parameter("q", it) }
        }
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

    suspend fun getCommunityPoseDetail(id: String): CommunityPose {
        val httpResponse: HttpResponse = httpClient.get("$baseUrl/api/community/poses/$id")
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
        val response: CommunityPoseDetailResponse = httpResponse.body()
        return response.data
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
        val httpResponse: HttpResponse = httpClient.get(resolvedUrl)
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
