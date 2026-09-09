package com.aipose.ui.screens.gallery

import com.aipose.Photo
import com.aipose.data.AiPoseDatabase
import com.aipose.data.DatabaseDriverFactory
import com.aipose.data.PhotoRepository
import com.aipose.data.createDatabase
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.update
import kotlinx.datetime.Clock

data class GalleryUiState(
    val photos: List<Photo> = emptyList(),
    val groupedByDate: Map<String, List<Photo>> = emptyMap(),
    val isLoading: Boolean = true,
    val selectedPhoto: Photo? = null,
)

class GalleryViewModel(
    database: AiPoseDatabase = createDatabase(DatabaseDriverFactory()),
    private val repository: PhotoRepository = PhotoRepository(database),
) {
    private val _uiState = MutableStateFlow(GalleryUiState())
    val uiState: StateFlow<GalleryUiState> = _uiState.asStateFlow()

    suspend fun load() {
        repository.getAllPhotos().collectLatest { photos ->
            _uiState.update {
                it.copy(
                    photos = photos,
                    groupedByDate = groupPhotosByDate(photos),
                    isLoading = false,
                )
            }
        }
    }

    suspend fun deletePhoto(id: Long) {
        repository.deletePhoto(id)

        // The list's flow collector is cancelled while Voyager shows detail.
        // Apply the successful deletion locally before returning so the list is
        // already consistent when detail is popped; a later DB emission keeps
        // this state authoritative if the list is still visible.
        _uiState.update { currentState ->
            val remainingPhotos = currentState.photos.filterNot { it.id == id }
            currentState.copy(
                photos = remainingPhotos,
                groupedByDate = groupPhotosByDate(remainingPhotos),
                selectedPhoto = currentState.selectedPhoto?.takeUnless { it.id == id },
            )
        }
    }

    suspend fun toggleFavorite(id: Long) {
        repository.toggleFavorite(id)
    }

    fun selectPhoto(photo: Photo?) {
        _uiState.value = _uiState.value.copy(selectedPhoto = photo)
    }

    private fun groupPhotosByDate(photos: List<Photo>): Map<String, List<Photo>> {
        val nowMillis = Clock.System.now().toEpochMilliseconds()
        val todayStart = floorToUtcDay(nowMillis)
        val yesterdayStart = todayStart - MILLIS_PER_DAY

        val sortedPhotos = photos.sortedByDescending { galleryPhotoEpochMillis(it.createdAt) ?: Long.MIN_VALUE }
        val intermediate = LinkedHashMap<String, MutableList<Photo>>()

        for (photo in sortedPhotos) {
            val millis = galleryPhotoEpochMillis(photo.createdAt) ?: 0L
            val dayStart = floorToUtcDay(millis)
            val key = when {
                dayStart >= todayStart -> "TODAY"
                dayStart >= yesterdayStart -> "YESTERDAY"
                else -> formatMonthDay(millis)
            }
            intermediate.getOrPut(key) { mutableListOf() }.add(photo)
        }

        // Ensure TODAY and YESTERDAY appear first (others already sorted desc)
        val result = LinkedHashMap<String, List<Photo>>()
        if (intermediate.containsKey("TODAY")) result["TODAY"] = intermediate["TODAY"]!!
        if (intermediate.containsKey("YESTERDAY")) result["YESTERDAY"] = intermediate["YESTERDAY"]!!
        intermediate.forEach { (key, value) ->
            if (key != "TODAY" && key != "YESTERDAY") result[key] = value
        }
        return result
    }
}

// ---------- Date helpers ----------

private const val MILLIS_PER_DAY = 24L * 60 * 60 * 1000

private fun floorToUtcDay(millis: Long): Long =
    (millis / MILLIS_PER_DAY) * MILLIS_PER_DAY

private val MONTHS = arrayOf(
    "JAN", "FEB", "MAR", "APR", "MAY", "JUN",
    "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"
)

private fun formatMonthDay(millis: Long): String {
    val totalDays = (millis / MILLIS_PER_DAY).toInt()
    val (_, month, day) = epochDaysToYearMonthDay(totalDays)
    val monthStr = MONTHS[month - 1]
    val dayStr = if (day < 10) "0$day" else "$day"
    return "$monthStr $dayStr"
}

/** Decomposes days-since-epoch (UTC, 1970-01-01) into (year, month, day). */
private fun epochDaysToYearMonthDay(daysSinceEpoch: Int): Triple<Int, Int, Int> {
    // Algorithm: http://howardhinnant.github.io/date_algorithms.html
    val z = daysSinceEpoch + 719468
    val era = (if (z >= 0) z else z - 146096) / 146097
    val doe = z - era * 146097
    val yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
    val y = yoe + era * 400
    val doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
    val mp = (5 * doy + 2) / 153
    val d = doy - (153 * mp + 2) / 5 + 1
    val m = if (mp < 10) mp + 3 else mp - 9
    val yr = if (m <= 2) y + 1 else y
    return Triple(yr.toInt(), m.toInt(), d.toInt())
}
