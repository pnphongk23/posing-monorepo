package com.aipose.ui.screens.gallery

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.SaveAlt
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import com.aipose.Photo
import com.aipose.data.resolveImagePath
import com.aipose.navigation.MatchedImageDestination
import com.aipose.navigation.reducedMotionFromPlatform
import com.aipose.ui.theme.AiPoseColors
import com.aipose.ui.theme.AiPoseTypography
import com.aipose.ui.theme.Spacing
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.datetime.Instant
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime
import kotlin.math.abs

private val GalleryDetailImageShape = RoundedCornerShape(22.dp)

private enum class DetailMediaState { Loading, Ready, Missing }
private enum class DetailSaveState { Idle, Saving, Saved, Failed }

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun GalleryDetailScreen(
    photos: List<Photo>,
    initialPhotoId: Long,
    onBack: () -> Unit,
    onDelete: suspend (Long) -> Boolean,
    onSave: suspend (Photo) -> Boolean,
    onShare: (Photo) -> Unit,
) {
    if (photos.isEmpty()) return

    val initialPage = photos.indexOfFirst { it.id == initialPhotoId }.coerceAtLeast(0)
    val pagerState = rememberPagerState(initialPage = initialPage) { photos.size }
    val currentPage = pagerState.currentPage.coerceIn(0, photos.lastIndex)
    val currentPhoto = photos[currentPage]
    val currentPath = remember(currentPhoto.imagePath) {
        resolveImagePath(currentPhoto.imagePath) ?: currentPhoto.imagePath.takeIf { it.isNotBlank() }
    }
    val scope = rememberCoroutineScope()
    val snackbarHost = remember { SnackbarHostState() }
    val mediaStates = remember { mutableStateMapOf<Long, DetailMediaState>() }
    val saveStates = remember { mutableStateMapOf<Long, DetailSaveState>() }
    var focusMode by remember { mutableStateOf(false) }
    var deleted by remember { mutableStateOf(false) }
    var dragOffset by remember { mutableFloatStateOf(0f) }
    var contentHeightPx by remember { mutableFloatStateOf(1f) }
    var settleJob by remember { mutableStateOf<Job?>(null) }
    val reducedMotion = remember { reducedMotionFromPlatform() }

    val mediaState = mediaStates[currentPhoto.id] ?: DetailMediaState.Loading
    val saveState = saveStates[currentPhoto.id] ?: DetailSaveState.Idle
    val actionsEnabled = mediaState == DetailMediaState.Ready && !deleted && saveState != DetailSaveState.Saving

    LaunchedEffect(currentPage) {
        focusMode = false
        dragOffset = 0f
        deleted = false
        if (currentPhoto.id !in mediaStates) mediaStates[currentPhoto.id] = DetailMediaState.Loading
        if (currentPhoto.id !in saveStates) saveStates[currentPhoto.id] = DetailSaveState.Idle
    }

    fun handleBack() {
        if (focusMode) {
            focusMode = false
            dragOffset = 0f
        } else {
            onBack()
        }
    }

    fun settleDrag(velocity: Float) {
        settleJob?.cancel()
        val focusThreshold = 110f
        val detailThreshold = contentHeightPx * .25f
        val shouldDismiss = if (focusMode) {
            dragOffset >= focusThreshold || velocity >= 900f
        } else {
            dragOffset >= detailThreshold || velocity >= contentHeightPx * 1.5f
        }
        val target = if (shouldDismiss) contentHeightPx else 0f
        settleJob = scope.launch {
            val duration = if (reducedMotion) 1 else 220
            androidx.compose.animation.core.Animatable(dragOffset).animateTo(
                targetValue = target,
                animationSpec = androidx.compose.animation.core.tween(duration),
            ) { dragOffset = value }
            if (shouldDismiss) {
                if (focusMode) {
                    focusMode = false
                    dragOffset = 0f
                } else {
                    onBack()
                }
            } else {
                dragOffset = 0f
            }
            settleJob = null
        }
    }

    fun runSave() {
        if (!actionsEnabled) return
        saveStates[currentPhoto.id] = DetailSaveState.Saving
        scope.launch {
            val result = try {
                onSave(currentPhoto)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                false
            }
            saveStates[currentPhoto.id] = if (result) DetailSaveState.Saved else DetailSaveState.Failed
            snackbarHost.showSnackbar(if (result) "Saved" else "Save failed")
        }
    }

    val background = if (focusMode) Color.Black else AiPoseColors.Background
    Box(Modifier.fillMaxSize().background(background)) {
        Scaffold(
            containerColor = Color.Transparent,
            snackbarHost = { SnackbarHost(snackbarHost) },
            modifier = Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.systemBars),
        ) { innerPadding ->
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding)
                    .padding(horizontal = if (focusMode) 0.dp else Spacing.lg),
            ) {
                if (!focusMode) {
                    DetailHeader(
                        photo = currentPhoto,
                        onBack = ::handleBack,
                        onMore = { scope.launch { snackbarHost.showSnackbar("Photo options") } },
                    )
                }

                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f)
                        .onSizeChanged { contentHeightPx = it.height.toFloat().coerceAtLeast(1f) }
                        .graphicsLayer {
                            translationY = dragOffset
                            alpha = 1f - (dragOffset / 360f).coerceIn(0f, .35f)
                        }
                        .galleryDetailDrag(
                            enabled = !deleted,
                            onDrag = { delta ->
                                if (delta > 0f) dragOffset = (dragOffset + delta).coerceAtLeast(0f)
                            },
                            onEnd = ::settleDrag,
                        ),
                    contentAlignment = Alignment.Center,
                ) {
                    if (deleted) {
                        DeletedPhoto(onBack = onBack)
                    } else {
                        MatchedImageDestination(
                            key = "photo:${currentPhoto.id}",
                            imageModel = currentPath,
                            cornerRadius = 22.dp,
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            HorizontalPager(
                                state = pagerState,
                                modifier = Modifier.fillMaxWidth(),
                                userScrollEnabled = !focusMode && photos.size > 1,
                                key = { photos[it].id },
                            ) { page ->
                                val pagePhoto = photos[page]
                                val pagePath = remember(pagePhoto.imagePath) {
                                    resolveImagePath(pagePhoto.imagePath) ?: pagePhoto.imagePath.takeIf { it.isNotBlank() }
                                }
                                val pageState = mediaStates[pagePhoto.id] ?: DetailMediaState.Loading
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .heightIn(min = if (focusMode) 1.dp else 320.dp)
                                        .clip(if (focusMode) RoundedCornerShape(0.dp) else GalleryDetailImageShape)
                                        .clickable(enabled = page == currentPage && pageState == DetailMediaState.Ready) {
                                            focusMode = !focusMode
                                            dragOffset = 0f
                                        }
                                        .semantics {
                                            contentDescription = "Photo ${page + 1} of ${photos.size}. " +
                                                if (focusMode) "Tap to return." else "Tap to focus."
                                        },
                                    contentAlignment = Alignment.Center,
                                ) {
                                    if (pageState == DetailMediaState.Missing) {
                                        MissingPhoto(onRetry = { mediaStates[pagePhoto.id] = DetailMediaState.Loading })
                                    } else {
                                        if (page == currentPage && pageState == DetailMediaState.Loading) {
                                            CircularProgressIndicator(color = AiPoseColors.Primary)
                                        }
                                        AsyncImage(
                                            model = pagePath,
                                            contentDescription = "Captured photo ${page + 1}",
                                            modifier = Modifier.fillMaxWidth(),
                                            contentScale = ContentScale.Fit,
                                            onLoading = { mediaStates[pagePhoto.id] = DetailMediaState.Loading },
                                            onSuccess = { mediaStates[pagePhoto.id] = DetailMediaState.Ready },
                                            onError = { mediaStates[pagePhoto.id] = DetailMediaState.Missing },
                                        )
                                    }
                                }
                            }
                        }

                        if (!focusMode && photos.size > 1) {
                            Text(
                                text = "${currentPage + 1} / ${photos.size}",
                                style = AiPoseTypography.Caption.copy(fontSize = 12.sp, fontWeight = FontWeight.Bold),
                                modifier = Modifier
                                    .align(Alignment.BottomEnd)
                                    .padding(Spacing.md)
                                    .background(AiPoseColors.Background.copy(alpha = .88f), RoundedCornerShape(999.dp))
                                    .padding(horizontal = 9.dp, vertical = 5.dp)
                                    .semantics { contentDescription = "Photo ${currentPage + 1} of ${photos.size}" },
                            )
                        }
                    }
                }

                if (!focusMode && !deleted) {
                    DetailActionRow(
                        enabled = actionsEnabled,
                        saveState = saveState,
                        onShare = { if (actionsEnabled) onShare(currentPhoto) },
                        onSave = ::runSave,
                        onDelete = {
                            if (!actionsEnabled) return@DetailActionRow
                            scope.launch {
                                val result = try {
                                    onDelete(currentPhoto.id)
                                } catch (cancelled: CancellationException) {
                                    throw cancelled
                                } catch (_: Exception) {
                                    false
                                }
                                if (result) {
                                    deleted = true
                                } else {
                                    snackbarHost.showSnackbar("Delete failed")
                                }
                            }
                        },
                        onRetrySave = ::runSave,
                    )
                }
            }
        }
    }
}

