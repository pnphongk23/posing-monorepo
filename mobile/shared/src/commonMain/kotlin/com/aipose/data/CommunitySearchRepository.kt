package com.aipose.data

import com.aipose.data.remote.CommunityPose
import com.aipose.data.remote.PaginatedResult
import com.aipose.data.remote.PaginationInfo
import com.aipose.data.remote.PoseApiService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

const val COMMUNITY_SEARCH_PAGE_LIMIT = 20

interface CommunitySearchRepository {
    suspend fun searchCommunityPoses(
        query: String,
        page: Int,
        limit: Int = COMMUNITY_SEARCH_PAGE_LIMIT,
    ): PaginatedResult<CommunityPose>
}

data class CommunitySearchPagingState(
    val query: String = "",
    val items: List<CommunityPose> = emptyList(),
    val page: Int = 0,
    val filteredTotal: Int = 0,
    val hasMore: Boolean = false,
    val isInitialLoading: Boolean = false,
    val isLoadingMore: Boolean = false,
    val initialError: String? = null,
    val loadMoreError: String? = null,
)

/**
 * Paging session for community title search. Independent of [PosesLibraryCoordinator].
 */
class CommunitySearchPagingController(
    private val repository: CommunitySearchRepository,
    private val scope: CoroutineScope,
) {
    private val _state = MutableStateFlow(CommunitySearchPagingState())
    val state: StateFlow<CommunitySearchPagingState> = _state.asStateFlow()
    private var generationId = 0

    fun search(query: String) {
        val currentGen = ++generationId
        _state.value = CommunitySearchPagingState(
            query = query,
            isInitialLoading = true,
        )
        scope.launch {
            try {
                val result = repository.searchCommunityPoses(query, page = 1)
                if (generationId != currentGen) return@launch
                applyInitialSuccess(result, query, page = 1)
            } catch (e: Exception) {
                if (generationId != currentGen) return@launch
                _state.value = _state.value.copy(
                    isInitialLoading = false,
                    initialError = e.message ?: "Search failed",
                )
            }
        }
    }

    fun loadMore() {
        val current = _state.value
        if (current.isLoadingMore || current.isInitialLoading || !current.hasMore) return
        val currentGen = generationId
        val nextPage = current.page + 1
        _state.value = current.copy(isLoadingMore = true, loadMoreError = null)
        scope.launch {
            try {
                val result = repository.searchCommunityPoses(current.query, page = nextPage)
                if (generationId != currentGen) return@launch
                val existingIds = _state.value.items.map { it.poseId }.toSet()
                val uniqueNew = result.data.filter { it.poseId !in existingIds }
                val merged = _state.value.items + uniqueNew
                _state.value = _state.value.copy(
                    items = merged,
                    page = nextPage,
                    filteredTotal = result.pagination.total,
                    hasMore = nextPage * result.pagination.limit < result.pagination.total,
                    isLoadingMore = false,
                    loadMoreError = null,
                )
            } catch (e: Exception) {
                if (generationId != currentGen) return@launch
                _state.value = _state.value.copy(
                    isLoadingMore = false,
                    loadMoreError = e.message ?: "Load more failed",
                )
            }
        }
    }

    fun retryInitial() {
        search(_state.value.query)
    }

    fun retryLoadMore() {
        loadMore()
    }

    private fun applyInitialSuccess(
        result: PaginatedResult<CommunityPose>,
        query: String,
        page: Int,
    ) {
        _state.value = CommunitySearchPagingState(
            query = query,
            items = result.data,
            page = page,
            filteredTotal = result.pagination.total,
            hasMore = page * result.pagination.limit < result.pagination.total,
            isInitialLoading = false,
        )
    }
}

internal data class MockCommunityFixture(
    val pose: CommunityPose,
    val published: Boolean = true,
)

