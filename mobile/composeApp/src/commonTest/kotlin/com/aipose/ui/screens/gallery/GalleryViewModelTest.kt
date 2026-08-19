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
import kotlin.test.assertFailsWith
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * WI-02 (Option A): gallery search filter — case-insensitive substring on
 * `Photo.poseName` OR linked `Pose.name` when `photo.poseId != null`.
 */
class GalleryViewModelTest {

    private fun clearDatabase(database: AiPoseDatabase) {
        database.photoQueries.getAllPhotos().executeAsList().forEach {
            database.photoQueries.deletePhoto(it.id)
        }
        database.poseQueries.getAllPoses().executeAsList().forEach {
            database.poseQueries.deletePose(it.id)
        }
    }

    private fun insertPose(database: AiPoseDatabase, name: String, createdAt: String = "100"): Long {
        database.poseQueries.insertPose(
            name = name,
            imagePath = "img-$name.jpg",
            thumbnailPath = null,
            originalImagePath = null,
            createdAt = createdAt,
            isMine = 1L,
            likes = 0L,
        )
        return database.poseQueries.getAllPoses().executeAsList().first { it.name == name }.id
    }

    private fun insertPhoto(
        database: AiPoseDatabase,
        poseName: String,
        imageTag: String = poseName,
        poseId: Long? = null,
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

    /** Filtered (grouped) photos the UI would actually render. */
    private fun GalleryUiState.filteredPhotos(): List<Photo> = groupedByDate.values.flatten()

    @Test
    fun emptyQueryReturnsAllPhotos() = runBlocking<Unit> {
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
            assertEquals(2, state.filteredPhotos().size)
            assertEquals("", state.searchQuery)
        } finally {
            job.cancel()
            driver.close()
        }
    }

    @Test
    fun queryMatchesPhotoPoseName() = runBlocking<Unit> {
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

            viewModel.setSearchQuery("warrior")
            val state = viewModel.uiState.value
            assertEquals(2, state.photos.size)
            assertEquals(listOf("Warrior Pose"), state.filteredPhotos().map { it.poseName })
            assertEquals("warrior", state.searchQuery)
        } finally {
            job.cancel()
            driver.close()
        }
    }

    @Test
    fun queryMatchesLinkedPoseNameWhenPoseIdNotNull() = runBlocking<Unit> {
        val driver = DatabaseDriverFactory().createDriver()
        val job = SupervisorJob()
        val scope = CoroutineScope(job + Dispatchers.Default)
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)

            // Photo snapshot poseName differs from the linked Pose.name; the
            // query must hit the linked Pose.name via poseId.
            val poseId = insertPose(database, name = "DANCING")
            insertPhoto(database, poseName = "My golden photo", imageTag = "a", poseId = poseId)
            insertPhoto(database, poseName = "Tree", imageTag = "b")

            val viewModel = GalleryViewModel(database)
            scope.launch { viewModel.load() }
            waitForLoaded(viewModel)

            viewModel.setSearchQuery("danCiNg")
            val state = viewModel.uiState.value
            val filtered = state.filteredPhotos()
            assertEquals(1, filtered.size)
            assertEquals("My golden photo", filtered.single().poseName)
        } finally {
            job.cancel()
            driver.close()
        }
    }

    @Test
    fun queryMatchesNeitherReturnsEmptyFilterResult() = runBlocking<Unit> {
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

            viewModel.setSearchQuery("cobra")
            val state = viewModel.uiState.value
            // photos stay unfiltered (source), grouped/filtered result is empty
            assertEquals(1, state.photos.size)
            assertTrue(state.filteredPhotos().isEmpty())
            assertTrue(state.groupedByDate.isEmpty())
        } finally {
            job.cancel()
            driver.close()
        }
    }

    @Test
    fun unmatchedPhotoWithNullPoseIdIsNotMatchedViaPoseNameOfOthers() = runBlocking<Unit> {
        val driver = DatabaseDriverFactory().createDriver()
        val job = SupervisorJob()
        val scope = CoroutineScope(job + Dispatchers.Default)
        try {
            val database = AiPoseDatabase(driver)
            clearDatabase(database)

            // A photo whose poseName doesn't contain the query has poseId == null,
            // so there is no linked Pose.name to fall back on → no match.
            insertPhoto(database, poseName = "Whale", imageTag = "w")
            val poseId = insertPose(database, name = "Cobra")
            insertPhoto(database, poseName = "Cobra", imageTag = "c", poseId = poseId)

            val viewModel = GalleryViewModel(database)
            scope.launch { viewModel.load() }
            waitForLoaded(viewModel)

            viewModel.setSearchQuery("cobra")
            val state = viewModel.uiState.value
            assertEquals(listOf("Cobra"), state.filteredPhotos().map { it.poseName })
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

            // DEL-UI-01: a failing delete must surface the repository failure
            // to the caller (GalleryScreen wraps this in try/catch to show a
            // snackbar) — never a silent success. A non-existent photo makes
            // the repository restore-and-rethrow path observable here.
            assertFailsWith<NoSuchElementException> { viewModel.deletePhoto(9999L) }

            // The existing photo is untouched → UI state stays recoverable
            // for retry.
            val state = viewModel.uiState.value
            assertEquals(1, state.photos.size)
            assertEquals("Warrior Pose", state.photos.single().poseName)
        } finally {
            job.cancel()
            driver.close()
        }
    }
}
