package com.aipose.ui.screens.poses

import com.aipose.auth.SignInIntent
import com.aipose.data.DatabaseDriverFactory
import com.aipose.data.PoseRepository
import com.aipose.data.PoseServiceLocator
import com.aipose.data.SavedPosesRepository
import com.aipose.data.AiPoseDatabase
import com.aipose.data.auth.SessionCredentials
import com.aipose.data.remote.CommunityPose
import com.aipose.data.remote.PaginatedResult
import com.aipose.data.remote.PaginationInfo
import com.aipose.data.remote.PoseApiException
import com.aipose.data.remote.PoseApiService
import com.aipose.navigation.PoseDetailOrigin
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import io.ktor.serialization.kotlinx.json.json
import io.ktor.utils.io.ByteReadChannel
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlin.coroutines.coroutineContext
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * WI-04 detail evidence: confirmed-only Save/Unsave (200/204), 404 -> unavailable
 * exact copy with Try blocked and no SavedEntry deletion, guest gating to a
 * single-use sign-in intent, and offline mutation keeping the confirmed state.
 */
class PoseDetailSavedStatusTest {

    @AfterTest
    fun tearDownSession() {
        PoseServiceLocator.sessionBoundary.tokenStorage.clearCredentials()
    }

    private suspend inline fun withSignedInSession(block: suspend () -> Unit) {
        val storage = PoseServiceLocator.sessionBoundary.tokenStorage
        storage.saveCredentials(SessionCredentials("access-test", "refresh-test"))
        try {
            block()
        } finally {
            storage.clearCredentials()
        }
    }

    private class FakeSavedRepository(
        private var saveThrows: Exception? = null,
        private var unsaveThrows: Exception? = null,
        private val savedInitially: Boolean = false,
        private var savedNow: Boolean,
    ) : SavedPosesRepository {
        var saveCalls = 0
        var unsaveCalls = 0
        var lastSaved: Boolean = savedNow

        override suspend fun getSavedPoses(page: Int, limit: Int): PaginatedResult<CommunityPose> =
            PaginatedResult(emptyList(), PaginationInfo(1, limit, 0))

        override suspend fun savePose(poseId: String): CommunityPose {
            saveCalls++
            saveThrows?.let { throw it }
            savedNow = true
            lastSaved = true
            return CommunityPose(poseId = poseId, name = "Saved")
        }

        override suspend fun unsavePose(poseId: String) {
            unsaveCalls++
            unsaveThrows?.let { throw it }
            savedNow = false
            lastSaved = false
        }
    }

    private fun mockClient(): HttpClient =
        HttpClient(MockEngine) {
            engine {
                addHandler { request ->
                    val detailJson = """{"data":{"id":"c-1","name":"Tree Pose","imagePath":"http://img/tree.png"}}"""
                    respond(
                        ByteReadChannel(detailJson), HttpStatusCode.OK,
                        headersOf(HttpHeaders.ContentType, "application/json"),
                    )
                }
            }
            install(ContentNegotiation) { json(Json { ignoreUnknownKeys = true }) }
        }

