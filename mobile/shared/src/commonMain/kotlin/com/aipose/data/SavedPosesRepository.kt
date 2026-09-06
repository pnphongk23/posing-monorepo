package com.aipose.data

import com.aipose.data.remote.CommunityPose
import com.aipose.data.remote.PaginatedResult
import com.aipose.data.remote.PaginationInfo
import com.aipose.data.remote.PoseApiException
import com.aipose.data.remote.PoseApiService
import com.aipose.data.remote.isUnauthorized
import com.aipose.data.auth.SessionEvent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch

/** WI-03 contract default page size for GET /api/me/saved. */
const val SAVED_PAGE_LIMIT = 20

/**
 * Account-scoped Saved collection (FEAT-008, WI-03 contract). All reads/mutations
 * go through the own API with the existing SecureTokenStorage/SessionBoundary
 * bearer seam; the mobile layer never calls Supabase directly.
 */
interface SavedPosesRepository {
    suspend fun getSavedPoses(page: Int, limit: Int = SAVED_PAGE_LIMIT): PaginatedResult<CommunityPose>
    suspend fun savePose(poseId: String): CommunityPose
    suspend fun unsavePose(poseId: String)
}

class LiveSavedPosesRepository(
    private val apiService: PoseApiService,
) : SavedPosesRepository {
    override suspend fun getSavedPoses(page: Int, limit: Int): PaginatedResult<CommunityPose> {
        require(page >= 1) { "page must be >= 1" }
        require(limit in 1..100) { "limit must be in 1..100" }
        return apiService.getSavedPoses(page = page, limit = limit)
    }

    override suspend fun savePose(poseId: String): CommunityPose = apiService.savePose(poseId)

    override suspend fun unsavePose(poseId: String) = apiService.unsavePose(poseId)
}

/**
 * Offline/stale-aware paging session for the Signed-in Saved list. Mirrors
 * [CommunitySearchPagingController] but never invents data: every confirmed page
 * is held in [SavedPagingState.items] (the last confirmed projection), and a
 * non-401 load failure with existing confirmed items renders [SavedPagingState.isStale]
 * read-only instead of replacing content. 401 clears the account-scoped list and
 * flags [SavedPagingState.signInRequired] so the UI routes to the shared
 * sign-in requirement; no mutation queue or fake success is ever produced here.
 */
data class SavedPagingState(
    val items: List<CommunityPose> = emptyList(),
    val page: Int = 0,
    val total: Int = 0,
    val hasMore: Boolean = false,
    val isInitialLoading: Boolean = false,
    val isLoadingMore: Boolean = false,
    val initialError: String? = null,
    val loadMoreError: String? = null,
    val refreshError: String? = null,
    val isStale: Boolean = false,
    val signInRequired: Boolean = false,
)

