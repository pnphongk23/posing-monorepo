package com.aipose.ui.screens.gallery

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.lazy.staggeredgrid.LazyVerticalStaggeredGrid
import androidx.compose.foundation.lazy.staggeredgrid.StaggeredGridCells
import androidx.compose.foundation.lazy.staggeredgrid.itemsIndexed
import androidx.compose.foundation.lazy.staggeredgrid.rememberLazyStaggeredGridState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.shape.RoundedCornerShape
import org.jetbrains.compose.resources.painterResource
import ai_pose.composeapp.generated.resources.Res
import ai_pose.composeapp.generated.resources.ic_chevron_left
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Image
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import com.aipose.Photo
import com.aipose.ui.components.PrimaryButton
import com.aipose.ui.components.NeoBrutalismContainer
import com.aipose.ui.components.cardChrome
import com.aipose.ui.theme.AiPoseColors
import com.aipose.ui.theme.AiPoseTypography
import com.aipose.ui.theme.Spacing
import com.aipose.data.resolveImagePath
import com.aipose.navigation.MainDockContentInset
import com.aipose.navigation.MatchedImageTransitionState
import com.aipose.navigation.SharedTransitionPhase

internal val galleryDateFilterLabels = listOf("All", "Today", "7 days", "30 days", "Date")

private val GalleryPrototypeBackground = Color(0xFFFBF6EF)
private val GalleryPrototypePink = Color(0xFFE89CAE)
private val GalleryPrototypeYellow = Color(0xFFFED766)
private val GalleryPrototypeBlack = Color(0xFF121212)
private val GalleryPrototypeWhite = Color.White
private val GalleryPrototypeGalleryCardShape = RoundedCornerShape(6.dp)
private val GalleryPrototypeAspectRatios = listOf(4f / 5f, 1f, 5f / 4f)

@Composable
@Suppress("UNUSED_PARAMETER")
fun GalleryScreen(
    viewModel: GalleryViewModel,
    gridState: LazyGridState = rememberLazyGridState(),
    onOpenCamera: () -> Unit,
    onBack: (() -> Unit)? = null,
    onPhotoClick: (com.aipose.Photo) -> Unit,
    onUpgrade: () -> Unit = {},
) {
    val uiState by viewModel.uiState.collectAsState()
    var selectedDateFilter by remember { mutableStateOf(galleryDateFilterLabels.first()) }
    // Keep the legacy LazyGridState parameter source-compatible with Navigation.kt;
    // the prototype gallery is now a staggered grid with its own scroll state.
    val staggeredGridState = rememberLazyStaggeredGridState()
    // Voyager disposes the list composition while detail is on top, so its
    // collector is cancelled too. Re-collect whenever the list re-enters to
    // pick up deletions and other changes made from detail.
    LaunchedEffect(viewModel) { viewModel.load() }

    val snackbarHostState = remember { SnackbarHostState() }

    Box(modifier = Modifier.fillMaxSize()) {
    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        containerColor = GalleryPrototypeBackground,
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .padding(horizontal = Spacing.md)
        ) {
            // ── Header row ──────────────────────────────────────────────────
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 4.dp)
                    .padding(top = 8.dp, bottom = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    if (onBack != null) {
                        NeoBrutalismContainer(
                                modifier = Modifier
                                    .semantics { testTag = "gallery-back-btn" }
                                .size(44.dp),
                            shape = RoundedCornerShape(10.dp),
                            backgroundColor = GalleryPrototypeWhite,
                            shadowColor = GalleryPrototypeBlack,
                            shadowOffset = 3.dp,
                            borderWidth = 2.dp,
                            onClick = onBack
                        ) {
                            Icon(
                                painter = painterResource(Res.drawable.ic_chevron_left),
                                contentDescription = "Back",
                                tint = GalleryPrototypeBlack,
                                modifier = Modifier.size(20.dp)
                            )
                        }
                    }

                    Text(
                        text = "Gallery",
                        style = AiPoseTypography.ScreenTitle,
                        color = GalleryPrototypeBlack,
                    )
                }

                NeoBrutalismContainer(
                    modifier = Modifier
                        .size(44.dp)
                        .semantics {
                            testTag = "gallery-upgrade-btn"
                            contentDescription = "Upgrade to Premium"
                        },
                    shape = RoundedCornerShape(10.dp),
                    backgroundColor = GalleryPrototypeYellow,
                    shadowColor = GalleryPrototypeBlack,
                    shadowOffset = 2.dp,
                    borderWidth = 2.dp,
                    onClick = onUpgrade,
                ) {
                    GalleryCrownIcon()
                }
            }

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState())
                    .padding(bottom = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                galleryDateFilterLabels.forEach { label ->
                    val isActive = label == selectedDateFilter
                    NeoBrutalismContainer(
                        modifier = Modifier
                            .height(36.dp)
                            .semantics {
                                testTag = "gallery-date-filter-${label.filter { it.isLetterOrDigit() }}"
                                contentDescription = "$label gallery date filter"
                            },
                        shape = RoundedCornerShape(8.dp),
                        backgroundColor = if (isActive) GalleryPrototypePink else GalleryPrototypeWhite,
                        shadowColor = GalleryPrototypeBlack,
                        shadowOffset = if (isActive) 1.5.dp else 0.dp,
                        borderWidth = if (isActive) 2.dp else 1.5.dp,
                        hasShadow = isActive,
                        onClick = { selectedDateFilter = label },
                    ) {
                        Text(
                            text = label,
                            style = AiPoseTypography.MetaLabel,
                            color = GalleryPrototypeBlack,
                            modifier = Modifier.padding(horizontal = 12.dp),
                        )
                    }
                }
            }

            // ── Content states ───────────────────────────────────────────────
            when {
                uiState.isLoading -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = GalleryPrototypePink)
                    }
                }

                // Gallery-empty: there are genuinely no photos at all.
                uiState.photos.isEmpty() -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Column(
                            modifier = Modifier
                                .cardChrome()
                                .padding(Spacing.lg),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(Spacing.md)
                        ) {
                            // Decorative glyph exception: frozen typography roles do not cover the empty-state camera emoji.
                            Text("📸", fontSize = 48.sp) // GalleryScreen.kt:146
                            Text("No photos yet", style = AiPoseTypography.Heading3)
                            PrimaryButton(text = "Open camera", onClick = { onOpenCamera() })
                        }
                    }
                }

                    // Gallery is one uninterrupted two-column masonry stream.
                  else -> {
                      LazyVerticalStaggeredGrid(
                          columns = StaggeredGridCells.Fixed(2),
                          state = staggeredGridState,
                          contentPadding = PaddingValues(bottom = MainDockContentInset),
                          horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                          verticalItemSpacing = Spacing.sm,
                          modifier = Modifier.fillMaxSize(),
                      ) {
                          itemsIndexed(
                              items = uiState.groupedByDate.values.flatten(),
                              key = { _, photo -> photo.id },
                          ) { index, photo ->
                              GalleryMasonryPhotoCard(
                                  photo = photo,
                                  index = index,
                                  onClick = { onPhotoClick(photo) },
                              )
                          }
                      }
                }
            }
        }
    }

      } // end Box overlay
}

