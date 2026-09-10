package com.aipose.ui.screens.gallery

import com.aipose.Photo
import com.aipose.data.AiPoseDatabase
import com.aipose.data.DatabaseDriverFactory
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

/**
 * Gallery state: photos load from the repository, group by date, filter by pose name,
 * and support selection/delete/favorite.
 */
class GalleryViewModelTest {

    private fun clearDatabase(database: AiPoseDatabase) {
        database.photoQueries.getAllPhotos().executeAsList().forEach {
            database.photoQueries.deletePhoto(it.id)
        }
        database.poseQueries.getAllPoses().executeAsList().forEach {
            database.poseQueries.deletePose(it.poseId)
        }
    }

    private fun insertPhoto(
        database: AiPoseDatabase,
        poseName: String,
        imageTag: String = poseName,
        poseId: String? = null,
        createdAt: String = "200",
    ) {
        database.photoQueries.insertPhoto(
            imagePath = "img-$imageTag.jpg",
            poseId = poseId,
            poseName = poseName,
            createdAt = createdAt,
            isFavorite = 0L,
        )
    }

    private fun insertLocalPose(
        database: AiPoseDatabase,
        poseId: String,
        name: String,
    ) {
        database.poseQueries.insertPose(
            poseId = poseId,
            ownerAccountId = "00000000-0000-0000-0000-000000000001",
            name = name,
            description = null,
            tags = "[]",
            difficulty = null,
            bodyParts = "[]",
            status = "local",
            originalPath = "orig-$poseId.jpg",
            skeletonPath = "skel-$poseId.jpg",
            thumbnailPath = "thumb-$poseId.jpg",
            currentJobId = null,
            createdAt = "100",
            updatedAt = "100",
        )
    }

    private suspend fun waitForLoaded(
        viewModel: GalleryViewModel,
    ): GalleryUiState {
        var attempts = 0
        var state = viewModel.uiState.value
        while (state.isLoading && attempts < 200) {
            delay(10)
            state = viewModel.uiState.value
            attempts++
        }
        return state
    }

    /** All photos grouped under their date sections (grid renders these). */
    private fun GalleryUiState.groupedPhotos(): List<Photo> = groupedByDate.values.flatten()

