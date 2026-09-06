package com.aipose.ui.screens.poses

import com.aipose.data.DatabaseDriverFactory
import com.aipose.data.PoseRepository
import com.aipose.data.PoseServiceLocator
import com.aipose.data.PoseStorage
import com.aipose.data.auth.SessionCredentials
import com.aipose.data.remote.CommunityPose
import com.aipose.data.remote.PoseApiService
import com.aipose.data.AiPoseDatabase
import io.ktor.client.*
import io.ktor.client.engine.mock.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.http.*
import io.ktor.serialization.kotlinx.json.*
import io.ktor.utils.io.*
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import kotlin.coroutines.coroutineContext
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.serialization.json.Json
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.assertNull
import kotlin.test.assertNotNull
import kotlin.test.assertFalse

class PoseDetailViewModelTest {

    private suspend fun testViewModelScope(): CoroutineScope {
        val dispatcher = coroutineContext[CoroutineDispatcher] ?: Dispatchers.Default
        return CoroutineScope(SupervisorJob() + dispatcher)
    }

    @AfterTest
    fun tearDownSession() {
        PoseServiceLocator.sessionBoundary.tokenStorage.clearCredentials()
    }

    private inline fun withSignedInSession(block: () -> Unit) {
        val storage = PoseServiceLocator.sessionBoundary.tokenStorage
        storage.saveCredentials(SessionCredentials("access-test", "refresh-test"))
        try {
            block()
        } finally {
            storage.clearCredentials()
        }
    }

    private fun buildMockClient(handler: MockRequestHandler): HttpClient {
        return HttpClient(MockEngine) {
            engine {
                addHandler(handler)
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

    private suspend fun waitForState(
        viewModel: PoseDetailViewModel,
        predicate: (PoseDetailUiState) -> Boolean
    ): PoseDetailUiState {
        var attempts = 0
        var state = viewModel.uiState.value
        while (!predicate(state) && attempts < 500) {
            platform.posix.usleep(10000u)
            delay(10)
            state = viewModel.uiState.value
            attempts++
        }
        return state
    }

    /** Minimal PNG: valid 8-byte signature plus a 1x1 IHDR header. */
    private val PNG_1PX_BYTES: ByteArray = byteArrayOf(
        0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR length + type
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // 1x1 dimensions
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4.toByte(), 0x89.toByte()
    )

    @Test
    fun testLoadLocalPoseSuccess() = runTest {
        val client = buildMockClient { _ ->
            respond(
                content = ByteReadChannel(""),
                status = HttpStatusCode.OK
            )
        }
        val apiService = PoseApiService(client, "https://test.server")
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val repository = PoseRepository(database, apiService)

            // Insert a dummy local pose
            repository.createPoseAfterExtraction("Personal T-Pose", "original-personal", "data:image/png;base64,iVBORw0KGgo=", "thumbnail-personal")
            val list = repository.getMyPoses().first()
            val createdId = list.first().poseId

            val key = createdId
            val viewModel = PoseDetailViewModel(key, repository, apiService, viewModelScope = testViewModelScope())

            val job = launch {
                viewModel.load()
            }
            val state = waitForState(viewModel) { it is PoseDetailUiState.Success }

            assertTrue(state is PoseDetailUiState.Success)
            assertEquals("Personal T-Pose", state.name)
            assertEquals("data:image/png;base64,iVBORw0KGgo=", state.skeletonPath)
            assertTrue(state.isMine)
            // Canonical Pose always carries its owner account.
            assertNull(state.difficulty)
            assertEquals("00000000-0000-0000-0000-000000000001", state.author)

            job.cancel()
        } finally {
            driver.close()
        }
    }

    @Test
    fun signedOutSaveCanBeRequestedAgainAfterDismissal() = runTest {
        PoseServiceLocator.sessionBoundary.tokenStorage.clearCredentials()
        val client = buildMockClient { error("projection should avoid a community detail request") }
        val apiService = PoseApiService(client, "https://test.server")
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val repository = PoseRepository(database, apiService)
            val viewModel = PoseDetailViewModel(
                poseId = "community-1",
                repository = repository,
                apiService = apiService,
                initialCommunityPose = CommunityPose(
                    poseId = "community-1",
                    name = "Tree Pose",
                    skeletonUrl = "https://img/tree.png",
                    thumbnailUrl = "https://img/tree-thumb.png",
                ),
                viewModelScope = testViewModelScope(),
            )

            viewModel.toggleSave()
            assertEquals(com.aipose.auth.SignInIntent.SAVE_POSE, viewModel.signInIntent.value)

            viewModel.clearSignInIntent()
            viewModel.toggleSave()
            assertEquals(com.aipose.auth.SignInIntent.SAVE_POSE, viewModel.signInIntent.value)
        } finally {
            driver.close()
        }
    }

    @Test
    fun projectedCommunityPoseLoadsWithoutDetailFetch() = runTest {
        var requests = 0
        val client = buildMockClient {
            requests++
            error("projected detail must not fetch")
        }
        val apiService = PoseApiService(client, "https://test.server")
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val repository = PoseRepository(database, apiService)
            val viewModel = PoseDetailViewModel(
                poseId = "community-2",
                repository = repository,
                apiService = apiService,
                initialCommunityPose = CommunityPose(
                    poseId = "community-2",
                    name = "Tree Pose",
                    skeletonUrl = "https://img/tree.png",
                    thumbnailUrl = "https://img/tree-thumb.png",
                ),
                viewModelScope = testViewModelScope(),
            )

            viewModel.load()

            val state = viewModel.uiState.value
            assertTrue(state is PoseDetailUiState.Success)
            assertEquals("Tree Pose", state.name)
            assertEquals(0, requests)
        } finally {
            driver.close()
        }
    }


