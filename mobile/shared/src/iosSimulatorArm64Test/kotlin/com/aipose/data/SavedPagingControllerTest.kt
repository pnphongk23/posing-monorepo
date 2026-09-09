package com.aipose.data

import com.aipose.data.remote.CommunityPose
import com.aipose.data.remote.PaginatedResult
import com.aipose.data.remote.PaginationInfo
import com.aipose.data.remote.PoseApiException
import com.aipose.data.auth.SessionEvent
import com.aipose.data.auth.SecureTokenStorage
import com.aipose.data.auth.SessionBoundary
import com.aipose.data.auth.SessionCredentials
import com.aipose.data.auth.installSessionBoundary
import com.aipose.data.remote.PoseApiService
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import io.ktor.serialization.kotlinx.json.json
import io.ktor.utils.io.ByteReadChannel
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.runBlocking
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * WI-04 Saved paging controller evidence: confirmed-page append, stop at total,
 * load-more error keeps content, refresh failure keeps last confirmed list stale
 * (read-only banner), 401 clears the account list into sign-in required, and no
 * mutation queue/fake success is ever produced by the controller itself.
 */
/** WI-04 test fixture builder. */
private fun savedPoseFixture(id: String, name: String = "Pose $id") =
    CommunityPose(poseId = id, name = name)

private class RefreshTokenStorage : SecureTokenStorage {
    var credentials: SessionCredentials? = null
    override fun saveCredentials(credentials: SessionCredentials) { this.credentials = credentials }
    override fun loadCredentials(): SessionCredentials? = credentials
    override fun clearCredentials() { credentials = null }
}

class SavedPagingControllerTest {

    private lateinit var controller: SavedPagingController
    private lateinit var scope: CoroutineScope

    private class FakeSavedRepository(
        private val pages: Map<Int, List<CommunityPose>> = emptyMap(),
        private val total: Int = 0,
        private var failInitialOnce: Boolean = false,
        private var failLoadMoreOnce: Boolean = false,
        private var unauthorizedOnInitial: String? = null,
        private val rejectMutations: Boolean = false,
    ) : SavedPosesRepository {
        var saveCalls = 0
        var unsaveCalls = 0

        override suspend fun getSavedPoses(page: Int, limit: Int): PaginatedResult<CommunityPose> {
            unauthorizedOnInitial?.let { code ->
                if (page == 1) {
                    unauthorizedOnInitial = null
                    throw PoseApiException(code, "Unauthorized")
                }
            }
            if (failInitialOnce) {
                failInitialOnce = false
                throw RuntimeException("network down")
            }
            if (page > 1 && failLoadMoreOnce) {
                failLoadMoreOnce = false
                throw RuntimeException("load more failed")
            }
            val data = pages[page] ?: emptyList()
            return PaginatedResult(
                data = data,
                pagination = PaginationInfo(page = page, limit = SAVED_PAGE_LIMIT, total = total),
            )
        }

        override suspend fun savePose(poseId: String): CommunityPose {
            saveCalls++
            if (rejectMutations) throw RuntimeException("offline")
            return savedPoseFixture(poseId)
        }

        override suspend fun unsavePose(poseId: String) {
            unsaveCalls++
            if (rejectMutations) throw RuntimeException("offline")
        }
    }

    private fun newController(
        repo: SavedPosesRepository,
        sessionEvents: Flow<SessionEvent>? = null,
        sessionGeneration: (() -> Long)? = null,
    ): SavedPagingController {
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        controller = SavedPagingController(repo, scope, sessionEvents, sessionGeneration)
        return controller
    }

    private suspend fun waitUntil(predicate: () -> Boolean): Boolean {
        var attempts = 0
        while (!predicate() && attempts < 500) {
            platform.posix.usleep(10_000u)
            delay(5)
            attempts++
        }
        return predicate()
    }

    @AfterTest
    fun tearDown() {
        if (::scope.isInitialized) scope.cancel()
    }

    @Test
    fun `initial load fills page 1 and computes hasMore from total`() = runBlocking {
        val page1 = (1..SAVED_PAGE_LIMIT).map { savedPoseFixture("s-$it") }
        newController(FakeSavedRepository(pages = mapOf(1 to page1), total = 45))
        controller.loadInitial()

        val ok = waitUntil { !controller.state.value.isInitialLoading }
        assertTrue(ok)
        val state = controller.state.value
        assertEquals(SAVED_PAGE_LIMIT, state.items.size)
        assertEquals(1, state.page)
        assertEquals(45, state.total)
        assertTrue(state.hasMore)
        assertFalse(state.signInRequired)
    }