@Composable
private fun DetailHeader(photo: Photo, onBack: () -> Unit, onMore: () -> Unit) {
    val dateTime = remember(photo.createdAt) { formatDetailDateTime(photo.createdAt) }
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = Spacing.md),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        TextButton(
            onClick = onBack,
            modifier = Modifier.size(48.dp).semantics { contentDescription = "Back to gallery" },
        ) {
            Icon(Icons.Default.ArrowBack, contentDescription = null, tint = AiPoseColors.Foreground)
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(dateTime.date, style = AiPoseTypography.Heading3)
            Text(dateTime.time, style = AiPoseTypography.Caption, color = AiPoseColors.Subtext)
        }
        TextButton(
            onClick = onMore,
            modifier = Modifier.size(48.dp).semantics { contentDescription = "Photo options" },
        ) {
            Icon(Icons.Default.MoreVert, contentDescription = null, tint = AiPoseColors.Foreground)
        }
    }
}

@Composable
private fun DetailActionRow(
    enabled: Boolean,
    saveState: DetailSaveState,
    onShare: () -> Unit,
    onSave: () -> Unit,
    onDelete: () -> Unit,
    onRetrySave: () -> Unit,
) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(vertical = Spacing.md),
            horizontalArrangement = Arrangement.SpaceEvenly,
        ) {
            DetailAction("Share", Icons.Default.Share, enabled, onShare)
            DetailAction(if (saveState == DetailSaveState.Saved) "Saved" else "Save", Icons.Default.SaveAlt, enabled && saveState != DetailSaveState.Saved, onSave)
            DetailAction("Trash", Icons.Default.Delete, enabled, onDelete, AiPoseColors.ErrorForeground)
        }
        if (saveState == DetailSaveState.Failed) {
            TextButton(onClick = onRetrySave, modifier = Modifier.semantics { contentDescription = "Try saving again" }) {
                Text("Try again")
            }
        }
    }
}

