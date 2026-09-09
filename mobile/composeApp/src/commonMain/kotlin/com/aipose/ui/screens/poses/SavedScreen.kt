package com.aipose.ui.screens.poses

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.staggeredgrid.LazyStaggeredGridState
import androidx.compose.foundation.lazy.staggeredgrid.LazyVerticalStaggeredGrid
import androidx.compose.foundation.lazy.staggeredgrid.StaggeredGridCells
import androidx.compose.foundation.lazy.staggeredgrid.StaggeredGridItemSpan
import androidx.compose.foundation.lazy.staggeredgrid.itemsIndexed
import androidx.compose.foundation.lazy.staggeredgrid.rememberLazyStaggeredGridState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.aipose.data.SavedPagingState
import com.aipose.ui.components.NeoBrutalismContainer
import com.aipose.ui.components.PrimaryButton
import com.aipose.ui.theme.AiPoseColors
import com.aipose.ui.theme.AiPoseTypography
import com.aipose.ui.theme.CornerRadius
import com.aipose.ui.theme.Spacing
import androidx.compose.foundation.border
import androidx.compose.ui.text.style.TextAlign
import org.jetbrains.compose.resources.painterResource
import ai_pose.composeapp.generated.resources.Res
import ai_pose.composeapp.generated.resources.ic_chevron_left

/** E-SAVED: stable test tag contract for the Saved list. */
internal const val SAVED_HEADER_TEST_TAG = "saved-header"
internal const val SAVED_BACK_TEST_TAG = "saved-back"
internal const val SAVED_REFRESH_TEST_TAG = "saved-refresh"
internal const val SAVED_STALE_BANNER_TEST_TAG = "saved-stale-banner"
internal const val SAVED_EMPTY_TEST_TAG = "saved-empty"
internal const val SAVED_INITIAL_ERROR_TEST_TAG = "saved-initial-error"
internal const val SAVED_LOAD_MORE_ERROR_TEST_TAG = "saved-load-more-error"
internal const val SAVED_REFRESH_ERROR_TEST_TAG = "saved-refresh-error"
internal const val SAVED_GRID_TEST_TAG = "saved-grid"

/** Exact stale/offline banner copy required by the design (do not soften). */
internal const val SAVED_STALE_BANNER_COPY = "Offline · showing saved poses from last confirmed read."
internal const val SAVED_REFRESH_ERROR_COPY = "Couldn't refresh. Showing your saved poses."

/**
 * Pushed Saved screen (entered only after sign-in). MainDock is not composed here;
 * the stack screen intentionally hides the dock while on top. Reuses the existing
 * community card (CommunityPoseCard) with a pink bookmark status badge; the whole
 * card is one activation that opens detail — the badge is not a nested mutation
 * target in v1.
 */
@Composable
fun SavedScreen(
    viewModel: SavedViewModel,
    gridState: LazyStaggeredGridState = rememberLazyStaggeredGridState(),
    onBack: () -> Unit,
    onPoseClick: (PosePreview) -> Unit,
    onBrowseCommunity: () -> Unit,
    onSignInRequired: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val uiState by viewModel.uiState.collectAsState()

    LaunchedEffect(viewModel) {
        viewModel.loadInitial()
    }

    Box(modifier = modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .padding(Spacing.lg),
            verticalArrangement = Arrangement.spacedBy(Spacing.md),
        ) {
            SavedHeader(
                onBack = onBack,
            )

            SavedContent(
                uiState = uiState,
                gridState = gridState,
                onPoseClick = onPoseClick,
                onLoadMore = viewModel::loadMore,
                onRetryInitial = viewModel::retryInitial,
                onRetryLoadMore = viewModel::retryLoadMore,
                onRetryRefresh = viewModel::refresh,
                onBrowseCommunity = onBrowseCommunity,
                onSignInRequired = onSignInRequired,
            )
        }
    }
}

