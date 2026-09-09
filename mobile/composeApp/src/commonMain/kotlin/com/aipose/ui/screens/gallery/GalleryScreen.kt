package com.aipose.ui.screens.gallery

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.shape.RoundedCornerShape
import org.jetbrains.compose.resources.painterResource
import ai_pose.composeapp.generated.resources.Res
import ai_pose.composeapp.generated.resources.ic_chevron_left
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.aipose.ui.components.PrimaryButton
import com.aipose.ui.components.SectionHeader
import com.aipose.ui.components.NeoBrutalismContainer
import com.aipose.ui.components.cardChrome
import com.aipose.ui.theme.AiPoseColors
import com.aipose.ui.theme.AiPoseTypography
import com.aipose.ui.theme.Spacing
import com.aipose.platform.saveToPhotos
import com.aipose.platform.shareImage
import com.aipose.data.resolveImagePath
import com.aipose.navigation.MainDockContentInset
import com.aipose.navigation.listShouldAutoLoad
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GalleryScreen(
    viewModel: GalleryViewModel,
    gridState: LazyGridState = rememberLazyGridState(),
    onOpenCamera: () -> Unit,
    onBack: (() -> Unit)? = null,
    onPhotoClick: ((com.aipose.Photo) -> Unit)? = null,
) {
    val uiState by viewModel.uiState.collectAsState()
    // Guard on the hoisted ViewModel's load state: ordinary Back re-enters this
    // list with state already loaded, so the DB is not re-queried. Refreshes stay
    // explicit.
    LaunchedEffect(Unit) { if (listShouldAutoLoad(uiState.isLoading)) viewModel.load() }

    val snackbarHostState = remember { SnackbarHostState() }

    Box(modifier = Modifier.fillMaxSize()) {
    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        containerColor = AiPoseColors.Background
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
                    .padding(top = 8.dp, bottom = 16.dp),
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
                                .size(32.dp),
                            shape = RoundedCornerShape(10.dp),
                            backgroundColor = AiPoseColors.Background,
                            shadowOffset = 2.dp,
                            borderWidth = 2.dp,
                            onClick = onBack
                        ) {
                            Icon(
                                painter = painterResource(Res.drawable.ic_chevron_left),
                                contentDescription = "Back",
                                tint = AiPoseColors.Foreground,
                                modifier = Modifier.size(16.dp)
                            )
                        }
                    }

                    Text(
                        text = "Gallery",
                        style = AiPoseTypography.NavigationTitle,
                        color = AiPoseColors.Foreground,
                    )
                }
            }

            // ── Content states ───────────────────────────────────────────────
            when {
                uiState.isLoading -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = AiPoseColors.Primary)
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

                // Grid is the only gallery layout (prototype reference).
                else -> {
                    LazyVerticalGrid(
                        columns = GridCells.Fixed(GalleryGridDefaults.DENSE_COLUMN_COUNT),
                        state = gridState,
                        contentPadding = PaddingValues(bottom = MainDockContentInset),
                        verticalArrangement = Arrangement.spacedBy(GalleryGridDefaults.DENSE_GAP),
                        horizontalArrangement = Arrangement.spacedBy(GalleryGridDefaults.DENSE_GAP),
                        modifier = Modifier.fillMaxSize()
                    ) {
                        uiState.groupedByDate.forEach { (dateKey, photos) ->
                            item(
                                key = "gallery-section-$dateKey",
                                contentType = "gallery:section",
                                span = { GridItemSpan(GalleryGridDefaults.DENSE_COLUMN_COUNT) },
                            ) {
                                SectionHeader(
                                    title = dateKey,
                                    count = photos.size,
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(vertical = Spacing.xs)
                                )
                            }
                            items(
                                items = photos,
                                key = { photo -> photo.id },
                                contentType = { "gallery:photo" },
                            ) { photo ->
                                PhotoCard(
                                    photo = photo,
                                    onClick = { onPhotoClick?.invoke(photo) ?: viewModel.selectPhoto(photo) },
                                    dense = true,
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    // Legacy inline detail remains available only to callers that do not provide
    // navigation; list roots provide onPhotoClick and therefore never overlay it.
    uiState.selectedPhoto?.let { photo ->
        PhotoDetailDialog(
            photo = photo,
            onDismiss = { viewModel.selectPhoto(null) },
            onDelete = { id -> mapGalleryDeletePhotoResult(viewModel::deletePhoto, id) },
            onSave = { selected ->
                val path = resolveImagePath(selected.imagePath) ?: selected.imagePath
                saveToPhotos(path, null)
            },
            onShare = { selected ->
                val path = resolveImagePath(selected.imagePath) ?: selected.imagePath
                shareImage(path, null)
            },
        )
    }
    } // end Box overlay
}
