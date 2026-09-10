package com.aipose.ui.screens.poses

import com.aipose.data.CommunitySearchRepository
import com.aipose.data.COMMUNITY_SEARCH_PAGE_LIMIT
import com.aipose.data.remote.CommunityPose
import com.aipose.data.remote.PaginatedResult
import com.aipose.data.remote.PaginationInfo
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.runBlocking

class SearchViewModelTest {

    private class FakeCommunitySearchRepository(
        private val fixtures: List<CommunityPose>,
        private val failOnceOnQueries: MutableSet<String> = mutableSetOf(),
        private val failLoadMoreOnce: Boolean = false,
    ) : CommunitySearchRepository {
        val searchCalls = mutableListOf<String>()
        private var failNextLoadMore = failLoadMoreOnce

        override suspend fun searchCommunityPoses(
            query: String,
            page: Int,
            limit: Int,
        ): PaginatedResult<CommunityPose> {
            searchCalls.add(query)
            if (failOnceOnQueries.remove(query)) {
                throw RuntimeException("Search provider unavailable")
            }
            if (page > 1 && failNextLoadMore) {
                failNextLoadMore = false
                throw RuntimeException("Load more failed")
            }
            val filtered = fixtures.filter { it.name.contains(query, ignoreCase = true) }
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
    fun testInitialCompositionNeverDispatchesBlankSearch() = runBlocking {
        val job = SupervisorJob()
        val scope = CoroutineScope(job + Dispatchers.Default)
        try {
            val fakeCommunity = FakeCommunitySearchRepository(
                listOf(CommunityPose("c-1", "T-Pose", "", "", "beginner", emptyList(), "", emptyList())),
            )
            SearchViewModel(fakeCommunity, scope)
            delay(50)
            assertTrue(fakeCommunity.searchCalls.isEmpty())
        } finally {
            job.cancel()
        }
    }

    @Test
    fun testBlankWhitespaceAndClearNeverDispatchSearch() = runBlocking {
        val job = SupervisorJob()
        val scope = CoroutineScope(job + Dispatchers.Default)
        try {
            val fakeCommunity = FakeCommunitySearchRepository(
                listOf(CommunityPose("c-1", "Alpha Pose", "", "", "beginner", emptyList(), "", emptyList())),
            )
            val viewModel = SearchViewModel(fakeCommunity, scope)

            viewModel.onQueryChange("   ")
            delay(30)
            assertTrue(fakeCommunity.searchCalls.isEmpty())
            assertTrue(viewModel.uiState.value.publishedResults.isEmpty())

            viewModel.onQueryChange("alpha")
            waitForState(viewModel) { it.publishedResults.size == 1 && !it.isInitialLoading }
            assertEquals(listOf("alpha"), fakeCommunity.searchCalls)

            viewModel.clearQuery()
            delay(30)
            assertEquals(listOf("alpha"), fakeCommunity.searchCalls)
            assertTrue(viewModel.uiState.value.publishedResults.isEmpty())
            assertTrue(viewModel.uiState.value.query.isEmpty())
        } finally {
            job.cancel()
        }
    }

    @Test
    fun testTrimmedNonblankQueryDispatchesPublishedSearch() = runBlocking {
        val job = SupervisorJob()
        val scope = CoroutineScope(job + Dispatchers.Default)
        try {
            val fakeCommunity = FakeCommunitySearchRepository(
                listOf(CommunityPose("c-1", "T-Pose", "", "", "beginner", emptyList(), "", emptyList())),
            )
            val viewModel = SearchViewModel(fakeCommunity, scope)

            viewModel.onQueryChange("  t-pose  ")
            val state = waitForState(viewModel) {
                it.publishedResults.size == 1 && !it.isInitialLoading
            }

            assertEquals(listOf("t-pose"), fakeCommunity.searchCalls)
            assertEquals("T-Pose", state.publishedResults.first().name)
        } finally {
            job.cancel()
        }
    }

    @Test
    fun testCaseInsensitivePublishedFiltering() = runBlocking {
        val job = SupervisorJob()
        val scope = CoroutineScope(job + Dispatchers.Default)
        try {
            val fakeCommunity = FakeCommunitySearchRepository(
                listOf(
                    CommunityPose("c-1", "T-Pose", "", "", "beginner", emptyList(), "", emptyList()),
                    CommunityPose("c-2", "Tree Pose", "", "", "beginner", emptyList(), "", emptyList()),
                ),
            )
            val viewModel = SearchViewModel(fakeCommunity, scope)

            viewModel.onQueryChange("t-pose")
            val state = waitForState(viewModel) {
                it.query == "t-pose" && !it.isInitialLoading && it.publishedResults.size == 1
            }

            assertEquals(1, state.publishedResults.size)
            assertEquals("T-Pose", state.publishedResults.first().name)
        } finally {
            job.cancel()
        }
    }

    @Test
    fun testNoResultsEmptyTips() = runBlocking {
        val job = SupervisorJob()
        val scope = CoroutineScope(job + Dispatchers.Default)
        try {
            val viewModel = SearchViewModel(FakeCommunitySearchRepository(emptyList()), scope)

            viewModel.onQueryChange("not-matching-anything")
            val state = waitForState(viewModel) {
                it.query == "not-matching-anything" && !it.isInitialLoading
            }

            assertTrue(state.publishedResults.isEmpty())
        } finally {
            job.cancel()
        }
    }

    @Test
    fun testProviderFailureSurfacesRecoverableErrorAndAllowsRetry() = runBlocking {
        val job = SupervisorJob()
        val scope = CoroutineScope(job + Dispatchers.Default)
        try {
            val failingProvider = FakeCommunitySearchRepository(
                fixtures = listOf(
                    CommunityPose("c-1", "Sun Salutation", "", "", "beginner", emptyList(), "", emptyList()),
                ),
                failOnceOnQueries = mutableSetOf("sun"),
            )

            val viewModel = SearchViewModel(failingProvider, scope)
            viewModel.onQueryChange("sun")
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
        }
    }

    @Test
    fun testBlankQueryWithEmptyCatalogKeepsPrototypeEmptyCopy() = runBlocking {
        val job = SupervisorJob()
        val scope = CoroutineScope(job + Dispatchers.Default)
        try {
            val viewModel = SearchViewModel(FakeCommunitySearchRepository(emptyList()), scope)
            delay(30)

            val state = viewModel.uiState.value
            assertTrue(state.query.isBlank())
            assertTrue(state.publishedResults.isEmpty())
            assertNull(state.searchError)
            assertEquals("No poses to search yet.", emptySearchSubtitle(state.query))
            assertEquals("No matching poses", emptySearchTitle())
        } finally {
            job.cancel()
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
    fun testLoadMoreAppendsCommunityPageTwo() = runBlocking {
        val job = SupervisorJob()
        val scope = CoroutineScope(job + Dispatchers.Default)
        try {
            val fixtures = (1..21).map { index ->
                CommunityPose("c-$index", "Fixture Pose $index", "", "", "beginner", emptyList(), "", emptyList())
            }
            val viewModel = SearchViewModel(FakeCommunitySearchRepository(fixtures), scope)

            viewModel.onQueryChange("Fixture")
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
        }
    }

    @Test
    fun testLoadMoreFailureRetainsCommunityResults() = runBlocking {
        val job = SupervisorJob()
        val scope = CoroutineScope(job + Dispatchers.Default)
        try {
            val fixtures = (1..21).map { index ->
                CommunityPose("c-$index", "Fixture Pose $index", "", "", "beginner", emptyList(), "", emptyList())
            }
            val viewModel = SearchViewModel(
                FakeCommunitySearchRepository(fixtures, failLoadMoreOnce = true),
                scope,
            )

            viewModel.onQueryChange("Fixture")
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
        }
    }

    @Test
    fun testQueryChangeResetsCommunityToPageOne() = runBlocking {
        val job = SupervisorJob()
        val scope = CoroutineScope(job + Dispatchers.Default)
        try {
            val fixtures = listOf(
                CommunityPose("c-1", "Alpha Pose", "", "", "beginner", emptyList(), "", emptyList()),
                CommunityPose("c-2", "Beta Pose", "", "", "beginner", emptyList(), "", emptyList()),
            )
            val viewModel = SearchViewModel(FakeCommunitySearchRepository(fixtures), scope)

            viewModel.onQueryChange("alpha")
            val filtered = waitForState(viewModel) {
                it.query == "alpha" && !it.isInitialLoading && it.publishedResults.size == 1
            }
            assertEquals("Alpha Pose", filtered.publishedResults.single().name)
        } finally {
            job.cancel()
        }
    }

    @Test
    fun testStalePagingCompletionCannotReplaceNewerQuery() = runBlocking {
        val job = SupervisorJob()
        val scope = CoroutineScope(job + Dispatchers.Default)
        try {
            val repo = object : CommunitySearchRepository {
                override suspend fun searchCommunityPoses(
                    query: String,
                    page: Int,
                    limit: Int,
                ): PaginatedResult<CommunityPose> {
                    if (query == "slow") delay(100)
                    return PaginatedResult(
                        data = listOf(
                            CommunityPose("$query-id", query, "", "", "beginner", emptyList(), "", emptyList()),
                        ),
                        pagination = PaginationInfo(page = page, limit = limit, total = 1),
                    )
                }
            }
            val viewModel = SearchViewModel(repo, scope)
            viewModel.onQueryChange("slow")
            viewModel.onQueryChange("fast")

            val settled = waitForState(viewModel) {
                !it.isInitialLoading && it.query == "fast" && it.publishedResults.singleOrNull()?.poseId == "fast-id"
            }
            assertEquals("fast-id", settled.publishedResults.single().poseId)
        } finally {
            job.cancel()
        }
    }
}
