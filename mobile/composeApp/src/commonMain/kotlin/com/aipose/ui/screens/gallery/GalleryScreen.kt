package com.aipose.ui.screens.gallery

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.clickable
import androidx.compose.foundation.shape.RoundedCornerShape
import org.jetbrains.compose.resources.painterResource
import ai_pose.composeapp.generated.resources.Res
import ai_pose.composeapp.generated.resources.ic_chevron_left
import ai_pose.composeapp.generated.resources.ic_layout_grid
import ai_pose.composeapp.generated.resources.ic_list
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import androidx.compose.ui.text.font.FontWeight
import com.aipose.ui.components.PrimaryButton
import com.aipose.ui.components.SectionHeader
import com.aipose.ui.components.NeoBrutalismContainer
import com.aipose.ui.components.cardChrome
import com.aipose.ui.components.neoBorder
import com.aipose.ui.components.neoShadow
import com.aipose.ui.theme.AiPoseColors
import com.aipose.ui.theme.AiPoseTypography
import com.aipose.ui.theme.CornerRadius
import com.aipose.ui.theme.Spacing
import com.aipose.platform.deletePhotoConfirmation
import com.aipose.platform.saveToPhotos
import com.aipose.platform.saveToPhotosConfirmation
import com.aipose.data.resolveImagePath
import com.aipose.navigation.MainDockContentInset
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GalleryScreen(
    viewModel: GalleryViewModel,
    onOpenCamera: () -> Unit,
    onBack: (() -> Unit)? = null,
) {
    val uiState by viewModel.uiState.collectAsState()
    LaunchedEffect(Unit) { viewModel.load() }

    val scope = rememberCoroutineScope()
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
                        text = "GALLERY",
                        fontSize = 22.sp,
                        fontWeight = FontWeight.ExtraBold,
                        color = AiPoseColors.Foreground,
                        letterSpacing = 0.06.em
                    )
                }

                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    val isGrid = uiState.viewMode == ViewMode.GRID
                    NeoBrutalismContainer(
                        modifier = Modifier
                            .semantics { testTag = "gallery-grid-toggle" }
                            .size(32.dp),
                        shape = RoundedCornerShape(10.dp),
                        backgroundColor = if (isGrid) AiPoseColors.AccentBlue else AiPoseColors.Background,
                        shadowOffset = 2.dp,
                        borderWidth = 2.dp,
                        onClick = { if (!isGrid) viewModel.toggleViewMode() }
                    ) {
                        Icon(
                            painter = painterResource(Res.drawable.ic_layout_grid),
                            contentDescription = "Grid view",
                            tint = AiPoseColors.Foreground,
                            modifier = Modifier.size(16.dp)
                        )
                    }

                    val isList = uiState.viewMode == ViewMode.LIST
                    NeoBrutalismContainer(
                        modifier = Modifier
                            .semantics { testTag = "gallery-list-toggle" }
                            .size(32.dp),
                        shape = RoundedCornerShape(10.dp),
                        backgroundColor = if (isList) AiPoseColors.AccentBlue else AiPoseColors.Background,
                        shadowOffset = 2.dp,
                        borderWidth = 2.dp,
                        onClick = { if (!isList) viewModel.toggleViewMode() }
                    ) {
                        Icon(
                            painter = painterResource(Res.drawable.ic_list),
                            contentDescription = "List view",
                            tint = AiPoseColors.Foreground,
                            modifier = Modifier.size(16.dp)
                        )
                    }
                }
            }

            // ── Search (WI-02) ───────────────────────────────────────────────
            // Only shown when the gallery has at least one photo; the gallery
            // empty state has nothing to search. Filter semantics (title-tag
            // substring, case-insensitive) live in GalleryViewModel.
            if (uiState.photos.isNotEmpty()) {
                OutlinedTextField(
                    value = uiState.searchQuery,
                    onValueChange = viewModel::setSearchQuery,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = Spacing.xs)
                        .semantics { testTag = "gallery-search-field" }
                        .semantics { contentDescription = "Search photos by pose" },
                    placeholder = {
                        Text(
                            "Search poses",
                            style = AiPoseTypography.Body,
                            color = AiPoseColors.Subtext,
                        )
                    },
                    textStyle = AiPoseTypography.Body,
                    singleLine = true,
                    colors = TextFieldDefaults.outlinedTextFieldColors(
                        focusedBorderColor = AiPoseColors.Foreground,
                        unfocusedBorderColor = AiPoseColors.Foreground,
                        containerColor = AiPoseColors.Surface,
                        cursorColor = AiPoseColors.Foreground,
                    ),
                    leadingIcon = {
                        Icon(
                            imageVector = Icons.Default.Search,
                            contentDescription = null,
                            tint = AiPoseColors.Foreground,
                        )
                    },
                    trailingIcon = {
                        if (uiState.searchQuery.isNotEmpty()) {
                            IconButton(
                                onClick = { viewModel.setSearchQuery("") },
                                modifier = Modifier
                                    .size(44.dp)
                                    .semantics { testTag = "gallery-search-clear" },
                            ) {
                                Icon(
                                    imageVector = Icons.Default.Close,
                                    contentDescription = "Clear",
                                    tint = AiPoseColors.Foreground,
                                )
                            }
                        }
                    },
                )
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
                            Text("📸", fontSize = 48.sp)
                            Text("NO PHOTOS YET", style = AiPoseTypography.Heading3)
                            PrimaryButton(text = "OPEN CAMERA", onClick = { onOpenCamera() })
                        }
                    }
                }

                // Filter-empty: photos exist but none match the active query.
                uiState.groupedByDate.isEmpty() -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text(
                            "No photos found",
                            style = AiPoseTypography.Heading3,
                            color = AiPoseColors.Subtext,
                        )
                    }
                }

                else -> {
                    if (uiState.viewMode == ViewMode.GRID) {
                        LazyVerticalGrid(
                            columns = GridCells.Fixed(GalleryGridDefaults.DENSE_COLUMN_COUNT),
                            contentPadding = PaddingValues(bottom = MainDockContentInset),
                            verticalArrangement = Arrangement.spacedBy(GalleryGridDefaults.DENSE_GAP),
                            horizontalArrangement = Arrangement.spacedBy(GalleryGridDefaults.DENSE_GAP),
                            modifier = Modifier.fillMaxSize()
                        ) {
                            uiState.groupedByDate.forEach { (dateKey, photos) ->
                                item(span = { GridItemSpan(GalleryGridDefaults.DENSE_COLUMN_COUNT) }) {
                                    SectionHeader(
                                        title = dateKey,
                                        count = photos.size,
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .padding(vertical = Spacing.xs)
                                    )
                                }
                                items(photos) { photo ->
                                    PhotoCard(
                                        photo = photo,
                                        onClick = { viewModel.selectPhoto(photo) },
                                        dense = true,
                                    )
                                }
                            }
                        }
                    } else {
                        LazyColumn(
                            modifier = Modifier.fillMaxSize(),
                            contentPadding = PaddingValues(bottom = MainDockContentInset),
                            verticalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            uiState.groupedByDate.forEach { (dateKey, photos) ->
                                item {
                                    SectionHeader(
                                        title = dateKey,
                                        count = photos.size,
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .padding(vertical = Spacing.xs)
                                    )
                                }
                                items(photos) { photo ->
                                    PhotoCard(
                                        photo = photo,
                                        onClick = { viewModel.selectPhoto(photo) },
                                        modifier = Modifier.fillMaxWidth()
                                    )
                                }
                            }
                            item { Spacer(Modifier.height(Spacing.md)) }
                        }
                    }
                }
            }
        }
    }

    // ── PhotoDetailDialog ────────────────────────────────────────────────────
    uiState.selectedPhoto?.let { photo ->
        PhotoDetailDialog(
            photo = photo,
            onDismiss = { viewModel.selectPhoto(null) },
            onDelete = { id ->
                // DEL-UI-01: repository restores metadata and rethrows on
                // failure; surface it as a snackbar and report `false` so the
                // detail dialog stays open for a retry. Cancellation must
                // propagate (never be reported as a delete failure).
                try {
                    viewModel.deletePhoto(id)
                    true
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Exception) {
                    snackbarHostState.showSnackbar(deletePhotoConfirmation(false))
                    false
                }
            },
            onToggleFavorite = { id -> scope.launch { viewModel.toggleFavorite(id) } },
            onSave = { p ->
                    val resolvedPath = resolveImagePath(p.imagePath) ?: p.imagePath
                    val saved = saveToPhotos(resolvedPath, null)
                    scope.launch {
                        snackbarHostState.showSnackbar(saveToPhotosConfirmation(saved))
                    }
                }
        )
    }
    } // end Box overlay
}