internal fun buildMockCommunityFixtures(): List<MockCommunityFixture> = listOf(
    MockCommunityFixture(
        CommunityPose(
            poseId = "community-mock-01",
            name = "T-Pose",
            skeletonUrl = "",
            difficulty = "beginner",
            tags = listOf("basic", "standing"),
            description = "Standard calibration T-pose with arms extended horizontally.",
            bodyParts = listOf("arms", "shoulders"),
        ),
    ),
    MockCommunityFixture(
        CommunityPose(
            poseId = "community-mock-02",
            name = "Warrior Pose",
            skeletonUrl = "",
            difficulty = "intermediate",
            tags = listOf("yoga", "standing"),
            description = "Classical yoga pose targeting legs and core stability.",
            bodyParts = listOf("legs", "core"),
        ),
    ),
    MockCommunityFixture(
        CommunityPose(
            poseId = "community-mock-03",
            name = "Tree Pose",
            skeletonUrl = "",
            difficulty = "beginner",
            tags = listOf("yoga", "balance"),
            description = "Single-leg balance pose improving equilibrium and focus.",
            bodyParts = listOf("legs", "ankles"),
        ),
    ),
    MockCommunityFixture(
        CommunityPose(
            poseId = "community-mock-04",
            name = "Cobra Pose",
            skeletonUrl = "",
            difficulty = "intermediate",
            tags = listOf("yoga", "lying"),
            description = "Prone backbend pose strengthening the spine and stretching chest.",
            bodyParts = listOf("spine", "chest"),
        ),
    ),
    MockCommunityFixture(
        CommunityPose(
            poseId = "community-mock-05",
            name = "Chair Pose",
            skeletonUrl = "",
            difficulty = "beginner",
            tags = listOf("yoga", "standing"),
            description = "Squat-like standing pose building leg strength.",
            bodyParts = listOf("legs", "glutes"),
        ),
    ),
    MockCommunityFixture(
        CommunityPose(
            poseId = "community-mock-06",
            name = "Downward Dog",
            skeletonUrl = "",
            difficulty = "beginner",
            tags = listOf("yoga", "stretch"),
            description = "Inverted V-shape stretch for hamstrings and shoulders.",
            bodyParts = listOf("hamstrings", "shoulders"),
        ),
    ),
    MockCommunityFixture(
        CommunityPose(
            poseId = "community-mock-07",
            name = "Mountain Pose",
            skeletonUrl = "",
            difficulty = "beginner",
            tags = listOf("yoga", "standing"),
            description = "Foundational standing alignment pose.",
            bodyParts = listOf("posture", "core"),
        ),
    ),
    MockCommunityFixture(
        CommunityPose(
            poseId = "community-mock-08",
            name = "Bridge Pose",
            skeletonUrl = "",
            difficulty = "intermediate",
            tags = listOf("yoga", "lying"),
            description = "Supine backbend opening the chest and hips.",
            bodyParts = listOf("spine", "hips"),
        ),
    ),
    MockCommunityFixture(
        CommunityPose(
            poseId = "community-mock-09",
            name = "Plank Pose",
            skeletonUrl = "",
            difficulty = "intermediate",
            tags = listOf("core", "strength"),
            description = "Isometric core hold for full-body stability.",
            bodyParts = listOf("core", "shoulders"),
        ),
    ),
    MockCommunityFixture(
        CommunityPose(
            poseId = "community-mock-10",
            name = "Side Plank",
            skeletonUrl = "",
            difficulty = "intermediate",
            tags = listOf("core", "balance"),
            description = "Lateral core strengthener with shoulder support.",
            bodyParts = listOf("core", "obliques"),
        ),
    ),
    MockCommunityFixture(
        CommunityPose(
            poseId = "community-mock-11",
            name = "Lotus Pose",
            skeletonUrl = "",
            difficulty = "advanced",
            tags = listOf("yoga", "seated"),
            description = "Seated hip opener for meditation posture.",
            bodyParts = listOf("hips", "knees"),
        ),
    ),
    MockCommunityFixture(
        CommunityPose(
            poseId = "community-mock-12",
            name = "Camel Pose",
            skeletonUrl = "",
            difficulty = "intermediate",
            tags = listOf("yoga", "backbend"),
            description = "Kneeling backbend stretching the front body.",
            bodyParts = listOf("spine", "chest"),
        ),
    ),
    MockCommunityFixture(
        CommunityPose(
            poseId = "community-mock-13",
            name = "Child Pose",
            skeletonUrl = "",
            difficulty = "beginner",
            tags = listOf("yoga", "rest"),
            description = "Restorative forward fold resting pose.",
            bodyParts = listOf("back", "hips"),
        ),
    ),
    MockCommunityFixture(
        CommunityPose(
            poseId = "community-mock-14",
            name = "Eagle Pose",
            skeletonUrl = "",
            difficulty = "intermediate",
            tags = listOf("yoga", "balance"),
            description = "Wrapped balance pose improving focus and stability.",
            bodyParts = listOf("legs", "shoulders"),
        ),
    ),
    MockCommunityFixture(
        CommunityPose(
            poseId = "community-mock-15",
            name = "Half Moon Pose",
            skeletonUrl = "",
            difficulty = "intermediate",
            tags = listOf("yoga", "balance"),
            description = "Standing balance with lateral opening.",
            bodyParts = listOf("legs", "core"),
        ),
    ),
    MockCommunityFixture(
        CommunityPose(
            poseId = "community-mock-16",
            name = "Pigeon Pose",
            skeletonUrl = "",
            difficulty = "intermediate",
            tags = listOf("yoga", "stretch"),
            description = "Deep hip opener for glutes and piriformis.",
            bodyParts = listOf("hips", "glutes"),
        ),
    ),
    MockCommunityFixture(
        CommunityPose(
            poseId = "community-mock-17",
            name = "Triangle Pose",
            skeletonUrl = "",
            difficulty = "beginner",
            tags = listOf("yoga", "standing"),
            description = "Side stretch improving hamstring and torso length.",
            bodyParts = listOf("hamstrings", "torso"),
        ),
    ),
    MockCommunityFixture(
        CommunityPose(
            poseId = "community-mock-18",
            name = "Warrior Two",
            skeletonUrl = "",
            difficulty = "beginner",
            tags = listOf("yoga", "standing"),
            description = "Open-hip warrior stance for leg endurance.",
            bodyParts = listOf("legs", "hips"),
        ),
    ),
    MockCommunityFixture(
        CommunityPose(
            poseId = "community-mock-19",
            name = "Warrior Three",
            skeletonUrl = "",
            difficulty = "intermediate",
            tags = listOf("yoga", "balance"),
            description = "Single-leg balance warrior variation.",
            bodyParts = listOf("legs", "core"),
        ),
    ),
    MockCommunityFixture(
        CommunityPose(
            poseId = "community-mock-20",
            name = "Sun Salutation A",
            skeletonUrl = "",
            difficulty = "beginner",
            tags = listOf("yoga", "flow"),
            description = "Classic vinyasa warm-up sequence.",
            bodyParts = listOf("full-body"),
        ),
    ),
    MockCommunityFixture(
        CommunityPose(
            poseId = "community-mock-21",
            name = "Sun Salutation B",
            skeletonUrl = "",
            difficulty = "intermediate",
            tags = listOf("yoga", "flow"),
            description = "Extended sun salutation with warrior transitions.",
            bodyParts = listOf("full-body"),
        ),
    ),
    MockCommunityFixture(
        CommunityPose(
            poseId = "community-draft-hidden",
            name = "Draft Studio Pose",
            skeletonUrl = "",
            difficulty = "beginner",
            tags = listOf("draft"),
            description = "Unpublished draft fixture that must never surface.",
            bodyParts = listOf("draft"),
        ),
        published = false,
    ),
)

