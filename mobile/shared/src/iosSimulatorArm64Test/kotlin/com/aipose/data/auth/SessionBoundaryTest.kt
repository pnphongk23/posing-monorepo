package com.aipose.data.auth

import com.aipose.data.remote.PoseApiService
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.request.get
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import io.ktor.serialization.kotlinx.json.json
import io.ktor.utils.io.ByteReadChannel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

private class FakeTokenStorage : SecureTokenStorage {
    var credentials: SessionCredentials? = null
    override fun saveCredentials(credentials: SessionCredentials) { this.credentials = credentials }
    override fun loadCredentials(): SessionCredentials? = credentials
    override fun clearCredentials() { credentials = null }
}

class SessionBoundaryTest {
    private fun client(handler: io.ktor.client.engine.mock.MockRequestHandler): HttpClient =
        HttpClient(MockEngine) {
            engine { addHandler(handler) }
            install(ContentNegotiation) { json(com.aipose.data.remote.sharedJson) }
        }

    @Test
    fun `save load clear session credentials`() = runBlocking<Unit> {
        val storage = FakeTokenStorage()
        val credentials = SessionCredentials("access-123", "refresh-123")
        storage.saveCredentials(credentials)
        assertEquals(credentials, storage.loadCredentials())
        storage.clearCredentials()
        assertNull(storage.loadCredentials())
    }

    @Test
    fun `attaches backend token as bearer`() = runBlocking {
        val storage = FakeTokenStorage().also {
            it.credentials = SessionCredentials("access-123", "refresh-123")
        }
        var authorization: String? = null
        val httpClient = client { request ->
            authorization = request.headers[HttpHeaders.Authorization]
            respond(ByteReadChannel("{}"), HttpStatusCode.OK, headersOf(HttpHeaders.ContentType, "application/json"))
        }
        try {
            val boundary = SessionBoundary(storage)
            httpClient.installSessionBoundary(boundary)
            httpClient.get("https://test.server/protected")
            assertEquals("Bearer access-123", authorization)
        } finally {
            httpClient.close()
        }
    }

    @Test
    fun `401 refreshes once and retries with new bearer`() = runBlocking<Unit> {
        val storage = FakeTokenStorage().also {
            it.credentials = SessionCredentials("expired", "refresh-123")
        }
        val boundary = SessionBoundary(storage)
        var requestCount = 0
        var protectedRequestCount = 0
        val paths = mutableListOf<String>()
        val authorizations = mutableListOf<String?>()
        val httpClient = client { request ->
            requestCount += 1
            paths += request.url.encodedPath
            if (request.url.encodedPath != "/api/auth/refresh") {
                authorizations += request.headers[HttpHeaders.Authorization]
            }
            if (request.url.encodedPath == "/api/auth/refresh") {
                respond(
                    ByteReadChannel("""{"accessToken":"access-456","refreshToken":"refresh-456"}"""),
                    HttpStatusCode.OK,
                    headersOf(HttpHeaders.ContentType, "application/json"),
                )
            } else if (protectedRequestCount++ == 0) {
                respond(ByteReadChannel(""), HttpStatusCode.Unauthorized)
            } else {
                respond(
                    ByteReadChannel("""{"data":[],"pagination":{"page":1,"limit":20,"total":0}}"""),
                    HttpStatusCode.OK,
                    headersOf(HttpHeaders.ContentType, "application/json"),
                )
            }
        }
        try {
            httpClient.installSessionBoundary(boundary)
            var failure: Exception? = null
            try {
                PoseApiService(httpClient, "https://test.server", boundary).getCommunityPoses()
            } catch (error: Exception) {
                failure = error
            }
            assertTrue(failure == null, "unexpected API failure: ${failure?.message}; paths=$paths")
            assertEquals(SessionCredentials("access-456", "refresh-456"), storage.credentials)
            assertEquals(
                listOf("/api/community/poses", "/api/auth/refresh", "/api/community/poses"),
                paths,
            )
              assertEquals(listOf<String?>("Bearer expired", "Bearer access-456"), authorizations)
              assertEquals(3, requestCount)
              assertEquals(0L, boundary.generation, "same-session refresh must not invalidate projections")
          } finally {
              httpClient.close()
          }
    }

    @Test
    fun `failed refresh clears credentials emits sign in and does not loop`() = runBlocking<Unit> {
        val storage = FakeTokenStorage().also {
            it.credentials = SessionCredentials("expired", "refresh-123")
        }
        val boundary = SessionBoundary(storage)
        var requestCount = 0
        val httpClient = client {
            requestCount += 1
            respond(ByteReadChannel(""), HttpStatusCode.Unauthorized)
        }
        try {
            httpClient.installSessionBoundary(boundary)
            try {
                PoseApiService(httpClient, "https://test.server", boundary).getCommunityPoses()
            } catch (_: Exception) {
                // The service preserves its existing API exception behavior.
            }
            assertNull(storage.loadCredentials())
            assertEquals(SessionEvent.SignInRequired, boundary.events.first())
            assertEquals(2, requestCount)
        } finally {
            httpClient.close()
        }
    }

    @Test
    fun `sign out is local and idempotent`() = runBlocking<Unit> {
        val storage = FakeTokenStorage().also {
            it.credentials = SessionCredentials("access-123", "refresh-123")
        }
        val boundary = SessionBoundary(storage)

        boundary.signOut()
        boundary.signOut()

        assertNull(storage.loadCredentials())
        assertEquals(SessionEvent.SignedOut, boundary.events.first())
        assertEquals(1L, boundary.generation)
    }
}
