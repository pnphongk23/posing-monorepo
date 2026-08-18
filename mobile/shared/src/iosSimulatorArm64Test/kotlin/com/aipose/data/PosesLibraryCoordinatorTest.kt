package com.aipose.data

import com.aipose.data.remote.CommunityPose
import com.aipose.data.remote.PoseApiException
import com.aipose.data.remote.PoseApiService
import com.aipose.data.remote.sharedJson
import io.ktor.client.*
import io.ktor.client.engine.mock.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.http.*
import io.ktor.serialization.kotlinx.json.*
import io.ktor.utils.io.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.assertFailsWith

class PosesLibraryCoordinatorTest {

    private fun buildMockClient(handler: MockRequestHandler): HttpClient {
        return HttpClient(MockEngine) {
            engine {
                addHandler(handler)
            }
            install(ContentNegotiation) {
                json(sharedJson)
            }
        }
    }

    private suspend fun awaitCommunitySettled(coordinator: PosesLibraryCoordinator) {
        repeat(200) {
            val state = coordinator.communityState.value
            val busy = state.initialLoadState is OperationState.Loading ||
                state.refreshState is OperationState.Loading ||
                state.loadMoreState is OperationState.Loading
            if (!busy) return
            delay(10)
        }
        error("Timed out waiting for community operations: ${coordinator.communityState.value}")
    }

    private fun clearDatabase(database: AiPoseDatabase) {
        val queries = database.poseQueries
        queries.getAllPoses().executeAsList().forEach {
            queries.deletePose(it.id)
        }
    }

    class FakePoseStorage : PoseStorage {
        var isOwnedFunc: (String) -> Boolean = { path ->
            !path.startsWith("http") && !path.startsWith("data:") && !path.contains("..") && !path.contains("//")
        }
        var existsFunc: (String) -> Boolean = { true }
        var deleteFunc: (String) -> Unit = {}

        override fun delete(path: String) = deleteFunc(path)
        override fun exists(path: String): Boolean = existsFunc(path)
        override fun isOwned(path: String): Boolean = isOwnedFunc(path)
    }