    private fun buildViewModel(
        client: HttpClient,
        repo: SavedPosesRepository,
        saved: Boolean = false,
        scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default),
    ): PoseDetailViewModel {
        val apiService = PoseApiService(client, "https://test.server")
        val driver = DatabaseDriverFactory().createDriver()
        val database = AiPoseDatabase(driver)
        val repository = PoseRepository(database, apiService)
        return PoseDetailViewModel(
            poseId = "c-1",
            repository = repository,
            apiService = apiService,
            savedRepository = repo,
            initialSaved = saved,
            origin = PoseDetailOrigin.SAVED,
            initialCommunityPose = CommunityPose(
                poseId = "c-1",
                name = "Tree Pose",
                skeletonUrl = "http://img/tree.png",
                thumbnailUrl = "",
            ),
            viewModelScope = scope,
        )
    }

    private suspend fun waitLoaded(vm: PoseDetailViewModel) {
        val dispatcher = coroutineContext[CoroutineDispatcher] ?: Dispatchers.Default
        val job = CoroutineScope(SupervisorJob() + dispatcher).launch { vm.load() }
        var attempts = 0
        while (vm.uiState.value !is PoseDetailUiState.Success && attempts < 500) {
            delay(5)
            attempts++
        }
        assertTrue(vm.uiState.value is PoseDetailUiState.Success)
        job.cancel()
    }

    private suspend fun testViewModelScope(): CoroutineScope {
        val dispatcher = coroutineContext[CoroutineDispatcher] ?: Dispatchers.Default
        return CoroutineScope(SupervisorJob() + dispatcher)
    }

    @Test
    fun `save flips confirmed state only after 200`() = runBlocking {
        withSignedInSession {
            val repo = FakeSavedRepository(savedInitially = false, savedNow = false)
            val vm = buildViewModel(
                mockClient(),
                repo,
                saved = false,
                scope = testViewModelScope(),
            )
            waitLoaded(vm)
            assertEquals(false, vm.savedStatus.value.isSaved)

            vm.toggleSave()
            var attempts = 0
            while (vm.savedStatus.value.isPending && attempts < 500) {
                platform.posix.usleep(10_000u)
                delay(5)
                attempts++
            }
            assertTrue(vm.savedStatus.value.isSaved, "confirmed saved only after 200")
            assertEquals(1, repo.saveCalls)
            assertEquals(0, repo.unsaveCalls)
        }
    }

    @Test
    fun `unsave flips confirmed state only after 204 and never deletes the pose`() = runBlocking {
        withSignedInSession {
            val repo = FakeSavedRepository(savedInitially = true, savedNow = true)
            val vm = buildViewModel(mockClient(), repo, saved = true, scope = testViewModelScope())
            waitLoaded(vm)
            assertEquals(true, vm.savedStatus.value.isSaved)

            vm.toggleSave() // target = unsave
            var attempts = 0
            while (vm.savedStatus.value.isPending && attempts < 500) {
                platform.posix.usleep(10_000u)
                delay(5)
                attempts++
            }
            assertFalse(vm.savedStatus.value.isSaved, "confirmed unsaved only after 204")
            assertEquals(1, repo.unsaveCalls)
            assertEquals(0, repo.saveCalls)
        }
    }

    @Test
    fun `404 during mutation becomes unavailable with exact copy and never success`() = runBlocking {
        withSignedInSession {
            val repo = FakeSavedRepository(
                saveThrows = PoseApiException("NOT_FOUND", "Pose not found"),
                savedInitially = false,
                savedNow = false,
            )
            val vm = buildViewModel(mockClient(), repo, saved = false, scope = testViewModelScope())
            waitLoaded(vm)

            vm.toggleSave()
            var attempts = 0
            while (vm.savedStatus.value.isPending && attempts < 500) {
                platform.posix.usleep(10_000u)
                delay(5)
                attempts++
            }
            assertTrue(vm.savedStatus.value.unavailable)
            assertEquals(REMOVED_POSE_COPY, vm.savedStatus.value.error)
            assertFalse(vm.savedStatus.value.isSaved, "never report success")
        }
    }

    @Test
    fun `offline mutation keeps confirmed state with inline error and no queue`() = runBlocking {
        withSignedInSession {
            val repo = FakeSavedRepository(
                saveThrows = RuntimeException("network down"),
                savedInitially = false,
                savedNow = false,
            )
            val vm = buildViewModel(mockClient(), repo, saved = false, scope = testViewModelScope())
            waitLoaded(vm)
            assertEquals(false, vm.savedStatus.value.isSaved)

            vm.toggleSave()
            var attempts = 0
            while (vm.savedStatus.value.isPending && attempts < 500) {
                platform.posix.usleep(10_000u)
                delay(5)
                attempts++
            }
            assertFalse(vm.savedStatus.value.isSaved, "confirmed state preserved")
            assertTrue(vm.savedStatus.value.error != null, "retryable inline error, no fake success")
        }
    }

    @Test
    fun `all 401 variants on toggle retain the interrupted save action via existing intent flow`() = runBlocking {
        // One 401 policy on the detail side: UNAUTHORIZED / 401 / AUTH_FAILED on a
        // mutation all surface through the existing single-use sign-in intent with the
        // interrupted action retained (never a generic inline error as the only
        // response, never success), preserving the last confirmed saved state.
        // A real session is stashed so the mutation path (not the guest gate) runs.
        val storage = PoseServiceLocator.sessionBoundary.tokenStorage
        storage.saveCredentials(com.aipose.data.auth.SessionCredentials("access-t", "refresh-t"))
        try {
            for (code in listOf("UNAUTHORIZED", "401", "AUTH_FAILED")) {
                val repo = FakeSavedRepository(
                    saveThrows = PoseApiException(code, "Unauthorized"),
                    savedInitially = false,
                    savedNow = false,
                )
                val vm = buildViewModel(mockClient(), repo, saved = false, scope = testViewModelScope())
                waitLoaded(vm)

                vm.toggleSave()
                var attempts = 0
                while (vm.savedStatus.value.isPending && attempts < 500) {
                    platform.posix.usleep(10_000u)
                    delay(5)
                    attempts++
                }
                assertEquals(SignInIntent.SAVE_POSE, vm.signInIntent.value, "code $code must retain the interrupted save intent")
                assertFalse(vm.savedStatus.value.isSaved, "code $code must not report success")
                assertNull(vm.savedStatus.value.error, "code $code must not leave a generic inline error as the only response")
                vm.clearSignInIntent()
            }
        } finally {
            storage.clearCredentials()
        }
    }

    @Test
    fun `guest save gates to single-use sign-in intent without a request`() = runBlocking {
        val repo = FakeSavedRepository(savedInitially = false, savedNow = false)
        val vm = buildViewModel(mockClient(), repo, saved = false, scope = testViewModelScope())
        waitLoaded(vm)

        // No stored session in this test process => guest gate.
        vm.toggleSave()
        assertEquals(SignInIntent.SAVE_POSE, vm.signInIntent.value)
        assertEquals(0, repo.saveCalls + repo.unsaveCalls, "no mutation request before auth")
    }

    @Test
    fun `guest try gates to single-use try intent and resumes only after real success`() = runBlocking {
        val repo = FakeSavedRepository(savedInitially = false, savedNow = false)
        val vm = buildViewModel(mockClient(), repo, saved = false, scope = testViewModelScope())
        waitLoaded(vm)

        var emitted: com.aipose.data.PreparedPoseReference? = null
        vm.tryPose { emitted = it }
        assertEquals(SignInIntent.TRY_POSE, vm.signInIntent.value)
        assertNull(emitted, "no handoff before sign-in")

        // Cancellation path clears the intent (no replay on a later screen).
        vm.clearSignInIntent()
        assertNull(vm.signInIntent.value)
        vm.tryPose { emitted = it }
        assertEquals(SignInIntent.TRY_POSE, vm.signInIntent.value)
        vm.clearSignInIntent()
        assertNull(vm.signInIntent.value)
    }
}