class SavedPagingController(
    private val repository: SavedPosesRepository,
    private val scope: CoroutineScope,
    private val sessionEvents: Flow<SessionEvent>? = null,
    private val sessionGenerationProvider: (() -> Long)? = null,
) {
    private val _state = MutableStateFlow(SavedPagingState())
    val state: StateFlow<SavedPagingState> = _state.asStateFlow()
    private var generationId = 0

    init {
        sessionEvents?.let { events ->
            scope.launch {
                events.collect { event ->
                    when (event) {
                        SessionEvent.SignInRequired,
                        SessionEvent.SignedOut,
                        -> clearForSessionChange(signInRequired = true)
                        SessionEvent.SignedIn -> clearForSessionChange(signInRequired = false)
                    }
                }
            }
        }
    }

    /** Loads page 1 (initial or refresh). Nothing is queued, only confirmed data lands. */
    fun loadInitial() {
        val current = _state.value
        if (current.isInitialLoading) return
        val currentSessionGeneration = sessionGenerationProvider?.invoke()
        val currentGen = ++generationId
        _state.value = current.copy(
            isInitialLoading = true,
            isLoadingMore = false,
            initialError = null,
            loadMoreError = null,
            refreshError = null,
            isStale = false,
            signInRequired = false,
        )
        scope.launch {
            try {
                val result = repository.getSavedPoses(page = 1)
                if (!isCurrent(currentGen, currentSessionGeneration)) {
                    _state.value = _state.value.copy(isInitialLoading = false)
                    return@launch
                }
                applyInitialSuccess(result)
            } catch (e: PoseApiException) {
                if (!isCurrent(currentGen, currentSessionGeneration)) {
                    _state.value = _state.value.copy(isInitialLoading = false)
                    return@launch
                }
                applyFailure(e, refreshing = false)
            } catch (e: Exception) {
                if (!isCurrent(currentGen, currentSessionGeneration)) {
                    _state.value = _state.value.copy(isInitialLoading = false)
                    return@launch
                }
                applyFailure(e, refreshing = false)
            }
        }
    }

    /** Explicit refresh of page 1; a failure keeps the last confirmed list. */
    fun refresh() {
        val current = _state.value
        if (current.isInitialLoading) return
        val currentSessionGeneration = sessionGenerationProvider?.invoke()
        val currentGen = ++generationId
        _state.value = current.copy(
            isLoadingMore = false, // a refresh supersedes any in-flight load-more
            loadMoreError = null,
            refreshError = null,
            isStale = false,
        )
        scope.launch {
            try {
                val result = repository.getSavedPoses(page = 1)
                if (!isCurrent(currentGen, currentSessionGeneration)) return@launch
                applyInitialSuccess(result)
            } catch (e: PoseApiException) {
                if (!isCurrent(currentGen, currentSessionGeneration)) return@launch
                applyFailure(e, refreshing = true)
            } catch (e: Exception) {
                if (!isCurrent(currentGen, currentSessionGeneration)) return@launch
                applyFailure(e, refreshing = true)
            }
        }
    }

    fun loadMore() {
        val current = _state.value
        if (current.isLoadingMore || !current.hasMore || current.isInitialLoading) return
        val currentSessionGeneration = sessionGenerationProvider?.invoke()
        val currentGen = generationId
        val nextPage = current.page + 1
        _state.value = current.copy(isLoadingMore = true, loadMoreError = null)
        scope.launch {
            try {
                val result = repository.getSavedPoses(page = nextPage)
                if (!isCurrent(currentGen, currentSessionGeneration)) {
                    _state.value = _state.value.copy(isLoadingMore = false)
                    return@launch
                }
                val existingIds = _state.value.items.map { it.poseId }.toSet()
                val uniqueNew = result.data.filter { it.poseId !in existingIds }
                val merged = _state.value.items + uniqueNew
                _state.value = _state.value.copy(
                    items = merged,
                    page = nextPage,
                    total = result.pagination.total,
                    hasMore = nextPage * result.pagination.limit < result.pagination.total,
                    isLoadingMore = false,
                    loadMoreError = null,
                )
            } catch (e: PoseApiException) {
                if (!isCurrent(currentGen, currentSessionGeneration)) {
                    // Superseded by a newer generation: never leave the spinner stuck.
                    _state.value = _state.value.copy(isLoadingMore = false)
                    return@launch
                }
                if (e.isUnauthorized()) {
                    // One 401 policy: any variant on load-more follows the same
                    // clear-account + sign-in-required path as initial/refresh.
                    _state.value = SavedPagingState(signInRequired = true)
                    return@launch
                }
                _state.value = _state.value.copy(isLoadingMore = false, loadMoreError = e.message ?: "Load more failed")
            } catch (e: Exception) {
                if (!isCurrent(currentGen, currentSessionGeneration)) {
                    _state.value = _state.value.copy(isLoadingMore = false)
                    return@launch
                }
                _state.value = _state.value.copy(isLoadingMore = false, loadMoreError = e.message ?: "Load more failed")
            }
        }
    }

    /**
     * Removes a pose from the single controller state after a CONFIRMED 204 unsave
     * in detail. The collector mirrors this state, so the item cannot be reinserted
     * by a later load-more merge (the controller is the single source of truth).
     */
    fun removeConfirmed(poseId: String) {
        val current = _state.value
        if (current.items.none { it.poseId == poseId }) return
        val newTotal = (current.total - 1).coerceAtLeast(0)
        _state.value = current.copy(
            items = current.items.filterNot { it.poseId == poseId },
            total = newTotal,
            hasMore = current.page * SAVED_PAGE_LIMIT < newTotal,
        )
    }

    /** Clears account-owned Saved data when the shared session boundary invalidates. */
    fun clearForSessionInvalidation() {
        clearForSessionChange(signInRequired = true)
    }

    private fun clearForSessionChange(signInRequired: Boolean) {
        generationId += 1
        _state.value = SavedPagingState(signInRequired = signInRequired)
    }

    private fun isCurrent(requestGeneration: Int, sessionGeneration: Long?): Boolean =
        generationId == requestGeneration &&
            (sessionGeneration == null || sessionGenerationProvider?.invoke() == sessionGeneration)

    private fun applyInitialSuccess(result: PaginatedResult<CommunityPose>) {
        _state.value = SavedPagingState(
            items = result.data,
            page = 1,
            total = result.pagination.total,
            hasMore = 1 * result.pagination.limit < result.pagination.total,
        )
    }

    private fun applyFailure(e: Exception, refreshing: Boolean) {
        if (e is PoseApiException && e.isUnauthorized()) {
            // Session expired: never render prior account data as current.
            _state.value = SavedPagingState(signInRequired = true)
            return
        }
        val current = _state.value
        val hasConfirmedItems = current.items.isNotEmpty()
        _state.value = if (hasConfirmedItems) {
            // Keep the last confirmed projection and mark it stale read-only.
            current.copy(
                isInitialLoading = false,
                isLoadingMore = false,
                initialError = null,
                refreshError = if (refreshing) (e.message ?: "Couldn't refresh. Showing your saved poses.") else null,
                isStale = true,
            )
        } else {
            current.copy(
                isInitialLoading = false,
                isLoadingMore = false,
                initialError = e.message ?: "Unable to load saved poses",
                refreshError = if (refreshing) (e.message ?: "Couldn't refresh. Showing your saved poses.") else null,
            )
        }
    }

    fun retryInitial() = loadInitial()

    fun retryLoadMore() = loadMore()
}