@Composable
private fun SavedHeader(
    onBack: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(52.dp)
            .testTag(SAVED_HEADER_TEST_TAG),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier.size(44.dp),
            contentAlignment = Alignment.CenterStart,
        ) {
            NeoBrutalismContainer(
                modifier = Modifier
                    .size(44.dp)
                    .testTag(SAVED_BACK_TEST_TAG),
                shape = RoundedCornerShape(10.dp),
                backgroundColor = AiPoseColors.Background,
                shadowOffset = 2.dp,
                borderWidth = 2.dp,
                onClick = onBack,
            ) {
                Icon(
                    painter = painterResource(Res.drawable.ic_chevron_left),
                    contentDescription = "Back to Poses",
                    tint = AiPoseColors.Foreground,
                    modifier = Modifier.size(16.dp),
                )
            }
        }

        Text(
            text = "Saved",
            style = AiPoseTypography.NavigationTitle,
            color = AiPoseColors.Foreground,
            textAlign = TextAlign.Center,
            modifier = Modifier.weight(1f),
        )

        Box(
            modifier = Modifier.size(44.dp),
        )
    }
}

@Composable
private fun SavedContent(
    uiState: SavedPagingState,
    gridState: LazyStaggeredGridState,
    onPoseClick: (PosePreview) -> Unit,
    onLoadMore: () -> Unit,
    onRetryInitial: () -> Unit,
    onRetryLoadMore: () -> Unit,
    onRetryRefresh: () -> Unit,
    onBrowseCommunity: () -> Unit,
    onSignInRequired: () -> Unit,
) {
    Column(modifier = Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        // Session expired: remove the account list; never render prior data as current.
        if (uiState.signInRequired) {
            SignInRequiredPanel(
                onContinueWithGoogle = onSignInRequired,
                modifier = Modifier.weight(1f).fillMaxWidth(),
            )
            return
        }

        // Stale/offline read-only banner above the (still visible) confirmed list.
        if (uiState.isStale && uiState.items.isNotEmpty()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(AiPoseColors.Warning.copy(alpha = 0.22f))
                    .padding(Spacing.md)
                    .testTag(SAVED_STALE_BANNER_TEST_TAG),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = SAVED_STALE_BANNER_COPY,
                    style = AiPoseTypography.Caption,
                    color = AiPoseColors.WarningForeground,
                )
            }
        }

        // Refresh error banner keeps confirmed content and does not claim fresh data.
        if (uiState.refreshError != null && uiState.items.isNotEmpty()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(AiPoseColors.Error.copy(alpha = 0.15f))
                    .padding(Spacing.md)
                    .testTag(SAVED_REFRESH_ERROR_TEST_TAG),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = SAVED_REFRESH_ERROR_COPY,
                    style = AiPoseTypography.Caption,
                    color = AiPoseColors.Error,
                )
                PrimaryButton(
                    text = "Retry",
                    onClick = onRetryRefresh,
                    modifier = Modifier.size(width = 80.dp, height = 30.dp),
                )
            }
        }

        when {
            uiState.isInitialLoading && uiState.items.isEmpty() -> {
                Box(modifier = Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = AiPoseColors.Primary)
                }
            }
            uiState.items.isEmpty() && uiState.initialError == null && !uiState.isStale -> {
                SavedEmptyState(
                    onBrowseCommunity = onBrowseCommunity,
                    modifier = Modifier.weight(1f).fillMaxWidth(),
                )
            }
            uiState.items.isEmpty() && uiState.initialError != null -> {
                val initialError = uiState.initialError
                SavedInitialError(
                    message = initialError ?: "Unable to load saved poses",
                    onRetry = onRetryInitial,
                    modifier = Modifier.weight(1f).fillMaxWidth(),
                )
            }
            else -> {
                Column(
                    modifier = Modifier.weight(1f).fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(Spacing.sm),
                ) {
                    SavedCountHeader(total = uiState.total, modifier = Modifier.fillMaxWidth())
                    LazyVerticalStaggeredGrid(
                        modifier = Modifier
                            .fillMaxSize()
                            .testTag(SAVED_GRID_TEST_TAG),
                        state = gridState,
                        columns = StaggeredGridCells.Fixed(2),
                        contentPadding = PaddingValues(bottom = Spacing.lg),
                        horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                        verticalItemSpacing = Spacing.sm,
                    ) {
                        itemsIndexed(
                            uiState.items,
                            key = { index, pose -> savedPoseGridKey(pose, index) },
                            contentType = { _, _ -> com.aipose.data.remote.CommunityPose::class },
                        ) { index, pose ->
                            SavedPoseCard(pose = pose, index = index, onClick = onPoseClick)
                        }
                        if (uiState.hasMore) {
                            if (uiState.isLoadingMore) {
                                item(span = StaggeredGridItemSpan.FullLine) {
                                    Box(
                                        modifier = Modifier.fillMaxWidth().padding(Spacing.md),
                                        contentAlignment = Alignment.Center,
                                    ) {
                                        CommunityLoadingIndicator()
                                    }
                                }
                            } else if (uiState.loadMoreError != null) {
                                item(span = StaggeredGridItemSpan.FullLine) {
                                    Column(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .padding(Spacing.md)
                                            .testTag(SAVED_LOAD_MORE_ERROR_TEST_TAG),
                                        horizontalAlignment = Alignment.CenterHorizontally,
                                        verticalArrangement = Arrangement.spacedBy(Spacing.xs),
                                    ) {
                                        Text(
                                            text = "Load more failed.",
                                            style = AiPoseTypography.Caption,
                                            color = AiPoseColors.Error,
                                        )
                                        PrimaryButton(
                                            text = "Retry",
                                            onClick = onRetryLoadMore,
                                        )
                                    }
                                }
                            } else {
                                item(span = StaggeredGridItemSpan.FullLine) {
                                    LaunchedEffect(Unit) { onLoadMore() }
                                    Box(modifier = Modifier.size(1.dp))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/**
 * Saved card: the shared community card plus a small filled-pink bookmark status
 * badge. The badge is purely presentational (no nested tap target) — the entire
 * card opens detail, where Unsave happens after a confirmed 204.
 */
@Composable
internal fun SavedPoseCard(
    pose: com.aipose.data.remote.CommunityPose,
    index: Int,
    onClick: (PosePreview) -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(modifier = modifier.fillMaxWidth()) {
        CommunityPoseCard(pose = pose, index = index, onClick = onClick)
        Box(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(Spacing.sm)
                .size(24.dp)
                .background(AiPoseColors.Primary, RoundedCornerShape(CornerRadius.sm))
                .border(1.dp, AiPoseColors.Foreground, RoundedCornerShape(CornerRadius.sm)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = Icons.Default.Bookmark,
                contentDescription = null,
                tint = AiPoseColors.Foreground,
                modifier = Modifier.size(18.dp),
            )
        }
    }
}

@Composable
private fun SavedCountHeader(total: Int, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.End,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = "$total saved",
            style = AiPoseTypography.MetaLabel,
            color = AiPoseColors.Subtext,
            modifier = Modifier.testTag("saved-count-label"),
        )
    }
}

@Composable
private fun SavedEmptyState(
    onBrowseCommunity: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.padding(Spacing.lg).testTag(SAVED_EMPTY_TEST_TAG),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(
            imageVector = Icons.Default.Bookmark,
            contentDescription = null,
            tint = AiPoseColors.Subtext,
            modifier = Modifier.size(40.dp),
        )
        Text(
            text = "No saved poses yet",
            style = AiPoseTypography.Heading3,
            color = AiPoseColors.Foreground,
            modifier = Modifier.padding(top = Spacing.md),
        )
        Text(
            text = "Save poses from Community to find them here.",
            style = AiPoseTypography.Body,
            color = AiPoseColors.Subtext,
            modifier = Modifier.padding(top = Spacing.sm, bottom = Spacing.lg),
        )
        PrimaryButton(
            text = "Browse Community",
            onClick = onBrowseCommunity,
        )
    }
}

@Composable
private fun SavedInitialError(
    message: String,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.padding(Spacing.lg).testTag(SAVED_INITIAL_ERROR_TEST_TAG),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            text = "Unable to load saved poses",
            style = AiPoseTypography.Heading3,
            color = AiPoseColors.Error,
        )
        Text(
            text = message,
            style = AiPoseTypography.Body,
            color = AiPoseColors.Subtext,
            modifier = Modifier.padding(top = Spacing.sm, bottom = Spacing.lg),
        )
        PrimaryButton(
            text = "Retry",
            onClick = onRetry,
        )
    }
}

@Composable
private fun SignInRequiredPanel(
    onContinueWithGoogle: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.padding(Spacing.lg).testTag("saved-signin-required"),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            text = "Sign in to view your saved poses",
            style = AiPoseTypography.Heading3,
            color = AiPoseColors.Foreground,
        )
        Text(
            text = "Your session expired. Sign in again to keep your saved poses synced.",
            style = AiPoseTypography.Body,
            color = AiPoseColors.Subtext,
            modifier = Modifier.padding(top = Spacing.sm, bottom = Spacing.lg),
        )
        PrimaryButton(
            text = "Continue with Google",
            onClick = onContinueWithGoogle,
        )
    }
}