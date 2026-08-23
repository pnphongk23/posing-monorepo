package com.aipose.ui.screens.poses

import com.aipose.Pose
import com.aipose.data.DatabaseDriverFactory
import com.aipose.data.PoseRepository
import com.aipose.data.AiPoseDatabase
import com.aipose.data.PosesLibraryCoordinator
import com.aipose.data.CommunityLibraryState
import com.aipose.data.OperationState
import com.aipose.data.remote.CommunityPose
import com.aipose.data.remote.PoseApiService
import io.ktor.client.*
import io.ktor.client.engine.mock.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.http.*
import io.ktor.serialization.kotlinx.json.*
import io.ktor.utils.io.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class PosesViewModelTest {

    private fun buildMockClient(responseJson: String, status: HttpStatusCode = HttpStatusCode.OK): HttpClient {
        return HttpClient(MockEngine) {
            engine {
                addHandler { _ ->
                    respond(
                        content = ByteReadChannel(responseJson),
                        status = status,
                        headers = headersOf(HttpHeaders.ContentType, "application/json")
                    )
                }
            }
            install(ContentNegotiation) {
                json(Json { ignoreUnknownKeys = true })
            }
        }
    }

    private suspend fun waitForState(
        viewModel: PosesViewModel,
        predicate: (PosesUiState) -> Boolean
    ): PosesUiState {
        var attempts = 0
        var state = viewModel.uiState.value
        while (!predicate(state) && attempts < 100) {
            delay(10)
            state = viewModel.uiState.value
            attempts++
        }
        return state
    }

    @Test
    fun testTabSelection() = runBlocking<Unit> {
        val driver = DatabaseDriverFactory().createDriver()
        val job = SupervisorJob()
        val scope = CoroutineScope(job)
        try {
            val database = AiPoseDatabase(driver)
            val apiService = PoseApiService(buildMockClient(""), "https://test.server")
            val repository = PoseRepository(database, apiService)
            val coordinator = PosesLibraryCoordinator(repository, apiService, scope)
            val viewModel = PosesViewModel(coordinator, scope)

            assertEquals(0, viewModel.uiState.value.selectedTab)

            viewModel.selectTab(1)
            assertEquals(1, viewModel.uiState.value.selectedTab)
        } finally {
            job.cancel()
            driver.close()
        }
    }

    @Test
    fun testRetryRefreshWiringAndListRetentionOnFailure() = runBlocking<Unit> {
        val driver = DatabaseDriverFactory().createDriver()
        val job = SupervisorJob()
        val scope = CoroutineScope(job)
        try {
            val database = AiPoseDatabase(driver)
            
            val jsonSuccess = """
                {
                    "data": [
                        {
                            "id": "c-1",
                            "name": "T-Pose",
                            "imagePath": "http://img/t.png",
                            "difficulty": "beginner",
                            "tags": []
                        }
                    ],
                    "pagination": {
                        "page": 1,
                        "limit": 20,
                        "total": 1
                    }
                }
            """.trimIndent()

            var callCount = 0
            val dynamicClient = HttpClient(MockEngine) {
                engine {
                    addHandler { _ ->
                        callCount++
                        if (callCount == 1) {
                            respond(jsonSuccess, HttpStatusCode.OK, headersOf(HttpHeaders.ContentType, "application/json"))
                        } else {
                            respond("""{"error":{"message":"Internal error"}}""", HttpStatusCode.InternalServerError, headersOf(HttpHeaders.ContentType, "application/json"))
                        }
                    }
                }
                install(ContentNegotiation) {
                    json(Json { ignoreUnknownKeys = true })
                }
            }
            val dynamicApiService = PoseApiService(dynamicClient, "https://test.server")
            val dynamicRepo = PoseRepository(database, dynamicApiService)
            val dynamicCoordinator = PosesLibraryCoordinator(dynamicRepo, dynamicApiService, scope)
            val dynamicViewModel = PosesViewModel(dynamicCoordinator, scope)

            // First call (initial load) - succeeds
            dynamicViewModel.loadCommunityPoses(refresh = false)
            val s1 = waitForState(dynamicViewModel) { it.communityState.items.isNotEmpty() }
            assertEquals(1, s1.communityState.items.size)

            // Second call (refresh) - fails
            dynamicViewModel.loadCommunityPoses(refresh = true)
            val s2 = waitForState(dynamicViewModel) { it.communityState.refreshState is OperationState.Error }

            // Invariant check: Items are retained even when refresh fails!
            assertEquals(1, s2.communityState.items.size)
            assertEquals("T-Pose", s2.communityState.items.first().name)
            assertTrue(s2.communityState.refreshState is OperationState.Error)
        } finally {
            job.cancel()
            driver.close()
        }
    }

    @Test
    fun testRefreshKeepsItemsVisibleWhileLoading() = runBlocking<Unit> {
        val driver = DatabaseDriverFactory().createDriver()
        val job = SupervisorJob()
        val scope = CoroutineScope(job)
        try {
            val database = AiPoseDatabase(driver)

            var callCount = 0
            val client = HttpClient(MockEngine) {
                engine {
                    addHandler { _ ->
                        callCount++
                        if (callCount == 1) {
                            respond(
                                """
                                    {
                                        "data": [
                                            {"id": "p1", "name": "Pose 1", "imagePath": "http://img1"}
                                        ],
                                        "pagination": {"page": 1, "limit": 20, "total": 1}
                                    }
                                """.trimIndent(),
                                HttpStatusCode.OK,
                                headersOf(HttpHeaders.ContentType, "application/json")
                            )
                        } else {
                            delay(300)
                            respond(
                                """
                                    {
                                        "data": [
                                            {"id": "p2", "name": "Pose 2", "imagePath": "http://img2"}
                                        ],
                                        "pagination": {"page": 1, "limit": 20, "total": 1}
                                    }
                                """.trimIndent(),
                                HttpStatusCode.OK,
                                headersOf(HttpHeaders.ContentType, "application/json")
                            )
                        }
                    }
                }
                install(ContentNegotiation) {
                    json(Json { ignoreUnknownKeys = true })
                }
            }
            val apiService = PoseApiService(client, "https://test.server")
            val repository = PoseRepository(database, apiService)
            val coordinator = PosesLibraryCoordinator(repository, apiService, scope)
            val viewModel = PosesViewModel(coordinator, scope)

            viewModel.loadCommunityPoses(refresh = false)
            val loaded = waitForState(viewModel) { it.communityState.items.isNotEmpty() }
            assertEquals("p1", loaded.communityState.items.first().poseId)

            // Trigger refresh; while in flight the previously loaded items stay visible.
            viewModel.loadCommunityPoses(refresh = true)
            val duringRefresh = waitForState(viewModel) {
                it.communityState.refreshState is OperationState.Loading
            }
            assertEquals(1, duringRefresh.communityState.items.size)
            assertEquals("p1", duringRefresh.communityState.items.first().poseId)

            // Refresh completes and replaces the items.
            val refreshed = waitForState(viewModel) {
                it.communityState.refreshState is OperationState.Idle &&
                    it.communityState.items.firstOrNull()?.poseId == "p2"
            }
            assertEquals("p2", refreshed.communityState.items.first().poseId)
        } finally {
            job.cancel()
            driver.close()
        }
    }

    @Test
    fun testUiStateCarriesOnlyBrowsingConcerns() = runBlocking<Unit> {
        val driver = DatabaseDriverFactory().createDriver()
        val job = SupervisorJob()
        val scope = CoroutineScope(job)
        try {
            val database = AiPoseDatabase(driver)
            val apiService = PoseApiService(buildMockClient(""), "https://test.server")
            val repository = PoseRepository(database, apiService)
            val coordinator = PosesLibraryCoordinator(repository, apiService, scope)
            val viewModel = PosesViewModel(coordinator, scope)

            val state = viewModel.uiState.value
            // WI-03 boundary: library UI state carries only browsing concerns.
            // FEAT-004 extraction orchestration (UploadState / onPickImageResult) is
            // not part of PosesViewModel; the Create Pose CTA stays a screen callback.
            assertEquals(emptyList<Pose>(), state.myPoses)
            assertEquals(CommunityLibraryState(), state.communityState)
            assertEquals(true, state.isLoading)
            assertEquals(0, state.selectedTab)
        } finally {
            job.cancel()
            driver.close()
        }
    }
}