    @Test
    fun testDeleteLocalPose() = runTest {
        val client = buildMockClient { _ -> respond(content = ByteReadChannel(""), status = HttpStatusCode.OK) }
        val apiService = PoseApiService(client, "https://test.server")
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val repository = PoseRepository(database, apiService)

            // Insert local pose
            repository.createPoseAfterExtraction("To Delete", "original-delete", "data:image/png;base64,iVBORw0KGgo=", "thumbnail-delete")
            val list = repository.getMyPoses().first()
            val createdId = list.first().poseId

            assertNotNull(repository.getPoseById(createdId).first())
            repository.deletePose(createdId)
            assertNull(repository.getPoseById(createdId).first())
        } finally {
            driver.close()
        }
    }

    @Test
    fun testCommunityDeleteIsGated() = runTest {
        val client = buildMockClient { _ ->
            respond(content = ByteReadChannel(""), status = HttpStatusCode.OK)
        }
        val apiService = PoseApiService(client, "https://test.server")
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val repository = PoseRepository(database, apiService)

            val key = "c-pose-1"
            val viewModel = PoseDetailViewModel(
                poseId = key,
                repository = repository,
                apiService = apiService,
                initialCommunityPose = CommunityPose(
                    poseId = key,
                    name = "Tree Pose",
                    skeletonUrl = "community/tree.png",
                    thumbnailUrl = "",
                ),
                viewModelScope = testViewModelScope(),
            )

            val job = launch {
                viewModel.load()
            }
            val state = waitForState(viewModel) { it is PoseDetailUiState.Success }
            assertTrue(state is PoseDetailUiState.Success)

            // Destructive delete is personal-only; community must refuse it.
            val deleteResult = viewModel.delete()
            assertTrue(!deleteResult)

            job.cancel()
        } finally {
            driver.close()
        }
    }

    @Test
    fun testTryPoseLocalSuccess() = runTest {
        val client = buildMockClient { _ -> respond(content = ByteReadChannel(""), status = HttpStatusCode.OK) }
        val apiService = PoseApiService(client, "https://test.server")
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val repository = PoseRepository(database, apiService)

            repository.createPoseAfterExtraction("Personal T-Pose", "original-personal", "data:image/png;base64,iVBORw0KGgo=", "thumbnail-personal")
            val list = repository.getMyPoses().first()
            val createdId = list.first().poseId

            val key = createdId
            val viewModel = PoseDetailViewModel(key, repository, apiService, viewModelScope = testViewModelScope())

            val job = launch {
                viewModel.load()
            }
            val state = waitForState(viewModel) { it is PoseDetailUiState.Success }
            assertTrue(state is PoseDetailUiState.Success)

            var emitted: com.aipose.data.PreparedPoseReference? = null
            viewModel.tryPose { emitted = it }

            assertNotNull(emitted)
            assertEquals(key, emitted!!.poseId)
            assertEquals("Personal T-Pose", emitted!!.poseName)
            // Verified data-URI render locator is preserved as-is.
            assertEquals("data:image/png;base64,iVBORw0KGgo=", emitted!!.skeletonPath)
            assertEquals(DetailActionState.Idle, viewModel.actionState.value)

            job.cancel()
        } finally {
            driver.close()
        }
    }

    @Test
    fun testTryPoseLocalUnreadableAssetStaysOnDetail() = runTest {
        val client = buildMockClient { _ -> respond(content = ByteReadChannel(""), status = HttpStatusCode.OK) }
        val apiService = PoseApiService(client, "https://test.server")
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val repository = PoseRepository(database, apiService)

            // Local file asset that cannot be resolved (does not exist on disk).
            repository.createPoseAfterExtraction("Broken Pose", "original-broken", "missing-asset.png", "thumbnail-broken")
            val list = repository.getMyPoses().first()
            val createdId = list.first().poseId

            val key = createdId
            val viewModel = PoseDetailViewModel(key, repository, apiService, viewModelScope = testViewModelScope())

            val job = launch {
                viewModel.load()
            }
            val state = waitForState(viewModel) { it is PoseDetailUiState.Success }
            assertTrue(state is PoseDetailUiState.Success)

            var emitted: com.aipose.data.PreparedPoseReference? = null
            viewModel.tryPose { emitted = it }

            // E4: stay on detail with a recoverable error, never navigate.
            assertNull(emitted)
            assertTrue(viewModel.actionState.value is DetailActionState.Error)

            job.cancel()
        } finally {
            driver.close()
        }
    }

    @Test
    fun testTryPoseCommunitySuccess() = runTest {
        withSignedInSession {
            val client = buildMockClient { request ->
                assertEquals("/community/tree.png", request.url.encodedPath)
                respond(
                    content = ByteReadChannel(PNG_1PX_BYTES),
                    status = HttpStatusCode.OK,
                    headers = headersOf(HttpHeaders.ContentType, "image/png")
                )
            }
        val apiService = PoseApiService(client, "https://test.server")
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val repository = PoseRepository(database, apiService)

            val key = "c-pose-1"
            val viewModel = PoseDetailViewModel(
                poseId = key,
                repository = repository,
                apiService = apiService,
                initialCommunityPose = CommunityPose(
                    poseId = key,
                    name = "Tree Pose",
                    skeletonUrl = "community/tree.png",
                    thumbnailUrl = "",
                ),
                viewModelScope = testViewModelScope(),
            )

            val job = launch {
                viewModel.load()
            }
            val state = waitForState(viewModel) { it is PoseDetailUiState.Success }
            assertTrue(state is PoseDetailUiState.Success)

            var emitted: com.aipose.data.PreparedPoseReference? = null
            viewModel.tryPose { emitted = it }

            assertNotNull(emitted)
            assertEquals(key, emitted!!.poseId)
            assertEquals("Tree Pose", emitted!!.poseName)
            // The render locator is a self-contained data URI built from the
            // verified downloaded bytes, not the remote URL.
            assertTrue(emitted!!.skeletonPath.startsWith("data:image/png;base64,"))
            assertEquals(DetailActionState.Idle, viewModel.actionState.value)

            job.cancel()
        } finally {
            driver.close()
        }
        }
    }

    @Test
    fun testTryPoseCommunityDownloadFailureStaysOnDetail() = runTest {
        withSignedInSession {
            val client = buildMockClient { request ->
                assertEquals("/community/tree.png", request.url.encodedPath)
                respond(
                    content = ByteReadChannel("""{"error":{"code":"NOT_FOUND","message":"Image not found"}}"""),
                    status = HttpStatusCode.NotFound,
                    headers = headersOf(HttpHeaders.ContentType, "application/json")
                )
            }
        val apiService = PoseApiService(client, "https://test.server")
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val repository = PoseRepository(database, apiService)

            val key = "c-pose-1"
            val viewModel = PoseDetailViewModel(
                poseId = key,
                repository = repository,
                apiService = apiService,
                initialCommunityPose = CommunityPose(
                    poseId = key,
                    name = "Tree Pose",
                    skeletonUrl = "community/tree.png",
                    thumbnailUrl = "",
                ),
                viewModelScope = testViewModelScope(),
            )

            val job = launch {
                viewModel.load()
            }
            val state = waitForState(viewModel) { it is PoseDetailUiState.Success }
            assertTrue(state is PoseDetailUiState.Success)

            var emitted: com.aipose.data.PreparedPoseReference? = null
            viewModel.tryPose { emitted = it }

            // E4: failed download keeps the user on detail with a recoverable error.
            assertNull(emitted)
            assertTrue(viewModel.actionState.value is DetailActionState.Error)

            job.cancel()
        } finally {
            driver.close()
        }
        }
    }

    @Test
    fun testTryPoseCommunityUndecodableImageStaysOnDetail() = runTest {
        withSignedInSession {
            val client = buildMockClient { request ->
                assertEquals("/community/tree.png", request.url.encodedPath)
                respond(
                    content = ByteReadChannel("not an image".encodeToByteArray()),
                    status = HttpStatusCode.OK,
                    headers = headersOf(HttpHeaders.ContentType, "image/png")
                )
            }
        val apiService = PoseApiService(client, "https://test.server")
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val repository = PoseRepository(database, apiService)

            val key = "c-pose-1"
            val viewModel = PoseDetailViewModel(
                poseId = key,
                repository = repository,
                apiService = apiService,
                initialCommunityPose = CommunityPose(
                    poseId = key,
                    name = "Tree Pose",
                    skeletonUrl = "community/tree.png",
                    thumbnailUrl = "",
                ),
                viewModelScope = testViewModelScope(),
            )

            val job = launch {
                viewModel.load()
            }
            val state = waitForState(viewModel) { it is PoseDetailUiState.Success }
            assertTrue(state is PoseDetailUiState.Success)

            var emitted: com.aipose.data.PreparedPoseReference? = null
            viewModel.tryPose { emitted = it }

            // E4: downloaded bytes that fail structural decode keep the user on
            // detail instead of navigating with a stale/wrong overlay.
            assertNull(emitted)
            assertTrue(viewModel.actionState.value is DetailActionState.Error)

            job.cancel()
        } finally {
            driver.close()
        }
        }
    }

    @Test
    fun testDoubleDeleteIgnoredWhileInFlight() = runTest {
        val client = buildMockClient { _ -> respond(content = ByteReadChannel(""), status = HttpStatusCode.OK) }
        val apiService = PoseApiService(client, "https://test.server")
        val driver = DatabaseDriverFactory().createDriver()
        val scope = CoroutineScope(Dispatchers.Default)
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)

            var deleteCalls = 0
            val storage = object : PoseStorage {
                override fun delete(path: String) {
                    deleteCalls++
                    // Hold the delete in flight on a worker thread long enough to
                    // attempt a concurrent second confirm deterministically.
                    platform.posix.usleep(500_000u)
                }
                override fun exists(path: String): Boolean = true
                override fun isOwned(path: String): Boolean = true
            }
            val repository = PoseRepository(database, apiService, storage)
            repository.createPoseAfterExtraction("Dual Delete", "/documents/original-dual.jpg", "/documents/skeleton-dual.jpg", "/documents/thumbnail-dual.jpg")
            val id = repository.getMyPoses().first().first().poseId

            val viewModel = PoseDetailViewModel(id, repository, apiService, viewModelScope = testViewModelScope())
            val loadJob = scope.launch { viewModel.load() }
            var loadAttempts = 0
            while (viewModel.uiState.value !is PoseDetailUiState.Success && loadAttempts < 200) {
                platform.posix.usleep(10000u)
                loadAttempts++
            }
            assertTrue(viewModel.uiState.value is PoseDetailUiState.Success)
            loadJob.cancel()

            val firstDelete = scope.async { viewModel.delete() }

            var attempts = 0
            while (viewModel.actionState.value !is DetailActionState.Deleting && attempts < 200) {
                platform.posix.usleep(10000u)
                attempts++
            }
            assertTrue(viewModel.actionState.value is DetailActionState.Deleting)

            // A second confirm while deleting must be ignored, not start another delete.
            val secondResult = viewModel.delete()
            assertFalse(secondResult)
            assertEquals(1, deleteCalls)

            assertTrue(firstDelete.await())
            // Canonical deletion removes original, skeleton, and thumbnail media.
            assertEquals(3, deleteCalls)
            assertEquals(DetailActionState.Idle, viewModel.actionState.value)
            assertNull(repository.getPoseById(id).first())
        } finally {
            scope.cancel()
            driver.close()
        }
    }
}
