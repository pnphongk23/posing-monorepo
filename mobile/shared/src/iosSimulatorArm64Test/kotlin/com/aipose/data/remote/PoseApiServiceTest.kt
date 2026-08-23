package com.aipose.data.remote

import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.MockRequestHandler
import io.ktor.client.engine.mock.respond
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpMethod
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import io.ktor.serialization.kotlinx.json.json
import io.ktor.utils.io.ByteReadChannel
import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull

class PoseApiServiceTest {

    private fun buildMockClient(handler: MockRequestHandler): HttpClient {
        return HttpClient(MockEngine) {
            engine {
                addHandler(handler)
            }
            install(ContentNegotiation) {
                json(sharedJson)
            }
        }
    }

    @Test
    fun `startPoseExtraction sends POST multipart and returns accepted job`() = runBlocking<Unit> {
        var capturedRequest: io.ktor.client.request.HttpRequestData? = null
        val fakeImageBytes = ByteArray(10) { it.toByte() }
        val client = buildMockClient { request ->
            capturedRequest = request
            respond(
                content = ByteReadChannel("""{"success":true,"data":{"jobId":"job-123","status":"queued"}}"""),
                status = HttpStatusCode.Accepted,
                headers = headersOf(HttpHeaders.ContentType, "application/json")
            )
        }
        try {
            val service = PoseApiService(client, "https://test.server")
            val result = service.startPoseExtraction(fakeImageBytes, "test.jpg")

            assertNotNull(capturedRequest)
            assertEquals(HttpMethod.Post, capturedRequest!!.method)
            assertEquals("/api/extract-pose", capturedRequest!!.url.encodedPath)
            assertEquals("job-123", result.data.jobId)
            assertEquals("queued", result.data.status)
        } finally {
            client.close()
        }
    }

    @Test
    fun `startPoseExtraction throws PoseApiException on non-202 response`() = runBlocking<Unit> {
        val client = buildMockClient { _ ->
            respond(
                content = ByteReadChannel("""{"error":{"code":"INVALID_IMAGE","message":"Bad image format"}}"""),
                status = HttpStatusCode.BadRequest,
                headers = headersOf(HttpHeaders.ContentType, "application/json")
            )
        }
        try {
            val service = PoseApiService(client, "https://test.server")
            val thrown = assertFailsWith<PoseApiException> {
                service.startPoseExtraction(ByteArray(4), "bad.jpg")
            }
            assertEquals("INVALID_IMAGE", thrown.code)
        } finally {
            client.close()
        }
    }

    @Test
    fun `getPoseExtractionJob requests canonical path and parses processing 200 response`() = runBlocking<Unit> {
        var capturedRequest: io.ktor.client.request.HttpRequestData? = null
        val client = buildMockClient { request ->
            capturedRequest = request
            respond(
                content = ByteReadChannel("""{"success":true,"data":{"jobId":"job-123","status":"processing","result":null,"error":null}}"""),
                status = HttpStatusCode.OK,
                headers = headersOf(HttpHeaders.ContentType, "application/json")
            )
        }
        try {
            val result = PoseApiService(client, "https://test.server").getPoseExtractionJob("job-123")

            assertNotNull(capturedRequest)
            assertEquals(HttpMethod.Get, capturedRequest!!.method)
            assertEquals("/api/extract-jobs/job-123", capturedRequest!!.url.encodedPath)
            assertEquals("job-123", result.data.jobId)
            assertEquals("processing", result.data.status)
            assertEquals(null, result.data.result)
        } finally {
            client.close()
        }
    }

    @Test
    fun `getPoseExtractionJob parses succeeded 200 pose result`() = runBlocking<Unit> {
        val client = buildMockClient {
            respond(
                content = ByteReadChannel("""{"success":true,"data":{"jobId":"job-123","status":"succeeded","result":{"imageBase64":"cG9zZQ==","mimeType":"image/png","processingTimeMs":42},"error":null}}"""),
                status = HttpStatusCode.OK,
                headers = headersOf(HttpHeaders.ContentType, "application/json")
            )
        }
        try {
            val result = PoseApiService(client, "https://test.server").getPoseExtractionJob("job-123")

            assertEquals("succeeded", result.data.status)
            assertEquals("cG9zZQ==", result.data.result?.imageBase64)
            assertEquals("image/png", result.data.result?.mimeType)
            assertEquals(42, result.data.result?.processingTimeMs)
        } finally {
            client.close()
        }
    }

