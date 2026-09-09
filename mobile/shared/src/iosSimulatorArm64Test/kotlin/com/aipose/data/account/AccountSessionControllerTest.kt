package com.aipose.data.account

import com.aipose.data.auth.SecureTokenStorage
import com.aipose.data.auth.SessionBoundary
import com.aipose.data.auth.SessionCredentials
import com.aipose.data.auth.installSessionBoundary
import com.aipose.data.remote.AccountSummary
import com.aipose.data.remote.PoseApiService
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import io.ktor.serialization.kotlinx.json.json
import io.ktor.utils.io.ByteReadChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

private class AccountFakeTokenStorage : SecureTokenStorage {
    var credentials: SessionCredentials? = null
    override fun saveCredentials(credentials: SessionCredentials) { this.credentials = credentials }
    override fun loadCredentials(): SessionCredentials? = credentials
    override fun clearCredentials() { credentials = null }
}

class AccountSessionControllerTest {
    private lateinit var scope: CoroutineScope

    @AfterTest
    fun tearDown() {
        if (::scope.isInitialized) scope.cancel()
    }

    @Test
    fun `loads read-only account when a session exists`() = runBlocking {
        val storage = AccountFakeTokenStorage().also {
            it.credentials = SessionCredentials("access", "refresh")
        }
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val controller = AccountSessionController(
            reader = AccountSessionReader {
                AccountSummary("account-1", "Yoga User", "2026-01-01T00:00:00Z")
            },
            sessionBoundary = SessionBoundary(storage),
            scope = scope,
        )

        controller.load()
        val loaded = waitUntil { controller.state.value is AccountSessionState.SignedIn }

        assertTrue(loaded)
        assertEquals(
            AccountSummary("account-1", "Yoga User", "2026-01-01T00:00:00Z"),
            (controller.state.value as AccountSessionState.SignedIn).account,
        )
    }

    @Test
    fun `guest load does not call the account reader`() = runBlocking {
        val storage = AccountFakeTokenStorage()
        var reads = 0
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val controller = AccountSessionController(
            reader = AccountSessionReader {
                reads += 1
                AccountSummary("unexpected", "Unexpected")
            },
            sessionBoundary = SessionBoundary(storage),
            scope = scope,
        )

        controller.load()

        assertEquals(AccountSessionState.SignedOut, controller.state.value)
        assertEquals(0, reads)
    }

    @Test
    fun `sign out clears credentials and remains safe when repeated`() = runBlocking {
        val storage = AccountFakeTokenStorage().also {
            it.credentials = SessionCredentials("access", "refresh")
        }
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val controller = AccountSessionController(
            reader = AccountSessionReader { AccountSummary("account-1", "Yoga User") },
            sessionBoundary = SessionBoundary(storage),
            scope = scope,
        )

        controller.load()
        waitUntil { controller.state.value is AccountSessionState.SignedIn }
        controller.signOut()
        controller.signOut()

        val signedOut = waitUntil { controller.state.value == AccountSessionState.SignedOut }
        assertTrue(signedOut)
        assertNull(storage.loadCredentials())
    }

    @Test
    fun `stale account response is rejected after session invalidation`() = runBlocking {
        val storage = AccountFakeTokenStorage().also {
            it.credentials = SessionCredentials("access", "refresh")
        }
        val boundary = SessionBoundary(storage)
        val delayedAccount = CompletableDeferred<AccountSummary>()
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val controller = AccountSessionController(
            reader = AccountSessionReader { delayedAccount.await() },
            sessionBoundary = boundary,
            scope = scope,
        )

        controller.load()
        waitUntil { controller.state.value == AccountSessionState.Loading }
        boundary.signOut()
        delayedAccount.complete(AccountSummary("account-a", "Stale Account"))

        val signedOut = waitUntil { controller.state.value == AccountSessionState.SignedOut }
        assertTrue(signedOut)
        assertNull(storage.loadCredentials())
    }

    @Test
    fun `stale account response is rejected when signed-in generation changes`() = runBlocking {
        val storage = AccountFakeTokenStorage().also {
            it.credentials = SessionCredentials("access-a", "refresh-a")
        }
        val boundary = SessionBoundary(storage)
        val staleAccount = CompletableDeferred<AccountSummary>()
        var reads = 0
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val controller = AccountSessionController(
            reader = AccountSessionReader {
                reads++
                if (reads == 1) staleAccount.await()
                else AccountSummary("account-b", "Account B")
            },
            sessionBoundary = boundary,
            scope = scope,
        )

        controller.load()
        assertTrue(waitUntil { reads == 1 })
        boundary.saveCredentials(SessionCredentials("access-b", "refresh-b"))
        staleAccount.complete(AccountSummary("account-a", "Account A"))

        delay(50)
        assertTrue(controller.state.value !is AccountSessionState.SignedIn)

        controller.load()
        assertTrue(waitUntil { controller.state.value is AccountSessionState.SignedIn })
        assertEquals(
            "account-b",
            (controller.state.value as AccountSessionState.SignedIn).account.id,
        )
    }

    @Test
    fun `publishes account after 401 refresh and retry 200 without invalidating session`() = runBlocking {
        val storage = AccountFakeTokenStorage().also {
            it.credentials = SessionCredentials("expired", "refresh-a")
        }
        val boundary = SessionBoundary(storage)
        var accountReads = 0
        val client = HttpClient(MockEngine) {
            engine {
                addHandler { request ->
                    when (request.url.encodedPath) {
                        "/api/account/me" -> {
                            if (accountReads++ == 0) {
                                respond(ByteReadChannel(""), HttpStatusCode.Unauthorized)
                            } else {
                                respond(
                                    ByteReadChannel(
                                        """{"data":{"id":"account-after-refresh","displayName":"Fresh User"}}""",
                                    ),
                                    HttpStatusCode.OK,
                                    headersOf("Content-Type", "application/json"),
                                )
                            }
                        }
                        "/api/auth/refresh" -> respond(
                            ByteReadChannel("""{"accessToken":"access-b","refreshToken":"refresh-b"}"""),
                            HttpStatusCode.OK,
                            headersOf("Content-Type", "application/json"),
                        )
                        else -> error("Unexpected request path: ${request.url.encodedPath}")
                    }
                }
            }
            install(ContentNegotiation) { json(com.aipose.data.remote.sharedJson) }
        }
        try {
            client.installSessionBoundary(boundary)
            scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
            val controller = AccountSessionController(
                reader = com.aipose.data.account.ApiAccountSessionReader(
                    PoseApiService(client, "https://test.server", boundary),
                ),
                sessionBoundary = boundary,
                scope = scope,
            )

            controller.load()

            assertTrue(waitUntil { controller.state.value is AccountSessionState.SignedIn })
            assertEquals(
                "account-after-refresh",
                (controller.state.value as AccountSessionState.SignedIn).account.id,
            )
            assertEquals(SessionCredentials("access-b", "refresh-b"), storage.credentials)
            assertEquals(0L, boundary.generation, "same-session refresh must preserve the projection generation")
        } finally {
            client.close()
        }
    }

    private suspend fun waitUntil(predicate: () -> Boolean): Boolean {
        var attempts = 0
        while (!predicate() && attempts < 500) {
            delay(5)
            attempts++
        }
        return predicate()
    }
}