    @Test
    fun loadsAllPhotosAndGroupsByDate() = runBlocking<Unit> {
        val driver = DatabaseDriverFactory().createDriver()
        val job = SupervisorJob()
        val scope = CoroutineScope(job + Dispatchers.Default)
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            insertPhoto(database, poseName = "Warrior Pose", imageTag = "a")
            insertPhoto(database, poseName = "Tree Pose", imageTag = "b")

            val viewModel = GalleryViewModel(database)
            scope.launch { viewModel.load() }
            waitForLoaded(viewModel)

            val state = viewModel.uiState.value
            assertEquals(2, state.photos.size)
            assertEquals(2, state.groupedPhotos().size)
            assertTrue(state.groupedByDate.isNotEmpty())
        } finally {
            job.cancel()
            driver.close()
        }
    }

    @Test
    fun filtersByStoredPoseNameCaseInsensitively() = runBlocking<Unit> {
        val driver = DatabaseDriverFactory().createDriver()
        val job = SupervisorJob()
        val scope = CoroutineScope(job + Dispatchers.Default)
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            insertPhoto(database, poseName = "Warrior Pose", imageTag = "a")
            insertPhoto(database, poseName = "Tree Pose", imageTag = "b")

            val viewModel = GalleryViewModel(database)
            scope.launch { viewModel.load() }
            waitForLoaded(viewModel)

            viewModel.onQueryChange("warrior")
            val state = viewModel.uiState.value
            assertEquals(2, state.photos.size)
            assertEquals(1, state.groupedPhotos().size)
            assertEquals("Warrior Pose", state.groupedPhotos().single().poseName)
        } finally {
            job.cancel()
            driver.close()
        }
    }

    @Test
    fun filtersByLinkedLocalPoseNameWhenStoredNameBlank() = runBlocking<Unit> {
        val driver = DatabaseDriverFactory().createDriver()
        val job = SupervisorJob()
        val scope = CoroutineScope(job + Dispatchers.Default)
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            insertLocalPose(database, poseId = "local-1", name = "Linked Warrior")
            insertPhoto(database, poseName = "", imageTag = "a", poseId = "local-1")

            val viewModel = GalleryViewModel(database)
            scope.launch { viewModel.load() }
            waitForLoaded(viewModel)

            viewModel.onQueryChange("linked")
            val state = viewModel.uiState.value
            assertEquals(1, state.photos.size)
            assertEquals(1, state.groupedPhotos().size)
        } finally {
            job.cancel()
            driver.close()
        }
    }

    @Test
    fun excludesUnresolvedLinkWithEmptyStoredNameFromFilterResults() = runBlocking<Unit> {
        val driver = DatabaseDriverFactory().createDriver()
        val job = SupervisorJob()
        val scope = CoroutineScope(job + Dispatchers.Default)
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            insertPhoto(database, poseName = "", imageTag = "orphan", poseId = "published-not-local")
            insertPhoto(database, poseName = "Visible Warrior", imageTag = "visible")

            val viewModel = GalleryViewModel(database)
            scope.launch { viewModel.load() }
            waitForLoaded(viewModel)
            assertEquals(2, viewModel.uiState.value.photos.size)

            viewModel.onQueryChange("warrior")
            val state = viewModel.uiState.value
            assertEquals(2, state.photos.size)
            assertEquals(1, state.groupedPhotos().size)
            assertEquals("Visible Warrior", state.groupedPhotos().single().poseName)
        } finally {
            job.cancel()
            driver.close()
        }
    }

    @Test
    fun metadataOnlyQueryDoesNotMatchUnrelatedPhotos() {
        val photo = Photo(
            id = 1L,
            imagePath = "img-a.jpg",
            poseId = null,
            poseName = "Warrior Pose",
            createdAt = "200",
            isFavorite = 0L,
        )
        val filtered = filterPhotosByPoseName(
            photos = listOf(photo),
            poseNameById = emptyMap(),
            query = "img-a",
        )
        assertTrue(filtered.isEmpty())
    }

    @Test
    fun blankQueryShowsAllPhotos() = runBlocking<Unit> {
        val driver = DatabaseDriverFactory().createDriver()
        val job = SupervisorJob()
        val scope = CoroutineScope(job + Dispatchers.Default)
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            insertPhoto(database, poseName = "Warrior Pose", imageTag = "a")
            insertPhoto(database, poseName = "Tree Pose", imageTag = "b")

            val viewModel = GalleryViewModel(database)
            scope.launch { viewModel.load() }
            waitForLoaded(viewModel)

            viewModel.onQueryChange("zzz")
            assertTrue(viewModel.uiState.value.groupedPhotos().isEmpty())

            viewModel.onQueryChange("")
            assertEquals(2, viewModel.uiState.value.groupedPhotos().size)
        } finally {
            job.cancel()
            driver.close()
        }
    }

    @Test
    fun reactiveUpdatesWhenPhotoOrPoseFlowEmits() = runBlocking<Unit> {
        val driver = DatabaseDriverFactory().createDriver()
        val job = SupervisorJob()
        val scope = CoroutineScope(job + Dispatchers.Default)
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            insertPhoto(database, poseName = "Alpha Pose", imageTag = "a")

            val viewModel = GalleryViewModel(database)
            scope.launch { viewModel.load() }
            waitForLoaded(viewModel)

            insertPhoto(database, poseName = "Beta Pose", imageTag = "b")
            waitForState(viewModel) { it.photos.size == 2 }

            insertLocalPose(database, poseId = "local-2", name = "Linked Beta")
            val photoId = database.photoQueries.getAllPhotos().executeAsList()
                .first { it.poseName == "Beta Pose" }.id
            database.photoQueries.insertPhoto(
                imagePath = "img-linked.jpg",
                poseId = "local-2",
                poseName = "",
                createdAt = "201",
                isFavorite = 0L,
            )
            waitForState(viewModel) { it.photos.size == 3 }

            viewModel.onQueryChange("linked")
            waitForState(viewModel) { it.groupedPhotos().size == 1 }
        } finally {
            job.cancel()
            driver.close()
        }
    }

    @Test
    fun loadRestartsAfterCancelAndPicksUpNewPhotos() = runBlocking<Unit> {
        val driver = DatabaseDriverFactory().createDriver()
        val job = SupervisorJob()
        val scope = CoroutineScope(job + Dispatchers.Default)
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            insertPhoto(database, poseName = "Warrior Pose", imageTag = "a")

            val viewModel = GalleryViewModel(database)
            val firstLoad = scope.launch { viewModel.load() }
            waitForLoaded(viewModel)
            assertEquals(1, viewModel.uiState.value.photos.size)

            firstLoad.cancel()
            firstLoad.join()

            insertPhoto(database, poseName = "Tree Pose", imageTag = "b")

            val secondLoad = scope.launch { viewModel.load() }
            waitForState(viewModel) { it.photos.size == 2 }
            secondLoad.cancel()
        } finally {
            job.cancel()
            driver.close()
        }
    }

    @Test
    fun selectPhotoSetsAndClearsSelection() = runBlocking<Unit> {
        val driver = DatabaseDriverFactory().createDriver()
        val job = SupervisorJob()
        val scope = CoroutineScope(job + Dispatchers.Default)
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            insertPhoto(database, poseName = "Warrior Pose", imageTag = "a")

            val viewModel = GalleryViewModel(database)
            scope.launch { viewModel.load() }
            waitForLoaded(viewModel)

            val photo = viewModel.uiState.value.photos.single()
            viewModel.selectPhoto(photo)
            assertEquals(photo, viewModel.uiState.value.selectedPhoto)

            viewModel.selectPhoto(null)
            assertEquals(null, viewModel.uiState.value.selectedPhoto)
        } finally {
            job.cancel()
            driver.close()
        }
    }

    @Test
    fun deletePhotoPropagatesRepositoryFailureAndKeepsStateRecoverable() = runBlocking<Unit> {
        val driver = DatabaseDriverFactory().createDriver()
        val job = SupervisorJob()
        val scope = CoroutineScope(job + Dispatchers.Default)
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            insertPhoto(database, poseName = "Warrior Pose", imageTag = "a")

            val viewModel = GalleryViewModel(database)
            scope.launch { viewModel.load() }
            waitForLoaded(viewModel)

            assertFailsWith<NoSuchElementException> { viewModel.deletePhoto(9999L) }

            val state = viewModel.uiState.value
            assertEquals(1, state.photos.size)
            assertEquals("Warrior Pose", state.photos.single().poseName)
        } finally {
            job.cancel()
            driver.close()
        }
    }

    @Test
    fun successfulDeleteRemovesPhotoFromStateBeforeDetailReturns() = runBlocking<Unit> {
        val driver = DatabaseDriverFactory().createDriver()
        val job = SupervisorJob()
        val scope = CoroutineScope(job + Dispatchers.Default)
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)
            insertPhoto(database, poseName = "Warrior Pose", imageTag = "a")
            insertPhoto(database, poseName = "Tree Pose", imageTag = "b")

            val viewModel = GalleryViewModel(database)
            scope.launch { viewModel.load() }
            waitForLoaded(viewModel)

            val deletedId = viewModel.uiState.value.photos.first().id
            viewModel.deletePhoto(deletedId)

            val state = viewModel.uiState.value
            assertEquals(1, state.photos.size)
            assertEquals(1, state.groupedPhotos().size)
            assertTrue(state.photos.none { it.id == deletedId })
        } finally {
            job.cancel()
            driver.close()
        }
    }

    private suspend fun waitForState(
        viewModel: GalleryViewModel,
        predicate: (GalleryUiState) -> Boolean,
    ): GalleryUiState {
        var attempts = 0
        var state = viewModel.uiState.value
        while (!predicate(state) && attempts < 200) {
            delay(10)
            state = viewModel.uiState.value
            attempts++
        }
        return state
    }
}