    @Test
    fun testInitialLoadSuccess() = runBlocking<Unit> {
        val client = buildMockClient { request ->
            respond(
                content = ByteReadChannel("""
                    {
                        "data": [
                            {"id": "p1", "name": "Pose 1", "imagePath": "http://img1", "difficulty": "beginner"},
                            {"id": "p2", "name": "Pose 2", "imagePath": "http://img2", "difficulty": "advanced"}
                        ],
                        "pagination": {
                            "page": 1,
                            "limit": 20,
                            "total": 2
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
            val coordinator = PosesLibraryCoordinator(repository, apiService, this)

            coordinator.loadCommunityInitial()
            awaitCommunitySettled(coordinator)

            val state = coordinator.communityState.value
            assertEquals(2, state.items.size)
            assertEquals("p1", state.items[0].id)
            assertEquals("p2", state.items[1].id)
            assertEquals(1, state.page)
            assertEquals(2, state.total)
            assertEquals(false, state.hasMore)
            assertTrue(state.initialLoadState is OperationState.Idle)
        } finally {
            client.close()
            driver.close()
        }
    }

    @Test
    fun testPaginationDeduplicationAndLoadMore() = runBlocking<Unit> {
        var callCount = 0
        val client = buildMockClient { request ->
            callCount++
            if (callCount == 1) {
                respond(
                    content = ByteReadChannel("""
                        {
                            "data": [
                                {"id": "p1", "name": "Pose 1", "imagePath": "http://img1"},
                                {"id": "p2", "name": "Pose 2", "imagePath": "http://img2"}
                            ],
                            "pagination": {
                                "page": 1,
                                "limit": 2,
                                "total": 4
                            }
                        }
                    """.trimIndent()),
                    status = HttpStatusCode.OK,
                    headers = headersOf(HttpHeaders.ContentType, "application/json")
                )
            } else {
                respond(
                    content = ByteReadChannel("""
                        {
                            "data": [
                                {"id": "p2", "name": "Pose 2", "imagePath": "http://img2"},
                                {"id": "p3", "name": "Pose 3", "imagePath": "http://img3"}
                            ],
                            "pagination": {
                                "page": 2,
                                "limit": 2,
                                "total": 4
                            }
                        }
                    """.trimIndent()),
                    status = HttpStatusCode.OK,
                    headers = headersOf(HttpHeaders.ContentType, "application/json")
                )
            }
        }

        val apiService = PoseApiService(client, "https://test.server")
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val repository = PoseRepository(database, apiService)
            val coordinator = PosesLibraryCoordinator(repository, apiService, this)

            // Initial load
            coordinator.loadCommunityInitial()
            awaitCommunitySettled(coordinator)

            assertEquals(2, coordinator.communityState.value.items.size)
            assertTrue(coordinator.communityState.value.hasMore)

            // Load more (should deduplicate "p2")
            coordinator.loadMoreCommunity()
            awaitCommunitySettled(coordinator)

            val state = coordinator.communityState.value
            assertEquals(3, state.items.size)
            assertEquals("p1", state.items[0].id)
            assertEquals("p2", state.items[1].id)
            assertEquals("p3", state.items[2].id)
            assertEquals(2, state.page)
            assertEquals(4, state.total)
            assertEquals(false, state.hasMore) // 2 * 2 = 4 (limit * page = total)
        } finally {
            client.close()
            driver.close()
        }
    }

    @Test
    fun testFailureRetentionAndRecovery() = runBlocking<Unit> {
        var shouldFail = false
        val client = buildMockClient { request ->
            if (shouldFail) {
                respond(
                    content = ByteReadChannel("""{"error":{"code":"SERVER_ERROR","message":"DB failed"}}"""),
                    status = HttpStatusCode.InternalServerError,
                    headers = headersOf(HttpHeaders.ContentType, "application/json")
                )
            } else {
                respond(
                    content = ByteReadChannel("""
                        {
                            "data": [{"id": "p1", "name": "Pose 1", "imagePath": "http://img1"}],
                            "pagination": {
                                "page": 1,
                                "limit": 1,
                                "total": 2
                            }
                        }
                    """.trimIndent()),
                    status = HttpStatusCode.OK,
                    headers = headersOf(HttpHeaders.ContentType, "application/json")
                )
            }
        }

        val apiService = PoseApiService(client, "https://test.server")
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val repository = PoseRepository(database, apiService)
            val coordinator = PosesLibraryCoordinator(repository, apiService, this)

            // Initial load success
            coordinator.loadCommunityInitial()
            awaitCommunitySettled(coordinator)

            assertEquals(1, coordinator.communityState.value.items.size)
            assertTrue(coordinator.communityState.value.hasMore)

            // Load more failure
            shouldFail = true
            coordinator.loadMoreCommunity()
            awaitCommunitySettled(coordinator)

            val stateAfterFail = coordinator.communityState.value
            assertEquals(1, stateAfterFail.items.size)
            assertTrue(stateAfterFail.loadMoreState is OperationState.Error)
            assertEquals("DB failed", (stateAfterFail.loadMoreState as OperationState.Error).message)

            // Recover load more
            shouldFail = false
            coordinator.loadMoreCommunity()
            awaitCommunitySettled(coordinator)

            val stateRecovered = coordinator.communityState.value
            assertTrue(stateRecovered.loadMoreState is OperationState.Idle)
            assertEquals(1, stateRecovered.items.size)
        } finally {
            client.close()
            driver.close()
        }
    }

    @Test
    fun testStaleCompletionsIgnored() = runBlocking<Unit> {
        var callCount = 0
        val client = buildMockClient { request ->
            callCount++
            if (callCount == 2) {
                delay(200)
                respond(
                    content = ByteReadChannel("""
                        {
                            "data": [{"id": "p_stale", "name": "Stale", "imagePath": "http://img"}],
                            "pagination": {"page": 2, "limit": 2, "total": 4}
                        }
                    """.trimIndent()),
                    status = HttpStatusCode.OK,
                    headers = headersOf(HttpHeaders.ContentType, "application/json")
                )
            } else {
                respond(
                    content = ByteReadChannel("""
                        {
                            "data": [{"id": "p_fresh", "name": "Fresh", "imagePath": "http://img"}],
                            "pagination": {"page": 1, "limit": 2, "total": 4}
                        }
                    """.trimIndent()),
                    status = HttpStatusCode.OK,
                    headers = headersOf(HttpHeaders.ContentType, "application/json")
                )
            }
        }

        val apiService = PoseApiService(client, "https://test.server")
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val repository = PoseRepository(database, apiService)
            val coordinator = PosesLibraryCoordinator(repository, apiService, this)

            coordinator.loadCommunityInitial()
            awaitCommunitySettled(coordinator)
            assertEquals("p_fresh", coordinator.communityState.value.items[0].id)
            assertTrue(coordinator.communityState.value.hasMore)

            coordinator.loadMoreCommunity()
            run {
                repeat(50) {
                    if (coordinator.communityState.value.loadMoreState is OperationState.Loading) return@run
                    delay(10)
                }
            }
            delay(30)

            coordinator.refreshCommunity()
            awaitCommunitySettled(coordinator)
            delay(250)

            val finalState = coordinator.communityState.value
            assertEquals(1, finalState.items.size)
            assertEquals("p_fresh", finalState.items[0].id)
        } finally {
            client.close()
            driver.close()
        }
    }

    @Test
    fun testUnknownFieldsTolerated() = runBlocking<Unit> {
        val client = buildMockClient { request ->
            respond(
                content = ByteReadChannel("""
                    {
                        "data": [
                            {"id": "p1", "name": "Pose 1", "imagePath": "http://img1", "unknown_key_1": 1234, "nested": {"key": "val"}}
                        ],
                        "pagination": {
                            "page": 1,
                            "limit": 20,
                            "total": 1
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
            val coordinator = PosesLibraryCoordinator(repository, apiService, this)

            coordinator.loadCommunityInitial()
            awaitCommunitySettled(coordinator)

            val state = coordinator.communityState.value
            assertEquals(1, state.items.size)
            assertEquals("p1", state.items[0].id)
        } finally {
            client.close()
            driver.close()
        }
    }

    @Test
    fun testNestedErrorHandling() = runBlocking<Unit> {
        val client = buildMockClient { request ->
            respond(
                content = ByteReadChannel("""
                    {
                        "error": {
                            "code": "INVALID_PARAMS",
                            "message": "Invalid page parameter"
                        }
                    }
                """.trimIndent()),
                status = HttpStatusCode.BadRequest,
                headers = headersOf(HttpHeaders.ContentType, "application/json")
            )
        }

        val apiService = PoseApiService(client, "https://test.server")
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val repository = PoseRepository(database, apiService)
            val coordinator = PosesLibraryCoordinator(repository, apiService, this)

            coordinator.loadCommunityInitial()
            awaitCommunitySettled(coordinator)

            val state = coordinator.communityState.value
            assertTrue(state.initialLoadState is OperationState.Error)
            assertEquals("Invalid page parameter", (state.initialLoadState as OperationState.Error).message)
        } finally {
            client.close()
            driver.close()
        }
    }

    @Test
    fun testExactLastPage() = runBlocking<Unit> {
        val client = buildMockClient { request ->
            respond(
                content = ByteReadChannel("""
                    {
                        "data": [
                            {"id": "p1", "name": "Pose 1", "imagePath": "http://img1"},
                            {"id": "p2", "name": "Pose 2", "imagePath": "http://img2"}
                        ],
                        "pagination": {
                            "page": 1,
                            "limit": 2,
                            "total": 2
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
            val coordinator = PosesLibraryCoordinator(repository, apiService, this)

            coordinator.loadCommunityInitial()
            awaitCommunitySettled(coordinator)

            val state = coordinator.communityState.value
            assertEquals(2, state.items.size)
            assertEquals(false, state.hasMore)
        } finally {
            client.close()
            driver.close()
        }
    }

    @Test
    fun testEmptyCatalog() = runBlocking<Unit> {
        val client = buildMockClient { request ->
            respond(
                content = ByteReadChannel("""
                    {
                        "data": [],
                        "pagination": {
                            "page": 1,
                            "limit": 20,
                            "total": 0
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
            val coordinator = PosesLibraryCoordinator(repository, apiService, this)

            coordinator.loadCommunityInitial()
            awaitCommunitySettled(coordinator)

            val state = coordinator.communityState.value
            assertEquals(0, state.items.size)
            assertEquals(false, state.hasMore)
        } finally {
            client.close()
            driver.close()
        }
    }

    @Test
    fun testRefreshReplacement() = runBlocking<Unit> {
        var callCount = 0
        val client = buildMockClient { request ->
            callCount++
            if (callCount == 1) {
                respond(
                    content = ByteReadChannel("""
                        {
                            "data": [{"id": "p1", "name": "Pose 1", "imagePath": "http://img1"}],
                            "pagination": {"page": 1, "limit": 20, "total": 1}
                        }
                    """.trimIndent()),
                    status = HttpStatusCode.OK,
                    headers = headersOf(HttpHeaders.ContentType, "application/json")
                )
            } else {
                respond(
                    content = ByteReadChannel("""
                        {
                            "data": [{"id": "p2", "name": "Pose 2", "imagePath": "http://img2"}],
                            "pagination": {"page": 1, "limit": 20, "total": 1}
                        }
                    """.trimIndent()),
                    status = HttpStatusCode.OK,
                    headers = headersOf(HttpHeaders.ContentType, "application/json")
                )
            }
        }

        val apiService = PoseApiService(client, "https://test.server")
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val repository = PoseRepository(database, apiService)
            val coordinator = PosesLibraryCoordinator(repository, apiService, this)

            coordinator.loadCommunityInitial()
            awaitCommunitySettled(coordinator)

            assertEquals("p1", coordinator.communityState.value.items[0].id)

            coordinator.refreshCommunity()
            awaitCommunitySettled(coordinator)

            val state = coordinator.communityState.value
            assertEquals(1, state.items.size)
            assertEquals("p2", state.items[0].id)
        } finally {
            client.close()
            driver.close()
        }
    }

    @Test
    fun testDeletionSuccess() = runTest {
        val driver = DatabaseDriverFactory().createDriver()
        val fakeStorage = FakePoseStorage()
        fakeStorage.existsFunc = { true }
        var deletedPath: String? = null
        fakeStorage.deleteFunc = { deletedPath = it }

        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val queries = database.poseQueries
            val repository = PoseRepository(database, null, fakeStorage)

            repository.insertPose("Pose A", "/documents/pose_a.jpg", isMine = true)
            val posesBefore = queries.getAllPoses().executeAsList()
            assertEquals(1, posesBefore.size)
            val targetId = posesBefore[0].id

            repository.deletePose(targetId)

            val posesAfter = queries.getAllPoses().executeAsList()
            assertEquals(0, posesAfter.size)
            assertEquals("/documents/pose_a.jpg", deletedPath)
        } finally {
            driver.close()
        }
    }

    @Test
    fun testDeletionMissingRecord() = runTest {
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val repository = PoseRepository(database, null, FakePoseStorage())

            assertFailsWith<NoSuchElementException> {
                repository.deletePose(9999L)
            }
        } finally {
            driver.close()
        }
    }

    @Test
    fun testDeletionMissingFile() = runTest {
        val driver = DatabaseDriverFactory().createDriver()
        val fakeStorage = FakePoseStorage()
        fakeStorage.existsFunc = { false } // file is missing
        var deletedCalled = false
        fakeStorage.deleteFunc = { deletedCalled = true }

        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val queries = database.poseQueries
            val repository = PoseRepository(database, null, fakeStorage)

            repository.insertPose("Pose B", "/documents/pose_b.jpg", isMine = true)
            val targetId = queries.getAllPoses().executeAsOne().id

            repository.deletePose(targetId)

            // Even if the file is missing, the metadata is deleted successfully (idempotent missing-file semantics)
            val posesAfter = queries.getAllPoses().executeAsList()
            assertEquals(0, posesAfter.size)
            assertEquals(false, deletedCalled)
        } finally {
            driver.close()
        }
    }

    @Test
    fun testDeletionEmbeddedData() = runTest {
        val driver = DatabaseDriverFactory().createDriver()
        val fakeStorage = FakePoseStorage()
        fakeStorage.isOwnedFunc = { false } // embedded data URI is not owned
        var deletedCalled = false
        fakeStorage.deleteFunc = { deletedCalled = true }

        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val queries = database.poseQueries
            val repository = PoseRepository(database, null, fakeStorage)

            repository.insertPose("Pose C", "data:image/png;base64,123", isMine = true)
            val targetId = queries.getAllPoses().executeAsOne().id

            repository.deletePose(targetId)

            val posesAfter = queries.getAllPoses().executeAsList()
            assertEquals(0, posesAfter.size)
            assertEquals(false, deletedCalled)
        } finally {
            driver.close()
        }
    }

    @Test
    fun testDeletionPermissionFailure() = runTest {
        val driver = DatabaseDriverFactory().createDriver()
        val fakeStorage = FakePoseStorage()
        fakeStorage.existsFunc = { true }
        fakeStorage.deleteFunc = { throw RuntimeException("Permission Denied") }

        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val queries = database.poseQueries
            val repository = PoseRepository(database, null, fakeStorage)

            repository.insertPose("Pose D", "/documents/pose_d.jpg", isMine = true)
            val targetId = queries.getAllPoses().executeAsOne().id

            assertFailsWith<RuntimeException> {
                repository.deletePose(targetId)
            }

            // Verify that metadata is compensated/restored because of the file deletion failure!
            val posesAfter = queries.getAllPoses().executeAsList()
            assertEquals(1, posesAfter.size)
            assertEquals("Pose D", posesAfter[0].name)
        } finally {
            driver.close()
        }
    }

    @Test
    fun testDeletionCompensationFailure() = runTest {
        val driver = DatabaseDriverFactory().createDriver()
        val fakeStorage = FakePoseStorage()
        fakeStorage.existsFunc = { true }
        fakeStorage.deleteFunc = {
            // Close the database driver here to cause compensation insert to fail!
            driver.close()
            throw RuntimeException("File deletion error")
        }

        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            val queries = database.poseQueries
            val repository = PoseRepository(database, null, fakeStorage)

            repository.insertPose("Pose E", "/documents/pose_e.jpg", isMine = true)
            val targetId = queries.getAllPoses().executeAsOne().id

            assertFailsWith<IllegalStateException> {
                repository.deletePose(targetId)
            }
        } finally {
            // driver is already closed inside deleteFunc
        }
    }
}
