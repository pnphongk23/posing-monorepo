package com.aipose.ui.screens.poses

import com.aipose.data.AiPoseDatabase
import com.aipose.data.CommunitySearchRepository
import com.aipose.data.COMMUNITY_SEARCH_PAGE_LIMIT
import com.aipose.data.DatabaseDriverFactory
import com.aipose.data.PoseRepository
import com.aipose.data.remote.CommunityPose
import com.aipose.data.remote.PaginatedResult
import com.aipose.data.remote.PaginationInfo
import com.aipose.data.remote.PoseApiService
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.http.HttpStatusCode
import io.ktor.serialization.kotlinx.json.json
import io.ktor.utils.io.ByteReadChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.runBlocking

class SearchViewModelTest {

    private fun buildMockClient(): HttpClient {
        return HttpClient(MockEngine) {
            engine {
                addHandler { _ -> respond(content = ByteReadChannel(""), status = HttpStatusCode.OK) }
            }
            install(ContentNegotiation) {
                json(Json { ignoreUnknownKeys = true })
            }
        }
    }

    private fun clearDatabase(database: AiPoseDatabase) {
        val queries = database.poseQueries
        queries.getAllPoses().executeAsList().forEach {
            queries.deletePose(it.poseId)
        }
    }

    private class FakeCommunitySearchRepository(
        private val fixtures: List<CommunityPose>,
        private val failOnceOnQueries: MutableSet<String> = mutableSetOf(),
        private val failLoadMoreOnce: Boolean = false,
    ) : CommunitySearchRepository {
        private var failNextLoadMore = failLoadMoreOnce

        override suspend fun searchCommunityPoses(
            query: String,
            page: Int,
            limit: Int,
        ): PaginatedResult<CommunityPose> {
            if (failOnceOnQueries.remove(query)) {
                throw RuntimeException("Search provider unavailable")
            }
            if (page > 1 && failNextLoadMore) {
                failNextLoadMore = false
                throw RuntimeException("Load more failed")
            }
            val filtered = if (query.isBlank()) {
                fixtures
            } else {
                fixtures.filter { it.name.contains(query, ignoreCase = true) }
            }
            val offset = (page - 1) * limit
            val pageData = filtered.drop(offset).take(limit)
            return PaginatedResult(
                data = pageData,
                pagination = PaginationInfo(page = page, limit = limit, total = filtered.size),
            )
        }
    }

    private suspend fun waitForState(
        viewModel: SearchViewModel,
        predicate: (SearchUiState) -> Boolean,
    ): SearchUiState {
        var attempts = 0
        var state = viewModel.uiState.value
        while (!predicate(state) && attempts < 200) {
            delay(10)
            state = viewModel.uiState.value
            attempts++
        }
        return state
    }

