package com.aipose.ui.screens.poses

import com.aipose.data.AppConfig
import com.aipose.data.PoseServiceLocator
import com.aipose.data.SAVED_PAGE_LIMIT
import com.aipose.data.SavedPagingController
import com.aipose.data.SavedPagingState
import com.aipose.data.SavedPosesRepository
import com.aipose.data.auth.SessionEvent
import com.aipose.data.remote.CommunityPose
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Saved-collection ViewModel. Mirrors the Poses Community feed structure but for the
 * account-scoped `/api/me/saved` contract: page-1 default [SAVED_PAGE_LIMIT], append
 * only confirmed pages, stop at `pagination.total`, no invented cursor. The paging
 * controller owns the stale/offline read-only projection and the 401 sign-in flip;
 * this ViewModel only mirrors its state and exposes safe actions.
 */
class SavedViewModel(
    private val savedRepository: SavedPosesRepository = PoseServiceLocator.savedPosesRepository,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main),
    private val sessionEvents: Flow<SessionEvent> = PoseServiceLocator.sessionBoundary.events,
    private val sessionGeneration: () -> Long = { PoseServiceLocator.sessionBoundary.generation },
) {
    private val paging = SavedPagingController(savedRepository, scope, sessionEvents, sessionGeneration)

    private val _uiState = MutableStateFlow(SavedPagingState())
    val uiState: StateFlow<SavedPagingState> = _uiState.asStateFlow()

    init {
        PoseServiceLocator.baseUrl = AppConfig.SERVER_BASE_URL
        scope.launch {
            paging.state.collect { _uiState.value = it }
        }
    }

    fun loadInitial() = paging.loadInitial()
    fun refresh() = paging.refresh()
    fun loadMore() = paging.loadMore()
    fun retryInitial() = paging.retryInitial()
    fun retryLoadMore() = paging.retryLoadMore()

    /**
     * Removes a pose from the hoisted Saved list ONLY after a confirmed 204 unsave
     * in detail. Delegates to the paging controller (single source of truth) so a
     * later load-more merge can never reinsert the removed item via the collector.
     */
    fun removeConfirmed(poseId: String) = paging.removeConfirmed(poseId)
}

/** Stable grid key for a saved pose (reuses the community key policy). */
internal fun savedPoseGridKey(pose: CommunityPose, index: Int): String =
    communityPoseGridKey(pose, index)
