package com.aipose.data

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import com.aipose.data.remote.CommunityPose
import com.aipose.data.remote.PaginatedResult
import com.aipose.data.remote.PaginationInfo
import com.aipose.data.remote.PoseApiService
import com.aipose.data.remote.sharedJson
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.request.HttpRequestData
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import io.ktor.serialization.kotlinx.json.json
import io.ktor.utils.io.ByteReadChannel
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class CommunitySearchRepositoryTest {

    @Test
    fun liveRepositoryForwardsSearchAndMapsPublishedResponse() = runTest {
        var capturedRequest: HttpRequestData? = null
        val client = HttpClient(MockEngine) {
            engine {
                addHandler { request ->
                    capturedRequest = request
                    respond(
                        content = ByteReadChannel(
                            """{"data":[{"poseId":"live-1","name":"Live Pose","skeletonUrl":"https://cdn/skeleton.png","thumbnailUrl":"https://cdn/thumb.png","status":"published"}],"pagination":{"page":1,"limit":20,"total":1}}"""
                        ),
                        status = HttpStatusCode.OK,
                        headers = headersOf(HttpHeaders.ContentType, "application/json")
                    )
                }
            }
            install(ContentNegotiation) { json(sharedJson) }
        }
        try {
            val repository = LiveCommunitySearchRepository(PoseApiService(client, "https://test.server"))
            val result = repository.searchCommunityPoses("live pose+%", page = 1)
            assertEquals("live pose+%", capturedRequest!!.url.parameters["q"])
            assertEquals("live-1", result.data.single().poseId)
            assertEquals("published", result.data.single().status)
        } finally {
            client.close()
        }
    }

    @Test
    fun liveRepositoryOmitsBlankQueryForCatalogueBrowse() = runTest {
        var capturedRequest: HttpRequestData? = null
        val client = HttpClient(MockEngine) {
            engine {
                addHandler { request ->
                    capturedRequest = request
                    respond(
                        content = ByteReadChannel("{\"data\":[],\"pagination\":{\"page\":1,\"limit\":20,\"total\":0}}"),
                        status = HttpStatusCode.OK,
                        headers = headersOf(HttpHeaders.ContentType, "application/json")
                    )
                }
            }
            install(ContentNegotiation) { json(sharedJson) }
        }
        try {
            LiveCommunitySearchRepository(PoseApiService(client, "https://test.server"))
                .searchCommunityPoses("   ", page = 1)
            assertEquals(null, capturedRequest!!.url.parameters["q"])
        } finally {
            client.close()
        }
    }

    @Test
    fun blankQueryReturnsPageOneWithLimitTwenty() = runTest {
        val repository = MockCommunitySearchRepository()
        val result = repository.searchCommunityPoses(query = "", page = 1)

        assertEquals(20, result.data.size)
        assertEquals(1, result.pagination.page)
        assertEquals(COMMUNITY_SEARCH_PAGE_LIMIT, result.pagination.limit)
        assertEquals(21, result.pagination.total)
        assertEquals("community-mock-01", result.data.first().poseId)
    }

    @Test
    fun whitespaceQueryReturnsPageOne() = runTest {
        val repository = MockCommunitySearchRepository()
        val result = repository.searchCommunityPoses(query = "   ", page = 1)

        assertEquals(20, result.data.size)
        assertEquals(21, result.pagination.total)
    }

    @Test
    fun pageTwoReturnsRemainingResult() = runTest {
        val repository = MockCommunitySearchRepository()
        val pageOne = repository.searchCommunityPoses(query = "", page = 1)
        val pageTwo = repository.searchCommunityPoses(query = "", page = 2)

        assertEquals(20, pageOne.data.size)
        assertEquals(1, pageTwo.data.size)
        assertEquals(21, pageTwo.pagination.total)
        assertEquals("community-mock-21", pageTwo.data.single().poseId)
    }

    @Test
    fun draftFixtureNeverSurfaces() = runTest {
        val repository = MockCommunitySearchRepository()
        val allIds = (1..2).flatMap { page ->
            repository.searchCommunityPoses(query = "", page = page).data.map { it.poseId }
        }
        assertFalse(allIds.any { it.contains("draft") })
        assertEquals(21, allIds.size)
    }

    @Test
    fun titleMatchIsCaseInsensitive() = runTest {
        val repository = MockCommunitySearchRepository()
        val result = repository.searchCommunityPoses(query = "warrior", page = 1)

        assertEquals(3, result.pagination.total)
        assertTrue(result.data.all { it.name.contains("Warrior", ignoreCase = true) })
    }

    @Test
    fun noMatchReturnsZeroTotalAndEmptyData() = runTest {
        val repository = MockCommunitySearchRepository()
        val result = repository.searchCommunityPoses(query = "non-existent-pose-name", page = 1)

        assertTrue(result.data.isEmpty())
        assertEquals(0, result.pagination.total)
    }

    @Test
    fun stableOrderingAcrossRepeatedCalls() = runTest {
        val repository = MockCommunitySearchRepository()
        val first = repository.searchCommunityPoses(query = "", page = 1).data.map { it.poseId }
        val second = repository.searchCommunityPoses(query = "", page = 1).data.map { it.poseId }
        assertEquals(first, second)
    }

    @Test
    fun pagingControllerLoadMoreAppendsPageTwo() = runTest {
        val job = SupervisorJob()
        val scope = CoroutineScope(job + Dispatchers.Default)
        try {
            val controller = CommunitySearchPagingController(MockCommunitySearchRepository(), scope)
            controller.search("")
            waitForPaging(controller) { !it.isInitialLoading && it.items.size == 20 }

            controller.loadMore()
            val loaded = waitForPaging(controller) { !it.isLoadingMore && it.items.size == 21 }
            assertEquals(21, loaded.items.size)
            assertEquals(2, loaded.page)
            assertFalse(loaded.hasMore)
        } finally {
            job.cancel()
        }
    }

    @Test
    fun pagingControllerDedupesOverlappingPageIds() = runTest {
        val overlapRepo = OverlapCommunitySearchRepository()
        val job = SupervisorJob()
        val scope = CoroutineScope(job + Dispatchers.Default)
        try {
            val controller = CommunitySearchPagingController(overlapRepo, scope)
            controller.search("")
            waitForPaging(controller) { !it.isInitialLoading && it.items.isNotEmpty() }

            controller.loadMore()
            val loaded = waitForPaging(controller) { !it.isLoadingMore }
            assertEquals(2, loaded.items.size)
            assertEquals(listOf("dup-1", "dup-2"), loaded.items.map { it.poseId })
        } finally {
            job.cancel()
        }
    }

    @Test
    fun pagingControllerIgnoresStaleInitialCompletion() = runTest {
        val job = SupervisorJob()
        val scope = CoroutineScope(job + Dispatchers.Default)
        try {
            val repo = object : CommunitySearchRepository {
                override suspend fun searchCommunityPoses(
                    query: String,
                    page: Int,
                    limit: Int,
                ): PaginatedResult<CommunityPose> {
                    return PaginatedResult(
                        data = listOf(CommunityPose(poseId = "$query-id", name = query, skeletonUrl = "")),
                        pagination = PaginationInfo(page = page, limit = limit, total = 1),
                    )
                }
            }
            val controller = CommunitySearchPagingController(repo, scope)
            controller.search("first")
            controller.search("second")

            val settled = waitForPaging(controller) {
                !it.isInitialLoading && it.query == "second" && it.items.isNotEmpty()
            }
            assertEquals("second", settled.query)
            assertEquals("second-id", settled.items.single().poseId)
        } finally {
            job.cancel()
        }
    }

    @Test
    fun pagingControllerRetainsItemsOnLoadMoreFailure() = runTest {
        val failingRepo = FailingLoadMoreRepository()
        val job = SupervisorJob()
        val scope = CoroutineScope(job + Dispatchers.Default)
        try {
            val controller = CommunitySearchPagingController(failingRepo, scope)
            controller.search("")
            val loaded = waitForPaging(controller) { !it.isInitialLoading && it.items.size == 1 && it.hasMore }
            assertEquals("keep-1", loaded.items.single().poseId)

            controller.loadMore()
            val failed = waitForPaging(controller) { !it.isLoadingMore && it.loadMoreError != null }
            assertEquals(1, failed.items.size)
            assertEquals("keep-1", failed.items.single().poseId)
            assertTrue(failed.loadMoreError!!.isNotBlank())
        } finally {
            job.cancel()
        }
    }

    @Test
    fun pagingControllerRetryInitialRecoversAfterFailure() = runTest {
        val repo = RetryOnceRepository()
        val job = SupervisorJob()
        val scope = CoroutineScope(job + Dispatchers.Default)
        try {
            val controller = CommunitySearchPagingController(repo, scope)
            controller.search("retry-query")
            val failed = waitForPaging(controller) { it.initialError != null }
            assertTrue(failed.items.isEmpty())

            controller.retryInitial()
            val recovered = waitForPaging(controller) { it.initialError == null && it.items.isNotEmpty() }
            assertEquals(1, recovered.items.size)
        } finally {
            job.cancel()
        }
    }

    private suspend fun waitForPaging(
        controller: CommunitySearchPagingController,
        predicate: (CommunitySearchPagingState) -> Boolean,
    ): CommunitySearchPagingState {
        var attempts = 0
        var state = controller.state.value
        while (!predicate(state) && attempts < 200) {
            delay(10)
            state = controller.state.value
            attempts++
        }
        return state
    }

    private class OverlapCommunitySearchRepository : CommunitySearchRepository {
        override suspend fun searchCommunityPoses(
            query: String,
            page: Int,
            limit: Int,
        ): PaginatedResult<CommunityPose> {
            return when (page) {
                1 -> PaginatedResult(
                    data = listOf(pose("dup-1"), pose("dup-2")),
                    pagination = PaginationInfo(page = 1, limit = limit, total = 2),
                )
                2 -> PaginatedResult(
                    data = listOf(pose("dup-2")),
                    pagination = PaginationInfo(page = 2, limit = limit, total = 2),
                )
                else -> PaginatedResult(
                    data = emptyList(),
                    pagination = PaginationInfo(page = page, limit = limit, total = 2),
                )
            }
        }

        private fun pose(id: String) = CommunityPose(poseId = id, name = id, skeletonUrl = "")
    }

    private class FailingLoadMoreRepository : CommunitySearchRepository {
        override suspend fun searchCommunityPoses(
            query: String,
            page: Int,
            limit: Int,
        ): PaginatedResult<CommunityPose> {
            if (page > 1) throw IllegalStateException("Load more failed")
            return PaginatedResult(
                data = listOf(CommunityPose(poseId = "keep-1", name = "Keep", skeletonUrl = "")),
                pagination = PaginationInfo(page = 1, limit = 1, total = 2),
            )
        }
    }

    private class RetryOnceRepository : CommunitySearchRepository {
        private var failNext = true

        override suspend fun searchCommunityPoses(
            query: String,
            page: Int,
            limit: Int,
        ): PaginatedResult<CommunityPose> {
            if (failNext) {
                failNext = false
                throw IllegalStateException("Search provider unavailable")
            }
            return PaginatedResult(
                data = listOf(CommunityPose(poseId = "retry-ok", name = query, skeletonUrl = "")),
                pagination = PaginationInfo(page = page, limit = limit, total = 1),
            )
        }
    }
}