@Composable
private fun GalleryCrownIcon() {
    Canvas(modifier = Modifier.size(22.dp)) {
        val strokeWidth = 2.5.dp.toPx()
        val crown = Path().apply {
            moveTo(size.width * 0.12f, size.height * 0.28f)
            lineTo(size.width * 0.30f, size.height * 0.50f)
            lineTo(size.width * 0.50f, size.height * 0.20f)
            lineTo(size.width * 0.70f, size.height * 0.50f)
            lineTo(size.width * 0.88f, size.height * 0.28f)
            lineTo(size.width * 0.78f, size.height * 0.76f)
            lineTo(size.width * 0.22f, size.height * 0.76f)
            close()
        }
        drawPath(
            path = crown,
            color = GalleryPrototypeBlack,
            style = Stroke(
                width = strokeWidth,
                cap = StrokeCap.Round,
                join = StrokeJoin.Round,
            ),
        )
        drawLine(
            color = GalleryPrototypeBlack,
            start = androidx.compose.ui.geometry.Offset(size.width * 0.20f, size.height * 0.86f),
            end = androidx.compose.ui.geometry.Offset(size.width * 0.80f, size.height * 0.86f),
            strokeWidth = strokeWidth,
            cap = StrokeCap.Round,
        )
    }
}

@Composable
private fun GalleryMasonryPhotoCard(
    photo: Photo,
    index: Int,
    onClick: () -> Unit,
) {
    var sourceBounds by remember { mutableStateOf<androidx.compose.ui.geometry.Rect?>(null) }
    val resolvedPath = remember(photo.imagePath) {
        resolveImagePath(photo.imagePath) ?: photo.imagePath.takeIf { it.isNotBlank() }
    }
    val isTransitioning = MatchedImageTransitionState.source?.key == "photo:${photo.id}" &&
        MatchedImageTransitionState.transitionPhase != SharedTransitionPhase.IDLE
    val shape = GalleryPrototypeGalleryCardShape
    val aspectRatio = GalleryPrototypeAspectRatios[index % GalleryPrototypeAspectRatios.size]

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .aspectRatio(aspectRatio)
            .clip(shape)
            .background(GalleryPrototypeWhite)
            .border(1.5.dp, GalleryPrototypeBlack, shape)
            .clickable {
                sourceBounds?.let {
                    MatchedImageTransitionState.capture(
                        key = "photo:${photo.id}",
                        bounds = it,
                        imageModel = resolvedPath,
                        cornerRadius = 6.dp,
                    )
                }
                onClick()
            }
            .semantics {
                testTag = "gallery-photo-item-${photo.id}"
                contentDescription = photo.poseName.ifBlank { "Gallery photo" }
            },
        contentAlignment = Alignment.Center,
    ) {
        if (!resolvedPath.isNullOrBlank()) {
            AsyncImage(
                model = resolvedPath,
                contentDescription = photo.poseName.ifBlank { "Gallery photo" },
                modifier = Modifier
                    .fillMaxSize()
                    .onGloballyPositioned { sourceBounds = it.boundsInWindow() }
                    .graphicsLayer { alpha = if (isTransitioning) 0f else 1f },
                contentScale = ContentScale.Crop,
            )
        } else {
            Icon(
                imageVector = Icons.Default.Image,
                contentDescription = null,
                modifier = Modifier.size(32.dp),
                tint = AiPoseColors.Subtext,
            )
        }
    }
}
