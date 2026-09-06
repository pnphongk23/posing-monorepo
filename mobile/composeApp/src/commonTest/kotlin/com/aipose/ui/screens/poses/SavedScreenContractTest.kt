package com.aipose.ui.screens.poses

import com.aipose.data.remote.CommunityPose as SharedCommunityPose

import com.aipose.data.remote.PaginatedResult
import com.aipose.data.remote.PaginationInfo
import com.aipose.data.remote.PoseApiException
import com.aipose.data.SAVED_PAGE_LIMIT
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlin.coroutines.coroutineContext
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** WI-04 Saved-screen copy + interaction contract (pure, no UI host). */
class SavedScreenContractTest {

    @Test
    fun `exact stale banner and refresh-error copies are frozen`() {
        assertEquals("Offline · showing saved poses from last confirmed read.", SAVED_STALE_BANNER_COPY)
        assertEquals("Couldn't refresh. Showing your saved poses.", SAVED_REFRESH_ERROR_COPY)
    }

    @Test
    fun `stable test tags match the screen contract`() {
        assertEquals("saved-header", SAVED_HEADER_TEST_TAG)
        assertEquals("saved-back", SAVED_BACK_TEST_TAG)
        assertEquals("saved-refresh", SAVED_REFRESH_TEST_TAG)
        assertEquals("saved-stale-banner", SAVED_STALE_BANNER_TEST_TAG)
        assertEquals("saved-empty", SAVED_EMPTY_TEST_TAG)
        assertEquals("saved-initial-error", SAVED_INITIAL_ERROR_TEST_TAG)
        assertEquals("saved-load-more-error", SAVED_LOAD_MORE_ERROR_TEST_TAG)
    }

    @Test
    fun `saved grid key reuses the community key policy`() {
        val pose = SharedCommunityPose(poseId = "p-1", name = "Pose")
        assertEquals("p-1", savedPoseGridKey(pose, 0))
        val blank = SharedCommunityPose(poseId = "", name = "No id", thumbnailUrl = "http://cdn/t.png")
        assertEquals("http://cdn/t.png", savedPoseGridKey(blank, 1))
    }
}

class SavedViewModelTest {

    private class FakeSavedRepository(
        private val pages: Map<Int, List<SharedCommunityPose>>,
        private val total: Int,
        private var failInitialOnce: Boolean = false,
        private var unauthorizedOnce: Boolean = false,
    ) : com.aipose.data.SavedPosesRepository {
        var failed = false
        override suspend fun getSavedPoses(page: Int, limit: Int): PaginatedResult<SharedCommunityPose> {
            if (unauthorizedOnce && page == 1) {
                unauthorizedOnce = false
                throw PoseApiException("UNAUTHORIZED", "Unauthorized")
            }
            if (failInitialOnce) {
                failInitialOnce = false
                failed = true
                throw RuntimeException("network down")
            }
            return PaginatedResult(
                data = pages[page] ?: emptyList(),
                pagination = PaginationInfo(page, limit, total),
            )
        }

        override suspend fun savePose(poseId: String): SharedCommunityPose =
            SharedCommunityPose(poseId = poseId, name = "Saved")

        override suspend fun unsavePose(poseId: String) {}
    }

    @Test
    fun `initial load lands confirmed page 1`() = runBlocking {
        val dispatcher = coroutineContext[CoroutineDispatcher] ?: kotlinx.coroutines.Dispatchers.Default
        val page1 = (1..SAVED_PAGE_LIMIT).map { SharedCommunityPose(poseId = "p-$it", name = "P$it") }
        val vm = SavedViewModel(
            savedRepository = FakeSavedRepository(pages = mapOf(1 to page1), total = 25),
            scope = CoroutineScope(SupervisorJob() + dispatcher),
        )
        vm.loadInitial()
        var attempts = 0
        while (vm.uiState.value.items.size < SAVED_PAGE_LIMIT && attempts < 500) {
            kotlinx.coroutines.delay(5)
            attempts++
        }
        assertFalse(vm.uiState.value.isInitialLoading)
        assertEquals(SAVED_PAGE_LIMIT, vm.uiState.value.items.size)
        assertEquals(25, vm.uiState.value.total)
    }

    @Test
    fun `401 flips the account list into sign-in required`() = runBlocking {
        val page1 = (1..2).map { SharedCommunityPose(poseId = "p-$it", name = "P$it") }
        val dispatcher = coroutineContext[CoroutineDispatcher] ?: kotlinx.coroutines.Dispatchers.Default
        val vm = SavedViewModel(
            savedRepository = FakeSavedRepository(pages = mapOf(1 to page1), total = 2, unauthorizedOnce = true),
            scope = CoroutineScope(SupervisorJob() + dispatcher),
        )
        vm.loadInitial()
        var attempts = 0
        while (!vm.uiState.value.signInRequired && attempts < 500) {
            platform.posix.usleep(10_000u)
            kotlinx.coroutines.delay(5)
            attempts++
        }
        assertTrue(vm.uiState.value.signInRequired)
        assertTrue(vm.uiState.value.items.isEmpty())
    }

    @Test
    fun `network failure with confirmed items keeps stale read-only projection`() = runBlocking {
        val page1 = (1..SAVED_PAGE_LIMIT).map { SharedCommunityPose(poseId = "p-$it", name = "P$it") }
        val repo = FakeSavedRepository(pages = mapOf(1 to page1), total = 45)
        val dispatcher = coroutineContext[CoroutineDispatcher] ?: kotlinx.coroutines.Dispatchers.Default
        val vm = SavedViewModel(
            savedRepository = repo,
            scope = CoroutineScope(SupervisorJob() + dispatcher),
        )
        vm.loadInitial()
        var attempts = 0
        while (vm.uiState.value.items.size < SAVED_PAGE_LIMIT && attempts < 500) {
            kotlinx.coroutines.delay(5)
            attempts++
        }
        // Now force the next page-1 (refresh) to fail: the confirmed list must remain.
        vm.refresh()
        assertEquals(SAVED_PAGE_LIMIT, vm.uiState.value.items.size)

        val failing = SavedViewModel(
            savedRepository = FakeSavedRepository(pages = mapOf(1 to page1), total = 45, failInitialOnce = false).let {
                object : com.aipose.data.SavedPosesRepository {
                    var calls = 0
                    override suspend fun getSavedPoses(page: Int, limit: Int): PaginatedResult<SharedCommunityPose> {
                        calls++
                        if (calls >= 2) throw RuntimeException("offline")
                        return PaginatedResult(page1, PaginationInfo(1, limit, 45))
                    }
                    override suspend fun savePose(poseId: String): SharedCommunityPose = SharedCommunityPose(poseId, "S")
                    override suspend fun unsavePose(poseId: String) {}
                }
            },
            scope = CoroutineScope(SupervisorJob() + dispatcher),
        )
        failing.loadInitial()
        attempts = 0
        while (failing.uiState.value.items.size < SAVED_PAGE_LIMIT && attempts < 500) {
            kotlinx.coroutines.delay(5)
            attempts++
        }
        failing.refresh()
        attempts = 0
        while (!failing.uiState.value.isStale && attempts < 500) {
            platform.posix.usleep(10_000u)
            kotlinx.coroutines.delay(5)
            attempts++
        }
        assertTrue(failing.uiState.value.isStale, "refresh failure with confirmed items must stay stale")
        assertEquals(SAVED_PAGE_LIMIT, failing.uiState.value.items.size)
    }
}