    @Test
    fun `load more appends only confirmed page 2 and stops at total`() = runBlocking {
        val page1 = (1..SAVED_PAGE_LIMIT).map { savedPoseFixture("s-$it") }
        val page2 = (SAVED_PAGE_LIMIT + 1..40).map { savedPoseFixture("s-$it") }
        val repo = FakeSavedRepository(
            pages = mapOf(1 to page1, 2 to page2),
            total = 40,
        )
        newController(repo)
        controller.loadInitial()
        waitUntil { !controller.state.value.isInitialLoading }

        controller.loadMore()
        waitUntil { !controller.state.value.isLoadingMore }
        assertEquals(40, controller.state.value.items.size)
        assertEquals(2, controller.state.value.page)
        assertFalse(controller.state.value.hasMore, "should stop once items reach total")
    }

    @Test
    fun `load more failure keeps confirmed items and exposes inline error`() = runBlocking {
        val page1 = (1..SAVED_PAGE_LIMIT).map { savedPoseFixture("s-$it") }
        val repo = FakeSavedRepository(pages = mapOf(1 to page1), total = 60, failLoadMoreOnce = true)
        newController(repo)
        controller.loadInitial()
        waitUntil { !controller.state.value.isInitialLoading }

        controller.loadMore()
        waitUntil { controller.state.value.loadMoreError != null }
        assertEquals(SAVED_PAGE_LIMIT, controller.state.value.items.size)
        assertTrue(controller.state.value.loadMoreError != null)
    }

    @Test
    fun `initial failure with no cache exposes initial error not empty state`() = runBlocking {
        newController(FakeSavedRepository(total = 0, failInitialOnce = true))
        controller.loadInitial()
        waitUntil { controller.state.value.initialError != null }
        assertTrue(controller.state.value.initialError != null)
        assertTrue(controller.state.value.items.isEmpty())
        assertFalse(controller.state.value.isStale, "no cache means no stale-read banner")
    }

    @Test
    fun `refresh failure keeps last confirmed list and marks stale read-only`() = runBlocking {
        val page1 = (1..SAVED_PAGE_LIMIT).map { savedPoseFixture("s-$it") }
        val repo = FakeSavedRepository(pages = mapOf(1 to page1), total = 45, failInitialOnce = false)
        newController(repo)
        controller.loadInitial()
        waitUntil { !controller.state.value.isInitialLoading }

        // Force the next page-1 read to fail by swapping the failure flag via a new load path:
        // refresh() re-reads page 1; make it throw by using a repo that fails its second call.
        val flaky = object : SavedPosesRepository {
            private var calls = 0
            override suspend fun getSavedPoses(page: Int, limit: Int): PaginatedResult<CommunityPose> {
                calls++
                if (calls >= 2) throw RuntimeException("network down")
                return PaginatedResult(page1, PaginationInfo(1, SAVED_PAGE_LIMIT, 45))
            }
            override suspend fun savePose(poseId: String): CommunityPose = savedPoseFixture(poseId)
            override suspend fun unsavePose(poseId: String) {}
        }
        scope.cancel()
        newController(flaky)
        controller.loadInitial()
        waitUntil { !controller.state.value.isInitialLoading }

        controller.refresh()
        waitUntil { controller.state.value.refreshError != null || controller.state.value.isStale }
        assertFalse(controller.state.value.items.isEmpty(), "confirmed list must survive refresh failure")
        assertTrue(controller.state.value.isStale, "stale read-only banner expected")
        assertNull(controller.state.value.initialError, "initial error must not replace stale content")
    }

    @Test
    fun `401 clears account list and sets sign-in required`() = runBlocking {
        val page1 = (1..SAVED_PAGE_LIMIT).map { savedPoseFixture("s-$it") }
        newController(FakeSavedRepository(pages = mapOf(1 to page1), total = 45, unauthorizedOnInitial = "UNAUTHORIZED"))
        controller.loadInitial()
        waitUntil { controller.state.value.signInRequired }
        assertTrue(controller.state.value.signInRequired)
        assertTrue(controller.state.value.items.isEmpty(), "prior account data must not render as current")
    }

