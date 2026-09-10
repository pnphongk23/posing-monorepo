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
 * Gallery state: photos load from the repository, group by date, and support
 * selection/delete/favorite without an in-gallery search query.
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
    fun dateFilterLabelsMatchGalleryPrototype() {
        assertEquals(
            listOf("All", "Today", "7 days", "30 days", "Date"),
            galleryDateFilterLabels,
        )
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

            waitForState(viewModel) { it.groupedPhotos().size == 2 }
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