@Composable
private fun DetailAction(
    label: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    enabled: Boolean,
    onClick: () -> Unit,
    tint: Color = AiPoseColors.Foreground,
) {
    Column(
        modifier = Modifier
            .heightIn(min = 70.dp)
            .clickable(enabled = enabled, onClick = onClick)
            .semantics { contentDescription = label },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.sm),
    ) {
        Icon(icon, contentDescription = null, tint = tint.copy(alpha = if (enabled) 1f else .38f), modifier = Modifier.size(24.dp))
        Text(label, style = AiPoseTypography.Caption.copy(fontSize = 11.sp, fontWeight = FontWeight.Bold), color = tint.copy(alpha = if (enabled) 1f else .38f))
    }
}

@Composable
private fun MissingPhoto(onRetry: () -> Unit) {
    Column(
        modifier = Modifier.padding(Spacing.xl),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.sm),
    ) {
        Icon(Icons.Default.Image, contentDescription = null, tint = AiPoseColors.Subtext, modifier = Modifier.size(44.dp))
        Text("Photo unavailable", style = AiPoseTypography.Heading3)
        Text(
            "This local file is missing, but the gallery record is still safe to recover.",
            style = AiPoseTypography.Caption,
            color = AiPoseColors.Subtext,
        )
        TextButton(onClick = onRetry) { Text("Try again") }
    }
}

@Composable
private fun DeletedPhoto(onBack: () -> Unit) {
    Column(
        modifier = Modifier.padding(Spacing.xl).semantics { contentDescription = "Photo deleted" },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.md),
    ) {
        Icon(Icons.Default.Delete, contentDescription = null, tint = AiPoseColors.ErrorForeground, modifier = Modifier.size(44.dp))
        Text("Photo deleted", style = AiPoseTypography.Heading3)
        Text("The photo was removed. Return to Gallery to continue.", style = AiPoseTypography.Caption, color = AiPoseColors.Subtext)
        TextButton(onClick = onBack) { Text("Back to Gallery") }
    }
}

private data class GalleryDetailDateTime(val date: String, val time: String)

private fun formatDetailDateTime(raw: String): GalleryDetailDateTime {
    val value = raw.trim().toLongOrNull() ?: return GalleryDetailDateTime("Captured photo", "")
    val millis = if (value in -10_000_000_000L..10_000_000_000L) value * 1_000 else value
    val local = Instant.fromEpochMilliseconds(millis).toLocalDateTime(TimeZone.currentSystemDefault())
    val month = listOf("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")[local.month.ordinal]
    val hour = (local.hour % 12).let { if (it == 0) 12 else it }
    val meridiem = if (local.hour < 12) "AM" else "PM"
    return GalleryDetailDateTime(
        date = "$month ${local.dayOfMonth}, ${local.year}",
        time = "$hour:${local.minute.toString().padStart(2, '0')} $meridiem",
    )
}

private fun Modifier.galleryDetailDrag(
    enabled: Boolean,
    onDrag: (Float) -> Unit,
    onEnd: (Float) -> Unit,
): Modifier {
    if (!enabled) return this
    return pointerInput(Unit) {
        awaitEachGesture {
            val down = awaitFirstDown(requireUnconsumed = false)
            var vertical = false
            var totalX = 0f
            var totalY = 0f
            while (true) {
                val event = awaitPointerEvent()
                val change = event.changes.firstOrNull { it.id == down.id } ?: break
                if (!change.pressed) break
                val delta = change.positionChange()
                totalX += delta.x
                totalY += delta.y
                if (!vertical && (abs(totalX) > 8f || abs(totalY) > 8f)) {
                    if (abs(totalX) > abs(totalY)) break
                    vertical = true
                }
                if (vertical) {
                    change.consume()
                    onDrag(delta.y)
                }
            }
            if (vertical) onEnd(totalY)
        }
    }
}