    @Test
    fun `session invalidation clears confirmed account data`() = runBlocking {
        val page1 = (1..SAVED_PAGE_LIMIT).map { savedPoseFixture("s-$it") }
        val sessionEvents = MutableSharedFlow<SessionEvent>(extraBufferCapacity = 1)
        newController(
            FakeSavedRepository(pages = mapOf(1 to page1), total = 45),
            sessionEvents,
        )
        controller.loadInitial()
        waitUntil { !controller.state.value.isInitialLoading }
        assertEquals(SAVED_PAGE_LIMIT, controller.state.value.items.size)

        sessionEvents.emit(SessionEvent.SignedOut)
        val invalidated = waitUntil { controller.state.value.signInRequired }
        assertTrue(invalidated)
        assertTrue(controller.state.value.items.isEmpty(), "Saved must not render the prior account")
    }

    @Test
    fun `signed-in generation change rejects stale saved response`() = runBlocking {
        val sessionEvents = MutableSharedFlow<SessionEvent>(extraBufferCapacity = 1)
        var sessionGeneration = 0L
        val staleResponse = CompletableDeferred<PaginatedResult<CommunityPose>>()
        val repo = object : SavedPosesRepository {
            override suspend fun getSavedPoses(page: Int, limit: Int): PaginatedResult<CommunityPose> =
                staleResponse.await()

            override suspend fun savePose(poseId: String): CommunityPose = savedPoseFixture(poseId)
            override suspend fun unsavePose(poseId: String) {}
        }
        newController(repo, sessionEvents) { sessionGeneration }
        controller.loadInitial()
        assertTrue(waitUntil { controller.state.value.isInitialLoading })

        sessionGeneration = 1L
        sessionEvents.tryEmit(SessionEvent.SignedIn)
        staleResponse.complete(
            PaginatedResult(
                data = listOf(savedPoseFixture("account-a")),
                pagination = PaginationInfo(1, SAVED_PAGE_LIMIT, 1),
            ),
        )

        assertTrue(waitUntil { !controller.state.value.isInitialLoading })
        assertTrue(controller.state.value.items.isEmpty(), "account A data must not publish after account B sign-in")
        assertFalse(controller.state.value.signInRequired, "signed-in transition must not require sign-in")
    }

