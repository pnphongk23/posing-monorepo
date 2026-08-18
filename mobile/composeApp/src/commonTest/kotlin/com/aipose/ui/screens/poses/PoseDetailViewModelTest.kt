package com.aipose.ui.screens.poses

import com.aipose.data.DatabaseDriverFactory
import com.aipose.data.PoseReferenceKey
import com.aipose.data.PoseRepository
import com.aipose.data.PoseStorage
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
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.assertNull
import kotlin.test.assertNotNull
import kotlin.test.assertFalse

class PoseDetailViewModelTest {

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
            queries.deletePose(it.id)
        }
    }

    private suspend fun waitForState(
        viewModel: PoseDetailViewModel,
        predicate: (PoseDetailUiState) -> Boolean
    ): PoseDetailUiState {
        var attempts = 0
        var state = viewModel.uiState.value
        while (!predicate(state) && attempts < 100) {
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
    fun testLoadPersonalPoseSuccess() = runTest {
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

            // Insert a dummy personal pose
            repository.insertPose(name = "Personal T-Pose", imagePath = "data:image/png;base64,iVBORw0KGgo=")
            val list = repository.getMyPoses().first()
            val createdId = list.first().id

            val key = PoseReferenceKey.Personal(createdId)
            val viewModel = PoseDetailViewModel(key, repository, apiService)

            val job = launch {
                viewModel.load()
            }
            val state = waitForState(viewModel) { it is PoseDetailUiState.Success }

            assertTrue(state is PoseDetailUiState.Success)
            assertEquals("Personal T-Pose", state.name)
            assertEquals("data:image/png;base64,iVBORw0KGgo=", state.imagePath)
            assertTrue(state.isMine)
            // Personal poses have no author/difficulty/outline contract fields.
            assertNull(state.difficulty)
            assertNull(state.author)

            job.cancel()
        } finally {
            driver.close()
        }
    }

    @Test
    fun testLoadPersonalPoseNotFound() = runTest {
        val client = buildMockClient { _ -> respond(content = ByteReadChannel(""), status = HttpStatusCode.OK) }
        val apiService = PoseApiService(client, "https://test.server")
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val repository = PoseRepository(database, apiService)

            val key = PoseReferenceKey.Personal(9999L) // Non-existent ID
            val viewModel = PoseDetailViewModel(key, repository, apiService)

            val job = launch {
                viewModel.load()
            }
            val state = waitForState(viewModel) { it is PoseDetailUiState.NotFound }

            assertTrue(state is PoseDetailUiState.NotFound)

            job.cancel()
        } finally {
            driver.close()
        }
    }

    @Test
    fun testLoadCommunityPoseSuccess() = runTest {
        val client = buildMockClient { request ->
            assertEquals("/api/community/poses/c-pose-1", request.url.encodedPath)
            respond(
                content = ByteReadChannel("""
                    {
                        "data": {
                            "id": "c-pose-1",
                            "name": "Tree Pose",
                            "imagePath": "http://img/tree.png",
                            "thumbnailPath": "http://img/tree_thumb.png",
                            "difficulty": "beginner",
                            "tags": ["yoga"]
                        }
                    }
                """.trimIndent()),
                status = HttpStatusCode.OK,
                headers = headersOf(HttpHeaders.ContentType, "application/json")
            )
        }
        val apiService = PoseApiService(client, "https://test.server")
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val repository = PoseRepository(database, apiService)

            val key = PoseReferenceKey.Community("c-pose-1")
            val viewModel = PoseDetailViewModel(key, repository, apiService)

            val job = launch {
                viewModel.load()
            }
            val state = waitForState(viewModel) { it is PoseDetailUiState.Success }

            assertTrue(state is PoseDetailUiState.Success)
            assertEquals("Tree Pose", state.name)
            assertEquals("http://img/tree.png", state.imagePath)
            assertEquals("beginner", state.difficulty)
            assertTrue(!state.isMine)
            // Community pose records carry no author contract field.
            assertNull(state.author)

            job.cancel()
        } finally {
            driver.close()
        }
    }

    @Test
    fun testLoadCommunityPoseNotFound() = runTest {
        val client = buildMockClient { _ ->
            respond(
                content = ByteReadChannel("""{"error":{"code":"NOT_FOUND","message":"Pose not found"}}"""),
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

            val key = PoseReferenceKey.Community("non-existent")
            val viewModel = PoseDetailViewModel(key, repository, apiService)

            val job = launch {
                viewModel.load()
            }
            val state = waitForState(viewModel) { it is PoseDetailUiState.NotFound }

            // Missing/unpublished community records must not surface a
            // retryable error: recovery is back to the list, never a wrong record.
            assertTrue(state is PoseDetailUiState.NotFound)

            job.cancel()
        } finally {
            driver.close()
        }
    }

    @Test
    fun testLoadCommunityPoseRetryableError() = runTest {
        val client = buildMockClient { _ ->
            respond(
                content = ByteReadChannel("""{"error":{"code":"INTERNAL","message":"boom"}}"""),
                status = HttpStatusCode.InternalServerError,
                headers = headersOf(HttpHeaders.ContentType, "application/json")
            )
        }
        val apiService = PoseApiService(client, "https://test.server")
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val repository = PoseRepository(database, apiService)

            val key = PoseReferenceKey.Community("c-pose-1")
            val viewModel = PoseDetailViewModel(key, repository, apiService)

            val job = launch {
                viewModel.load()
            }
            val state = waitForState(viewModel) { it is PoseDetailUiState.Error }

            assertTrue(state is PoseDetailUiState.Error)
            assertEquals("boom", (state as PoseDetailUiState.Error).message)

            job.cancel()
        } finally {
            driver.close()
        }
    }

    @Test
    fun testDeletePersonalPose() = runTest {
        val client = buildMockClient { _ -> respond(content = ByteReadChannel(""), status = HttpStatusCode.OK) }
        val apiService = PoseApiService(client, "https://test.server")
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val repository = PoseRepository(database, apiService)

            // Insert local personal pose
            repository.insertPose(name = "To Delete", imagePath = "data:image/png;base64,iVBORw0KGgo=")
            val list = repository.getMyPoses().first()
            val createdId = list.first().id

            val key = PoseReferenceKey.Personal(createdId)
            val viewModel = PoseDetailViewModel(key, repository, apiService)

            // 1. Verify it exists first (using active job)
            val job1 = launch {
                viewModel.load()
            }
            val state1 = waitForState(viewModel) { it is PoseDetailUiState.Success }
            assertTrue(state1 is PoseDetailUiState.Success)
            
            // Cancel job1 BEFORE deletion to prevent concurrent SQLDelight query flow unregistration during write transaction
            job1.cancel()
            platform.posix.usleep(10000u)
            delay(10)

            // 2. Delete the record
            val deleteSuccess = viewModel.delete()
            assertTrue(deleteSuccess)

            // 3. Load again via a clean job to check that it is now NotFound
            val job2 = launch {
                viewModel.load()
            }
            val state2 = waitForState(viewModel) { it is PoseDetailUiState.NotFound }
            assertTrue(state2 is PoseDetailUiState.NotFound)

            job2.cancel()
        } finally {
            driver.close()
        }
    }

    @Test
    fun testCommunityDeleteIsGated() = runTest {
        val client = buildMockClient { _ ->
            respond(
                content = ByteReadChannel("""
                    {
                        "data": {
                            "id": "c-pose-1",
                            "name": "Tree Pose",
                            "imagePath": "http://img/tree.png"
                        }
                    }
                """.trimIndent()),
                status = HttpStatusCode.OK,
                headers = headersOf(HttpHeaders.ContentType, "application/json")
            )
        }
        val apiService = PoseApiService(client, "https://test.server")
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val repository = PoseRepository(database, apiService)

            val key = PoseReferenceKey.Community("c-pose-1")
            val viewModel = PoseDetailViewModel(key, repository, apiService)

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
    fun testTryPosePersonalSuccess() = runTest {
        val client = buildMockClient { _ -> respond(content = ByteReadChannel(""), status = HttpStatusCode.OK) }
        val apiService = PoseApiService(client, "https://test.server")
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val repository = PoseRepository(database, apiService)

            repository.insertPose(name = "Personal T-Pose", imagePath = "data:image/png;base64,iVBORw0KGgo=")
            val list = repository.getMyPoses().first()
            val createdId = list.first().id

            val key = PoseReferenceKey.Personal(createdId)
            val viewModel = PoseDetailViewModel(key, repository, apiService)

            val job = launch {
                viewModel.load()
            }
            val state = waitForState(viewModel) { it is PoseDetailUiState.Success }
            assertTrue(state is PoseDetailUiState.Success)

            var emitted: com.aipose.data.PreparedPoseReference? = null
            viewModel.tryPose { emitted = it }

            assertNotNull(emitted)
            assertEquals(key, emitted!!.key)
            assertEquals("Personal T-Pose", emitted!!.name)
            // Verified data-URI render locator is preserved as-is.
            assertEquals("data:image/png;base64,iVBORw0KGgo=", emitted!!.renderLocator)
            assertEquals(DetailActionState.Idle, viewModel.actionState.value)

            job.cancel()
        } finally {
            driver.close()
        }
    }

    @Test
    fun testTryPosePersonalUnreadableAssetStaysOnDetail() = runTest {
        val client = buildMockClient { _ -> respond(content = ByteReadChannel(""), status = HttpStatusCode.OK) }
        val apiService = PoseApiService(client, "https://test.server")
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val repository = PoseRepository(database, apiService)

            // Local file asset that cannot be resolved (does not exist on disk).
            repository.insertPose(name = "Broken Pose", imagePath = "missing-asset.png")
            val list = repository.getMyPoses().first()
            val createdId = list.first().id

            val key = PoseReferenceKey.Personal(createdId)
            val viewModel = PoseDetailViewModel(key, repository, apiService)

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
        val client = buildMockClient { request ->
            when (request.url.encodedPath) {
                "/api/community/poses/c-pose-1" -> respond(
                    content = ByteReadChannel("""
                        {
                            "data": {
                                "id": "c-pose-1",
                                "name": "Tree Pose",
                                "imagePath": "community/tree.png"
                            }
                        }
                    """.trimIndent()),
                    status = HttpStatusCode.OK,
                    headers = headersOf(HttpHeaders.ContentType, "application/json")
                )
                "/community/tree.png" -> respond(
                    content = ByteReadChannel(PNG_1PX_BYTES),
                    status = HttpStatusCode.OK,
                    headers = headersOf(HttpHeaders.ContentType, "image/png")
                )
                else -> respond(content = ByteReadChannel(""), status = HttpStatusCode.NotFound)
            }
        }
        val apiService = PoseApiService(client, "https://test.server")
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val repository = PoseRepository(database, apiService)

            val key = PoseReferenceKey.Community("c-pose-1")
            val viewModel = PoseDetailViewModel(key, repository, apiService)

            val job = launch {
                viewModel.load()
            }
            val state = waitForState(viewModel) { it is PoseDetailUiState.Success }
            assertTrue(state is PoseDetailUiState.Success)

            var emitted: com.aipose.data.PreparedPoseReference? = null
            viewModel.tryPose { emitted = it }

            assertNotNull(emitted)
            assertEquals(key, emitted!!.key)
            assertEquals("Tree Pose", emitted!!.name)
            // The render locator is a self-contained data URI built from the
            // verified downloaded bytes, not the remote URL.
            assertTrue(emitted!!.renderLocator.startsWith("data:image/png;base64,"))
            assertEquals(DetailActionState.Idle, viewModel.actionState.value)

            job.cancel()
        } finally {
            driver.close()
        }
    }

    @Test
    fun testTryPoseCommunityDownloadFailureStaysOnDetail() = runTest {
        val client = buildMockClient { request ->
            when (request.url.encodedPath) {
                "/api/community/poses/c-pose-1" -> respond(
                    content = ByteReadChannel("""
                        {
                            "data": {
                                "id": "c-pose-1",
                                "name": "Tree Pose",
                                "imagePath": "community/tree.png"
                            }
                        }
                    """.trimIndent()),
                    status = HttpStatusCode.OK,
                    headers = headersOf(HttpHeaders.ContentType, "application/json")
                )
                "/community/tree.png" -> respond(
                    content = ByteReadChannel("""{"error":{"code":"NOT_FOUND","message":"Image not found"}}"""),
                    status = HttpStatusCode.NotFound,
                    headers = headersOf(HttpHeaders.ContentType, "application/json")
                )
                else -> respond(content = ByteReadChannel(""), status = HttpStatusCode.NotFound)
            }
        }
        val apiService = PoseApiService(client, "https://test.server")
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val repository = PoseRepository(database, apiService)

            val key = PoseReferenceKey.Community("c-pose-1")
            val viewModel = PoseDetailViewModel(key, repository, apiService)

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

    @Test
    fun testTryPoseCommunityUndecodableImageStaysOnDetail() = runTest {
        val client = buildMockClient { request ->
            when (request.url.encodedPath) {
                "/api/community/poses/c-pose-1" -> respond(
                    content = ByteReadChannel("""
                        {
                            "data": {
                                "id": "c-pose-1",
                                "name": "Tree Pose",
                                "imagePath": "community/tree.png"
                            }
                        }
                    """.trimIndent()),
                    status = HttpStatusCode.OK,
                    headers = headersOf(HttpHeaders.ContentType, "application/json")
                )
                "/community/tree.png" -> respond(
                    content = ByteReadChannel("not an image".encodeToByteArray()),
                    status = HttpStatusCode.OK,
                    headers = headersOf(HttpHeaders.ContentType, "image/png")
                )
                else -> respond(content = ByteReadChannel(""), status = HttpStatusCode.NotFound)
            }
        }
        val apiService = PoseApiService(client, "https://test.server")
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val repository = PoseRepository(database, apiService)

            val key = PoseReferenceKey.Community("c-pose-1")
            val viewModel = PoseDetailViewModel(key, repository, apiService)

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
            repository.insertPose(name = "Dual Delete", imagePath = "/documents/dual.jpg")
            val id = repository.getMyPoses().first().first().id

            val viewModel = PoseDetailViewModel(PoseReferenceKey.Personal(id), repository, apiService)

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
            assertEquals(1, deleteCalls)
            assertEquals(DetailActionState.Idle, viewModel.actionState.value)
            assertNull(repository.getPoseById(id).first())
        } finally {
            scope.cancel()
            driver.close()
        }
    }
}