internal val MOCK_PUBLISHED_COMMUNITY_FIXTURES: List<CommunityPose> =
    buildMockCommunityFixtures().filter { it.published }.map { it.pose }

class LiveCommunitySearchRepository(
    private val apiService: PoseApiService,
) : CommunitySearchRepository {
    override suspend fun searchCommunityPoses(
        query: String,
        page: Int,
        limit: Int,
    ): PaginatedResult<CommunityPose> {
        require(page >= 1) { "page must be >= 1" }
        require(limit > 0) { "limit must be > 0" }
        return apiService.getCommunityPoses(
            page = page,
            limit = limit,
            q = query.takeIf { it.isNotBlank() },
        )
    }
}

class MockCommunitySearchRepository : CommunitySearchRepository {
    private val fixtures: List<MockCommunityFixture> = buildMockCommunityFixtures()

    override suspend fun searchCommunityPoses(
        query: String,
        page: Int,
        limit: Int,
    ): PaginatedResult<CommunityPose> {
        require(page >= 1) { "page must be >= 1" }
        require(limit > 0) { "limit must be > 0" }

        val published = fixtures.filter { it.published }.map { it.pose }
        val filtered = if (query.isBlank()) {
            published
        } else {
            published.filter { it.name.contains(query, ignoreCase = true) }
        }
        val total = filtered.size
        val offset = (page - 1) * limit
        val pageData = filtered.drop(offset).take(limit)

        return PaginatedResult(
            data = pageData,
            pagination = PaginationInfo(page = page, limit = limit, total = total),
        )
    }
}