    @Test
    fun `getPoseExtractionJob maps contract error response`() = runBlocking<Unit> {
        val client = buildMockClient {
            respond(
                content = ByteReadChannel("""{"error":{"code":"JOB_NOT_FOUND","message":"Extraction job not found"}}"""),
                status = HttpStatusCode.NotFound,
                headers = headersOf(HttpHeaders.ContentType, "application/json")
            )
        }
        try {
            val exception = assertFailsWith<PoseApiException> {
                PoseApiService(client, "https://test.server").getPoseExtractionJob("missing-job")
            }

            assertEquals("JOB_NOT_FOUND", exception.code)
            assertEquals("Extraction job not found", exception.message)
        } finally {
            client.close()
        }
    }

    @Test
    fun `getCommunityPoses sends GET with correct query params`() = runBlocking<Unit> {
        var capturedRequest: io.ktor.client.request.HttpRequestData? = null
        val client = buildMockClient { request ->
            capturedRequest = request
            respond(
                content = ByteReadChannel("""{"data":[],"pagination":{"page":1,"limit":20,"total":0}}"""),
                status = HttpStatusCode.OK,
                headers = headersOf(HttpHeaders.ContentType, "application/json")
            )
        }
        try {
            val service = PoseApiService(client, "https://test.server")
            val result = service.getCommunityPoses(
                page = 2,
                limit = 10,
                difficulty = "beginner",
                q = "warrior pose+%",
            )

            assertNotNull(capturedRequest)
            assertEquals(HttpMethod.Get, capturedRequest!!.method)
            assertEquals("/api/community/poses", capturedRequest!!.url.encodedPath)
            assertEquals("2", capturedRequest!!.url.parameters["page"])
            assertEquals("10", capturedRequest!!.url.parameters["limit"])
            assertEquals("beginner", capturedRequest!!.url.parameters["difficulty"])
            assertEquals("warrior pose+%", capturedRequest!!.url.parameters["q"])
            assertEquals(1, result.pagination.page)
        } finally {
            client.close()
        }
    }

    @Test
    fun `getCommunityPoses maps published canonical DTO`() = runBlocking<Unit> {
        val client = buildMockClient {
            respond(
                content = ByteReadChannel(
                    """{"data":[{"poseId":"pose-1","name":"Published Pose","skeletonUrl":"https://cdn/skeleton.png","thumbnailUrl":"https://cdn/thumb.png","status":"published","tags":["standing"],"bodyParts":["arms"]}],"pagination":{"page":1,"limit":20,"total":1}}"""
                ),
                status = HttpStatusCode.OK,
                headers = headersOf(HttpHeaders.ContentType, "application/json")
            )
        }
        try {
            val result = PoseApiService(client, "https://test.server").getCommunityPoses(q = "published")
            val pose = result.data.single()
            assertEquals("pose-1", pose.poseId)
            assertEquals("https://cdn/skeleton.png", pose.skeletonUrl)
            assertEquals("https://cdn/thumb.png", pose.thumbnailUrl)
            assertEquals("published", pose.status)
        } finally {
            client.close()
        }
    }

    @Test
    fun `getCommunityPoseDetail sends GET with ID and returns CommunityPose`() = runBlocking<Unit> {
        var capturedRequest: io.ktor.client.request.HttpRequestData? = null
        val client = buildMockClient { request ->
            capturedRequest = request
            respond(
                content = ByteReadChannel("""{"data":{"id":"p123","name":"Test Pose","imagePath":"http://img","difficulty":"intermediate","tags":["test"]}}"""),
                status = HttpStatusCode.OK,
                headers = headersOf(HttpHeaders.ContentType, "application/json")
            )
        }
        try {
            val service = PoseApiService(client, "https://test.server")
            val result = service.getCommunityPoseDetail("p123")

            assertNotNull(capturedRequest)
            assertEquals(HttpMethod.Get, capturedRequest!!.method)
            assertEquals("/api/community/poses/p123", capturedRequest!!.url.encodedPath)
            assertEquals("p123", result.poseId)
            assertEquals("Test Pose", result.name)
            assertEquals("intermediate", result.difficulty)
        } finally {
            client.close()
        }
    }

    @Test
    fun `getCommunityPoses throws PoseApiException with nested error info on non-2xx response`() = runBlocking<Unit> {
        val client = buildMockClient { _ ->
            respond(
                content = ByteReadChannel("""{"error":{"code":"AUTH_FAILED","message":"Invalid token"}}"""),
                status = HttpStatusCode.Unauthorized,
                headers = headersOf(HttpHeaders.ContentType, "application/json")
            )
        }
        try {
            val service = PoseApiService(client, "https://test.server")
            val exception = assertFailsWith<PoseApiException> {
                service.getCommunityPoses(page = 1, limit = 20)
            }
            assertEquals("AUTH_FAILED", exception.code)
            assertEquals("Invalid token", exception.message)
        } finally {
            client.close()
        }
    }
}
