package com.aipose.data

import com.aipose.Pose
import com.aipose.data.remote.CommunityPose
import com.aipose.data.remote.PoseApiService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

sealed interface OperationState {
    object Idle : OperationState
    object Loading : OperationState
    data class Error(val message: String) : OperationState
}

data class CommunityLibraryState(
    val items: List<CommunityPose> = emptyList(),
    val page: Int = 1,
    val total: Int = 0,
    val hasMore: Boolean = true,
    val initialLoadState: OperationState = OperationState.Idle,
    val refreshState: OperationState = OperationState.Idle,
    val loadMoreState: OperationState = OperationState.Idle,
    val generationId: Int = 0
)

class PosesLibraryCoordinator(
    private val repository: PoseRepository,
    private val apiService: PoseApiService,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main),
) {
    
    private val _communityState = MutableStateFlow(CommunityLibraryState())
    val communityState: StateFlow<CommunityLibraryState> = _communityState.asStateFlow()

    fun getMyPoses(): Flow<List<Pose>> = repository.getMyPoses()

    fun loadCommunityInitial() {
        if (_communityState.value.initialLoadState is OperationState.Loading) return
        val currentGen = _communityState.value.generationId + 1
        _communityState.value = _communityState.value.copy(
            initialLoadState = OperationState.Loading,
            loadMoreState = OperationState.Idle,
            generationId = currentGen
        )
        scope.launch {
            try {
                val result = repository.getCommunityPoses(page = 1, pageSize = 20)
                if (_communityState.value.generationId == currentGen) {
                    _communityState.value = _communityState.value.copy(
                        items = result.data,
                        page = 1,
                        total = result.pagination.total,
                        hasMore = 1 * result.pagination.limit < result.pagination.total,
                        initialLoadState = OperationState.Idle
                    )
                }
            } catch (e: Exception) {
                if (_communityState.value.generationId == currentGen) {
                    _communityState.value = _communityState.value.copy(
                        initialLoadState = OperationState.Error(e.message ?: "Initial load failed")
                    )
                }
            }
        }
    }

    fun refreshCommunity() {
        if (_communityState.value.refreshState is OperationState.Loading) return
        val currentGen = _communityState.value.generationId + 1
        _communityState.value = _communityState.value.copy(
            refreshState = OperationState.Loading,
            loadMoreState = OperationState.Idle,
            generationId = currentGen
        )
        scope.launch {
            try {
                val result = repository.getCommunityPoses(page = 1, pageSize = 20)
                if (_communityState.value.generationId == currentGen) {
                    _communityState.value = _communityState.value.copy(
                        items = result.data,
                        page = 1,
                        total = result.pagination.total,
                        hasMore = 1 * result.pagination.limit < result.pagination.total,
                        refreshState = OperationState.Idle
                    )
                }
            } catch (e: Exception) {
                if (_communityState.value.generationId == currentGen) {
                    _communityState.value = _communityState.value.copy(
                        refreshState = OperationState.Error(e.message ?: "Refresh failed")
                    )
                }
            }
        }
    }

    fun loadMoreCommunity() {
        val state = _communityState.value
        if (state.loadMoreState is OperationState.Loading || !state.hasMore) return
        val currentGen = state.generationId
        val nextPage = state.page + 1
        _communityState.value = _communityState.value.copy(
            loadMoreState = OperationState.Loading
        )
        scope.launch {
            try {
                val result = repository.getCommunityPoses(page = nextPage, pageSize = 20)
                if (_communityState.value.generationId == currentGen) {
                    val updatedState = _communityState.value
                    // Deduplicate by ID and maintain stable first-seen order
                    val existingIds = updatedState.items.map { it.id }.toSet()
                    val uniqueNew = result.data.filter { it.id !in existingIds }
                    val updatedItems = updatedState.items + uniqueNew
                    
                    _communityState.value = updatedState.copy(
                        items = updatedItems,
                        page = nextPage,
                        total = result.pagination.total,
                        hasMore = nextPage * result.pagination.limit < result.pagination.total,
                        loadMoreState = OperationState.Idle
                    )
                }
            } catch (e: Exception) {
                if (_communityState.value.generationId == currentGen) {
                    _communityState.value = _communityState.value.copy(
                        loadMoreState = OperationState.Error(e.message ?: "Load more failed")
                    )
                }
            }
        }
    }
}