    @Test
    fun testEmptyQueryReturnsAllLocalAndPublishedPoses() = runBlocking {
        val driver = DatabaseDriverFactory().createDriver()
        val job = SupervisorJob()
        val scope = CoroutineScope(job + Dispatchers.Default)
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val apiService = PoseApiService(buildMockClient(), "https://test.server")
            val repository = PoseRepository(database, apiService)

            repository.createPoseAfterExtraction("T-Pose", "img1", "img1-skeleton", "img1-thumbnail")
            repository.createPoseAfterExtraction("Warrior Pose", "img2", "img2-skeleton", "img2-thumbnail")

            val fakeCommunity = FakeCommunitySearchRepository(
                listOf(CommunityPose("c-1", "T-Pose", "", "", "beginner", emptyList(), "", emptyList())),
            )

            val viewModel = SearchViewModel(repository, fakeCommunity, scope)
            val state = waitForState(viewModel) {
                it.localResults.size == 2 && it.publishedResults.size == 1 && !it.isInitialLoading
            }

            assertEquals(2, state.localResults.size)
            assertEquals(1, state.publishedResults.size)
            assertEquals("T-Pose", state.publishedResults.first().name)
        } finally {
            job.cancel()
            driver.close()
        }
    }

    @Test
    fun testCaseInsensitiveLocalFilteringAndPublishedHits() = runBlocking {
        val driver = DatabaseDriverFactory().createDriver()
        val job = SupervisorJob()
        val scope = CoroutineScope(job + Dispatchers.Default)
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val apiService = PoseApiService(buildMockClient(), "https://test.server")
            val repository = PoseRepository(database, apiService)

            repository.createPoseAfterExtraction("T-Pose", "img1", "img1-skeleton", "img1-thumbnail")
            repository.createPoseAfterExtraction("Warrior Pose", "img2", "img2-skeleton", "img2-thumbnail")

            val fakeCommunity = FakeCommunitySearchRepository(
                listOf(
                    CommunityPose("c-1", "T-Pose", "", "", "beginner", emptyList(), "", emptyList()),
                    CommunityPose("c-2", "Tree Pose", "", "", "beginner", emptyList(), "", emptyList()),
                ),
            )

            val viewModel = SearchViewModel(repository, fakeCommunity, scope)
            waitForState(viewModel) { it.localResults.size == 2 && !it.isInitialLoading }

            viewModel.onQueryChange("t-pose")
            val state = waitForState(viewModel) {
                it.query == "t-pose" && !it.isInitialLoading &&
                    it.localResults.size == 1 && it.publishedResults.size == 1
            }

            assertEquals(1, state.localResults.size)
            assertEquals("T-Pose", state.localResults.first().name)
            assertEquals(1, state.publishedResults.size)
            assertEquals("T-Pose", state.publishedResults.first().name)
        } finally {
            job.cancel()
            driver.close()
        }
    }

    @Test
    fun testNoResultsEmptyTips() = runBlocking {
        val driver = DatabaseDriverFactory().createDriver()
        val job = SupervisorJob()
        val scope = CoroutineScope(job + Dispatchers.Default)
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val apiService = PoseApiService(buildMockClient(), "https://test.server")
            val repository = PoseRepository(database, apiService)

            val viewModel = SearchViewModel(repository, FakeCommunitySearchRepository(emptyList()), scope)
            waitForState(viewModel) { !it.isInitialLoading }

            viewModel.onQueryChange("not-matching-anything")
            val state = waitForState(viewModel) {
                it.query == "not-matching-anything" && !it.isInitialLoading
            }

            assertTrue(state.localResults.isEmpty())
            assertTrue(state.publishedResults.isEmpty())
        } finally {
            job.cancel()
            driver.close()
        }
    }

    @Test
    fun testProviderFailureSurfacesRecoverableErrorAndAllowsRetry() = runBlocking {
        val driver = DatabaseDriverFactory().createDriver()
        val job = SupervisorJob()
        val scope = CoroutineScope(job + Dispatchers.Default)
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val apiService = PoseApiService(buildMockClient(), "https://test.server")
            val repository = PoseRepository(database, apiService)

            val failingProvider = FakeCommunitySearchRepository(
                fixtures = listOf(
                    CommunityPose("c-1", "Sun Salutation", "", "", "beginner", emptyList(), "", emptyList()),
                ),
                failOnceOnQueries = mutableSetOf(""),
            )

            val viewModel = SearchViewModel(repository, failingProvider, scope)
            val failed = waitForState(viewModel) { !it.isInitialLoading && it.searchError != null }
            assertNotNull(failed.searchError)
            assertTrue(failed.publishedResults.isEmpty())

            viewModel.retrySearch()
            val recovered = waitForState(viewModel) {
                !it.isInitialLoading && it.searchError == null && it.publishedResults.size == 1
            }
            assertNull(recovered.searchError)
            assertEquals("Sun Salutation", recovered.publishedResults.first().name)
        } finally {
            job.cancel()
            driver.close()
        }
    }

    @Test
    fun testBlankQueryWithEmptyCatalogsKeepsPrototypeEmptyCopy() = runBlocking {
        val driver = DatabaseDriverFactory().createDriver()
        val job = SupervisorJob()
        val scope = CoroutineScope(job + Dispatchers.Default)
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val apiService = PoseApiService(buildMockClient(), "https://test.server")
            val repository = PoseRepository(database, apiService)

            val viewModel = SearchViewModel(repository, FakeCommunitySearchRepository(emptyList()), scope)
            val state = waitForState(viewModel) { !it.isInitialLoading }

            assertTrue(state.query.isBlank())
            assertTrue(state.localResults.isEmpty())
            assertTrue(state.publishedResults.isEmpty())
            assertNull(state.searchError)
            assertEquals("No poses to search yet.", emptySearchSubtitle(state.query))
            assertEquals("No matching poses", emptySearchTitle())
        } finally {
            job.cancel()
            driver.close()
        }
    }

    @Test
    fun testEmptySearchCopyMatchesPrototype() {
        assertEquals("No poses to search yet.", emptySearchSubtitle(""))
        assertEquals("No poses to search yet.", emptySearchSubtitle("   "))
        assertEquals(
            "No poses match “cobra”. Try a different title.",
            emptySearchSubtitle("cobra"),
        )
        assertEquals("Clear search", clearSearchActionLabel())
        assertEquals("1 pose", searchResultsCountLabel(1, ""))
        assertEquals("2 poses", searchResultsCountLabel(2, ""))
        assertEquals("1 pose for “cobra”", searchResultsCountLabel(1, "cobra"))
        assertEquals("3 poses for “warrior”", searchResultsCountLabel(3, "warrior"))
    }

    @Test
    fun testMixedSourceIdsRemainDistinct() = runBlocking {
        val driver = DatabaseDriverFactory().createDriver()
        val job = SupervisorJob()
        val scope = CoroutineScope(job + Dispatchers.Default)
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val apiService = PoseApiService(buildMockClient(), "https://test.server")
            val repository = PoseRepository(database, apiService)

            repository.createPoseAfterExtraction("Shared Name Pose", "img1", "img1-skeleton", "img1-thumbnail")
            val personalId = database.poseQueries.getAllPoses().executeAsList().first().poseId
            val sharedId = "00000000-0000-0000-0000-000000000002"

            val communityProvider = FakeCommunitySearchRepository(
                listOf(
                    CommunityPose(sharedId, "Shared Name Pose", "", "", "beginner", emptyList(), "", emptyList()),
                ),
            )

            val viewModel = SearchViewModel(repository, communityProvider, scope)
            waitForState(viewModel) {
                it.localResults.size == 1 && it.publishedResults.size == 1 && !it.isInitialLoading
            }

            val state = viewModel.uiState.value
            assertEquals(personalId, state.localResults.single().poseId)
            assertEquals(sharedId, state.publishedResults.single().poseId)
            assertNotEquals(personalId, sharedId)
        } finally {
            job.cancel()
            driver.close()
        }
    }

    @Test
    fun testLoadMoreAppendsCommunityPageTwo() = runBlocking {
        val driver = DatabaseDriverFactory().createDriver()
        val job = SupervisorJob()
        val scope = CoroutineScope(job + Dispatchers.Default)
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val apiService = PoseApiService(buildMockClient(), "https://test.server")
            val repository = PoseRepository(database, apiService)

            val fixtures = (1..21).map { index ->
                CommunityPose("c-$index", "Fixture Pose $index", "", "", "beginner", emptyList(), "", emptyList())
            }
            val viewModel = SearchViewModel(repository, FakeCommunitySearchRepository(fixtures), scope)

            val pageOne = waitForState(viewModel) {
                !it.isInitialLoading && it.publishedResults.size == COMMUNITY_SEARCH_PAGE_LIMIT
            }
            assertTrue(pageOne.communityHasMore)

            viewModel.loadMoreCommunity()
            val pageTwo = waitForState(viewModel) {
                !it.isLoadingMore && it.publishedResults.size == 21
            }
            assertEquals(21, pageTwo.publishedResults.size)
            assertFalse(pageTwo.communityHasMore)
        } finally {
            job.cancel()
            driver.close()
        }
    }

    @Test
    fun testLoadMoreFailureRetainsCommunityResults() = runBlocking {
        val driver = DatabaseDriverFactory().createDriver()
        val job = SupervisorJob()
        val scope = CoroutineScope(job + Dispatchers.Default)
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val apiService = PoseApiService(buildMockClient(), "https://test.server")
            val repository = PoseRepository(database, apiService)

            val fixtures = (1..21).map { index ->
                CommunityPose("c-$index", "Fixture Pose $index", "", "", "beginner", emptyList(), "", emptyList())
            }
            val viewModel = SearchViewModel(
                repository,
                FakeCommunitySearchRepository(fixtures, failLoadMoreOnce = true),
                scope,
            )

            waitForState(viewModel) {
                !it.isInitialLoading && it.publishedResults.size == COMMUNITY_SEARCH_PAGE_LIMIT
            }

            viewModel.loadMoreCommunity()
            val failed = waitForState(viewModel) { it.loadMoreError != null }
            assertEquals(COMMUNITY_SEARCH_PAGE_LIMIT, failed.publishedResults.size)
            assertNotNull(failed.loadMoreError)

            viewModel.retryLoadMore()
            val recovered = waitForState(viewModel) {
                it.loadMoreError == null && it.publishedResults.size == 21
            }
            assertEquals(21, recovered.publishedResults.size)
        } finally {
            job.cancel()
            driver.close()
        }
    }

    @Test
    fun testQueryChangeResetsCommunityToPageOne() = runBlocking {
        val driver = DatabaseDriverFactory().createDriver()
        val job = SupervisorJob()
        val scope = CoroutineScope(job + Dispatchers.Default)
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val apiService = PoseApiService(buildMockClient(), "https://test.server")
            val repository = PoseRepository(database, apiService)

            val fixtures = listOf(
            CommunityPose("c-1", "Alpha Pose", "", "", "beginner", emptyList(), "", emptyList()),
            CommunityPose("c-2", "Beta Pose", "", "", "beginner", emptyList(), "", emptyList()),
            )
            val viewModel = SearchViewModel(repository, FakeCommunitySearchRepository(fixtures), scope)
            waitForState(viewModel) { !it.isInitialLoading && it.publishedResults.size == 2 }

            viewModel.onQueryChange("alpha")
            val filtered = waitForState(viewModel) {
                it.query == "alpha" && !it.isInitialLoading && it.publishedResults.size == 1
            }
            assertEquals("Alpha Pose", filtered.publishedResults.single().name)
        } finally {
            job.cancel()
            driver.close()
        }
    }
}
