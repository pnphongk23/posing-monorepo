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
    fun `extractPose sends POST multipart with image field and returns ByteArray`() = runBlocking<Unit> {
        var capturedRequest: io.ktor.client.request.HttpRequestData? = null
        val fakeImageBytes = ByteArray(10) { it.toByte() }
        val client = buildMockClient { request ->
            capturedRequest = request
            respond(
                content = ByteReadChannel("""{"success":true,"data":{"imageBase64":"AQIDBA==","mimeType":"image/png","processingTimeMs":100}}"""),
                status = HttpStatusCode.OK,
                headers = headersOf(HttpHeaders.ContentType, "application/json")
            )
        }
        try {
            val service = PoseApiService(client, "https://test.server")
            val result = service.extractPose(fakeImageBytes, "test.jpg")

            assertNotNull(capturedRequest)
            assertEquals(HttpMethod.Post, capturedRequest!!.method)
            assertEquals("/api/extract-pose", capturedRequest!!.url.encodedPath)
            assertNotNull(result)
        } finally {
            client.close()
        }
    }

    @Test
    fun `extractPose throws PoseApiException on non-2xx response`() = runBlocking<Unit> {
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
                service.extractPose(ByteArray(4), "bad.jpg")
            }
            assertEquals("INVALID_IMAGE", thrown.code)
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
            val result = service.getCommunityPoses(page = 2, limit = 10, difficulty = "beginner")

            assertNotNull(capturedRequest)
            assertEquals(HttpMethod.Get, capturedRequest!!.method)
            assertEquals("/api/community/poses", capturedRequest!!.url.encodedPath)
            assertEquals("2", capturedRequest!!.url.parameters["page"])
            assertEquals("10", capturedRequest!!.url.parameters["limit"])
            assertEquals("beginner", capturedRequest!!.url.parameters["difficulty"])
            assertEquals(1, result.pagination.page)
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
            assertEquals("p123", result.id)
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