    @Test
    fun `publishes saved page after 401 refresh and retry 200 without invalidating session`() = runBlocking {
        val storage = RefreshTokenStorage().also {
            it.credentials = SessionCredentials("expired", "refresh-a")
        }
        val boundary = SessionBoundary(storage)
        var savedReads = 0
        val client = HttpClient(MockEngine) {
            engine {
                addHandler { request ->
                    when (request.url.encodedPath) {
                        "/api/me/saved" -> {
                            if (savedReads++ == 0) {
                                respond(ByteReadChannel(""), HttpStatusCode.Unauthorized)
                            } else {
                                respond(
                                    ByteReadChannel(
                                        """{"data":[{"poseId":"saved-after-refresh","name":"Fresh Saved","status":"published"}],"pagination":{"page":1,"limit":20,"total":1}}""",
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
            val service = PoseApiService(client, "https://test.server", boundary)
            newController(
                repo = LiveSavedPosesRepository(service),
                sessionEvents = boundary.events,
                sessionGeneration = { boundary.generation },
            )

            controller.loadInitial()

            assertTrue(waitUntil { !controller.state.value.isInitialLoading })
            assertEquals(listOf("saved-after-refresh"), controller.state.value.items.map { it.poseId })
            assertEquals(SessionCredentials("access-b", "refresh-b"), storage.credentials)
            assertEquals(0L, boundary.generation, "same-session refresh must preserve the projection generation")
        } finally {
            client.close()
        }
    }

    @Test
    fun `all 401 variants map to sign-in required for initial load`() = runBlocking {
        // One 401 policy: UNAUTHORIZED, bare HTTP 401, and AUTH_FAILED all route
        // to the account sign-in requirement, never to a generic inline error.
        for (code in listOf("UNAUTHORIZED", "401", "AUTH_FAILED")) {
            newController(FakeSavedRepository(total = 0, unauthorizedOnInitial = code))
            controller.loadInitial()
            val ok = waitUntil { controller.state.value.signInRequired }
            assertTrue(ok, "code $code must flip signInRequired")
            assertTrue(controller.state.value.items.isEmpty())
            assertNull(controller.state.value.initialError, "code $code must not surface as inline error")
        }
    }

    @Test
    fun `401 during load-more clears account list and sets sign-in required`() = runBlocking {
        val page1 = (1..SAVED_PAGE_LIMIT).map { savedPoseFixture("s-$it") }
        val repo = object : SavedPosesRepository {
            private var calls = 0
            override suspend fun getSavedPoses(page: Int, limit: Int): PaginatedResult<CommunityPose> {
                calls++
                if (page > 1) throw PoseApiException("AUTH_FAILED", "expired")
                return PaginatedResult(page1, PaginationInfo(1, SAVED_PAGE_LIMIT, 45))
            }
            override suspend fun savePose(poseId: String): CommunityPose = savedPoseFixture(poseId)
            override suspend fun unsavePose(poseId: String) {}
        }
        newController(repo)
        controller.loadInitial()
        waitUntil { !controller.state.value.isInitialLoading }
        controller.loadMore()
        waitUntil { controller.state.value.signInRequired }
        assertTrue(controller.state.value.signInRequired)
        assertTrue(controller.state.value.items.isEmpty(), "no prior account data after 401 on load-more")
        assertFalse(controller.state.value.isLoadingMore, "spinner must not stay stuck after 401")
    }

    @Test
    fun `sign-in required is never derived from network failure`() = runBlocking {
        newController(FakeSavedRepository(total = 0, failInitialOnce = true))
        controller.loadInitial()
        waitUntil { controller.state.value.initialError != null }
        assertFalse(controller.state.value.signInRequired)
    }

    @Test
    fun `refresh while load-more in flight clears the stale spinner`() = runBlocking {
        val page1 = (1..SAVED_PAGE_LIMIT).map { savedPoseFixture("s-$it") }
        val page2 = (SAVED_PAGE_LIMIT + 1..40).map { savedPoseFixture("s-$it") }
        val repo = FakeSavedRepository(
            pages = mapOf(1 to page1, 2 to page2),
            total = 40,
        )
        newController(repo)
        controller.loadInitial()
        waitUntil { !controller.state.value.isInitialLoading }

        controller.loadMore()
        assertTrue(controller.state.value.isLoadingMore)
        // A refresh supersedes the in-flight load-more: spinner must clear immediately.
        controller.refresh()
        assertFalse(controller.state.value.isLoadingMore, "refresh must clear the load-more spinner")
        waitUntil { !controller.state.value.isInitialLoading }
        assertFalse(controller.state.value.isLoadingMore)
    }

    @Test
    fun `removeConfirmed deletes only the confirmed item and survives collector merge`() = runBlocking {
        val page1 = (1..SAVED_PAGE_LIMIT).map { savedPoseFixture("s-$it") }
        val page2 = (SAVED_PAGE_LIMIT + 1..40).map { savedPoseFixture("s-$it") }
        val repo = FakeSavedRepository(pages = mapOf(1 to page1, 2 to page2), total = 40)
        newController(repo)
        controller.loadInitial()
        waitUntil { !controller.state.value.isInitialLoading }

        val removedId = "s-3"
        controller.removeConfirmed(removedId)
        assertTrue(controller.state.value.items.none { it.poseId == removedId }, "confirmed removal must leave the state")

        // A later load-more merge must not reinsert the removed item (single source).
        controller.loadMore()
        waitUntil { !controller.state.value.isLoadingMore }
        assertEquals(40 - 1, controller.state.value.items.size)
        assertTrue(controller.state.value.items.none { it.poseId == removedId })
    }

    @Test
    fun `controller performs no mutation work of its own`() = runBlocking {
        // The paging controller is read-only: repository mutation counters must stay zero.
        val page1 = (1..SAVED_PAGE_LIMIT).map { savedPoseFixture("s-$it") }
        val repo = FakeSavedRepository(pages = mapOf(1 to page1), total = 45)
        newController(repo)
        controller.loadInitial()
        waitUntil { !controller.state.value.isInitialLoading }
        controller.loadMore()
        waitUntil { !controller.state.value.isLoadingMore }
        assertEquals(0, repo.saveCalls)
        assertEquals(0, repo.unsaveCalls)
    }
}
