package com.aipose.ui.screens.poses

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.staggeredgrid.LazyVerticalStaggeredGrid
import androidx.compose.foundation.lazy.staggeredgrid.LazyStaggeredGridState
import androidx.compose.foundation.lazy.staggeredgrid.StaggeredGridCells
import androidx.compose.foundation.lazy.staggeredgrid.StaggeredGridItemSpan
import androidx.compose.foundation.lazy.staggeredgrid.itemsIndexed
import androidx.compose.foundation.lazy.staggeredgrid.rememberLazyStaggeredGridState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshContainer
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import coil3.compose.LocalPlatformContext
import coil3.compose.SubcomposeAsyncImage
import coil3.request.ImageRequest
import com.aipose.data.AppConfig
import com.aipose.data.CommunityLibraryState
import com.aipose.data.OperationState
import com.aipose.data.PoseServiceLocator
import com.aipose.data.PosesLibraryCoordinator
import com.aipose.data.remote.CommunityPose
import com.aipose.navigation.MainDockContentInset
import com.aipose.navigation.MatchedImageTransitionState
import com.aipose.navigation.shouldAutoLoadCommunity
import com.aipose.ui.components.NeoBrutalismContainer
import com.aipose.ui.components.PrimaryButton
import com.aipose.ui.theme.AiPoseColors
import com.aipose.ui.theme.AiPoseTypography
import com.aipose.ui.theme.CornerRadius
import com.aipose.ui.theme.Spacing
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** E-SEARCH-WIRED: stable test tag for the poses-list search affordance. */
internal const val POSES_SEARCH_BUTTON_TEST_TAG = "poses-search-button"

/**
 * Thumbnail fill policy. Crop fills the rounded card viewport while preserving
 * intrinsic aspect ratio — no letterbox white strips, no distortion.
 */
internal fun poseThumbnailContentScale(): ContentScale = ContentScale.Crop

/**
 * Masonry card height variation, mirroring the prototype `.nb-card--aspect-*`
 * classes (`card.css`). Cycles a tall / square / short ratio so a true two-
 * column [LazyVerticalStaggeredGrid] renders uneven column heights (RedNote /
 * Pinterest feed) instead of row-banded whitespace. Kept pure and deterministic
 * so the masonry ratio policy is unit-testable without a UI host.
 */
internal fun communityCardAspectRatio(index: Int): Float = when (index % 3) {
    0 -> 1f / 1.25f // nb-card--aspect-tall
    1 -> 1f          // nb-card--aspect-square
    else -> 1.25f / 1f // nb-card--aspect-short
}

/**
 * Community item loading indicator dimensions / tone. Intentionally small
 * (16dp), thin (1.5dp stroke) and low-contrast (muted subtext, never the
 * primary/error red): a calm, non-diagnostic placeholder. The card image region
 * is already bounded by its aspect-ratio box, so the indicator never shifts
 * layout when it swaps in/out. Sizes stay pure so the focused test can pin them.
 */
internal const val COMMUNITY_LOADING_SIZE = 16 // dp
internal const val COMMUNITY_LOADING_STROKE = 1.5f // dp
internal const val COMMUNITY_LOADING_ALPHA = 0.65f

/**
 * Resolve the Coil image model for a community card: prefer the thumbnail URL,
 * falling back to the skeleton URL when the thumbnail is blank, else null. Both
 * are http(s) remote URLs that the shared Coil singleton drives directly — no
 * per-card fetch-and-stage to a local path.
 */
internal fun resolveCommunityImageModel(pose: CommunityPose): String? = when {
    pose.thumbnailUrl.isNotBlank() -> pose.thumbnailUrl
    pose.skeletonUrl.isNotBlank() -> pose.skeletonUrl
    else -> null
}

/**
 * Bounded, deterministic downsampling target (px) for a community thumbnail:
 * at most the displayed grid cell, never the full remote image. Coil decodes
 * to this size (source larger than target is downsampled).
 */
internal fun communityImageTargetSize(cell: IntSize): IntSize =
    IntSize(width = cell.width.coerceAtLeast(1), height = cell.height.coerceAtLeast(1))

/**
 * Stable, collision-safe LazyGrid key for a community pose. Prefers the stable
 * [CommunityPose.poseId], then the thumbnail/skeleton URLs, with an index
 * fallback so the key is always non-blank and unique within its grid.
 */
internal fun communityPoseGridKey(pose: CommunityPose, index: Int): String =
    pose.poseId.ifBlank {
        pose.thumbnailUrl.ifBlank {
            pose.skeletonUrl.ifBlank { "community-idx-$index" }
        }
    }

data class PosesUiState(
    val communityState: CommunityLibraryState = CommunityLibraryState(),
)

/**
 * Community-only Poses feed ViewModel. The My Poses pane/tab was removed, so the
 * screen never queries/collects the local DB via [PosesLibraryCoordinator.getMyPoses]
 * and carries no tab selection state. The only browsable catalog is Community, whose
 * state is mirrored from the hoisted coordinator and auto-loaded on first composition.
 */
class PosesViewModel(
    private val coordinator: PosesLibraryCoordinator = PoseServiceLocator.coordinator,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main),
) {
    private val _uiState = MutableStateFlow(PosesUiState())
    val uiState: StateFlow<PosesUiState> = _uiState.asStateFlow()

    init {
        // Set server base URL from config
        PoseServiceLocator.baseUrl = AppConfig.SERVER_BASE_URL
        
        // Listen to community state changes from coordinator
        scope.launch {
            coordinator.communityState.collect { communityState ->
                _uiState.value = _uiState.value.copy(communityState = communityState)
            }
        }
    }

    fun loadCommunityPoses(refresh: Boolean = false) {
        if (refresh) {
            coordinator.refreshCommunity()
        } else {
            coordinator.loadCommunityInitial()
        }
    }

    fun loadMoreCommunityPoses() {
        coordinator.loadMoreCommunity()
    }

}

@Composable
fun PosesScreen(
    viewModel: PosesViewModel,
    communityGridState: LazyStaggeredGridState = rememberLazyStaggeredGridState(),
    onExtractPoseClick: () -> Unit,
    onPublishedPoseClick: (PosePreview) -> Unit = {},
    onBack: (() -> Unit)? = null,
    onSearchClick: (() -> Unit)? = null,
    modifier: Modifier = Modifier
) {
    val uiState by viewModel.uiState.collectAsState()

    // Community auto-loads only the first time the feed is composed (never loaded);
    // after ordinary Back the hoisted state keeps items, so this does not duplicate
    // the initial Community load. Refreshes stay explicit.
    LaunchedEffect(viewModel) {
        if (shouldAutoLoadCommunity(uiState.communityState.items.isNotEmpty())) {
            viewModel.loadCommunityPoses()
        }
    }

    Box(modifier = modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .padding(Spacing.lg),
            verticalArrangement = Arrangement.spacedBy(Spacing.lg)
        ) {
            // Community is the only pane: the header holds the static screen title
            // at the left, plus the search + create pose (+) affordances right-aligned
            // above the masonry feed.
            Row(
                modifier = Modifier.fillMaxWidth().height(52.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Community",
                    style = AiPoseTypography.Heading2,
                    color = AiPoseColors.Foreground,
                )
                Row(
                    horizontalArrangement = Arrangement.spacedBy(2.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // Prototype `.nb-btn--compact-action`: 44dp touch target
                    // wrapping a 32dp `.nb-btn__compact-surface` chip.
                    val searchInteractionSource = remember { MutableInteractionSource() }
                    Box(
                        modifier = Modifier
                            .size(44.dp)
                            .clickable(
                                interactionSource = searchInteractionSource,
                                indication = null,
                                role = Role.Button,
                                onClick = { onSearchClick?.invoke() }
                            ),
                        contentAlignment = Alignment.Center
                    ) {
                        NeoBrutalismContainer(
                            modifier = Modifier.size(32.dp).testTag(POSES_SEARCH_BUTTON_TEST_TAG),
                            shape = RoundedCornerShape(10.dp),
                            backgroundColor = AiPoseColors.Surface,
                            shadowOffset = 1.5.dp,
                            borderWidth = 2.dp,
                            interactionSource = searchInteractionSource
                        ) {
                            Icon(
                                imageVector = Icons.Default.Search,
                                contentDescription = "Search poses",
                                tint = AiPoseColors.Foreground,
                                modifier = Modifier.size(16.dp)
                            )
                        }
                    }

                    val addInteractionSource = remember { MutableInteractionSource() }
                    Box(
                        modifier = Modifier
                            .size(44.dp)
                            .clickable(
                                interactionSource = addInteractionSource,
                                indication = null,
                                role = Role.Button,
                                onClick = onExtractPoseClick
                            ),
                        contentAlignment = Alignment.Center
                    ) {
                        NeoBrutalismContainer(
                            modifier = Modifier.size(32.dp).testTag("extract-pose-button"),
                            shape = RoundedCornerShape(10.dp),
                            backgroundColor = AiPoseColors.Warning,
                            shadowOffset = 1.5.dp,
                            borderWidth = 2.dp,
                            interactionSource = addInteractionSource
                        ) {
                            Icon(
                                imageVector = Icons.Default.Add,
                                contentDescription = "Create Pose",
                                tint = AiPoseColors.Foreground,
                                modifier = Modifier.size(16.dp)
                            )
                        }
                    }
                }
            }

            CommunityContent(
                uiState = uiState,
                gridState = communityGridState,
                onPoseClick = onPublishedPoseClick,
                onLoadMore = viewModel::loadMoreCommunityPoses,
                onRefresh = { viewModel.loadCommunityPoses(refresh = true) },
                onRetryInitial = { viewModel.loadCommunityPoses(refresh = false) },
                onRetryLoadMore = viewModel::loadMoreCommunityPoses,
                onRetryRefresh = { viewModel.loadCommunityPoses(refresh = true) }
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CommunityContent(
    uiState: PosesUiState,
    gridState: LazyStaggeredGridState,
    onPoseClick: (PosePreview) -> Unit,
    onLoadMore: () -> Unit,
    onRefresh: () -> Unit,
    onRetryInitial: () -> Unit,
    onRetryLoadMore: () -> Unit,
    onRetryRefresh: () -> Unit
) {
    val state = uiState.communityState
    val pullToRefreshState = rememberPullToRefreshState()
    val isRefreshing = state.refreshState is OperationState.Loading && state.items.isNotEmpty()

    LaunchedEffect(pullToRefreshState.isRefreshing) {
        if (pullToRefreshState.isRefreshing) {
            onRefresh()
        }
    }

    LaunchedEffect(isRefreshing) {
        if (!isRefreshing && pullToRefreshState.isRefreshing) {
            pullToRefreshState.endRefresh()
        }
    }

    Column(modifier = Modifier.fillMaxSize()) {
        // Refresh error banner
        if (state.refreshState is OperationState.Error) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(AiPoseColors.Error.copy(alpha = 0.15f))
                    .padding(Spacing.md)
                    .testTag("retry-refresh-banner"),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Refresh failed. Showing previous catalog.",
                    style = AiPoseTypography.Caption,
                    color = AiPoseColors.Error
                )
                PrimaryButton(
                    text = "Retry",
                    onClick = onRetryRefresh,
                    modifier = Modifier
                        .size(width = 80.dp, height = 30.dp)
                        .testTag("retry-refresh-button")
                )
            }
        }

        when {
            state.initialLoadState is OperationState.Loading && state.items.isEmpty() -> {
                Box(modifier = Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = AiPoseColors.Primary)
                }
            }
            state.initialLoadState is OperationState.Error && state.items.isEmpty() -> {
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth()
                        .padding(Spacing.lg)
                        .testTag("initial-load-error-state"),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center
                ) {
                    Text(
                        text = "Failed to load poses",
                        style = AiPoseTypography.Heading3,
                        color = AiPoseColors.Error
                    )
                    Text(
                        text = (state.initialLoadState as OperationState.Error).message,
                        style = AiPoseTypography.Body,
                        color = AiPoseColors.Subtext,
                        modifier = Modifier.padding(top = Spacing.sm, bottom = Spacing.lg)
                    )
                    PrimaryButton(
                        text = "Retry",
                        onClick = onRetryInitial,
                        modifier = Modifier.testTag("retry-initial-button")
                    )
                }
            }
            state.items.isEmpty() -> {
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth()
                        .padding(Spacing.lg),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center
                ) {
                    Text(
                        "No poses found.",
                        style = AiPoseTypography.Body,
                        color = AiPoseColors.Subtext,
                        modifier = Modifier.testTag("empty-poses-text")
                    )
                }
            }
            else -> {
                Column(
                    modifier = Modifier.weight(1f).fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(Spacing.md)
                ) {
                    CountOnlyHeader(count = state.total, modifier = Modifier.fillMaxWidth())

                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .nestedScroll(pullToRefreshState.nestedScrollConnection)
                    ) {
                        LazyVerticalStaggeredGrid(
                            modifier = Modifier.fillMaxSize(),
                            state = gridState,
                            columns = StaggeredGridCells.Fixed(2),
                            contentPadding = PaddingValues(bottom = MainDockContentInset),
                            horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                            verticalItemSpacing = Spacing.sm,
                        ) {
                            itemsIndexed(
                                state.items,
                                key = { index, pose -> communityPoseGridKey(pose, index) },
                                contentType = { _, _ -> CommunityPose::class },
                            ) { index, pose ->
                                CommunityPoseCard(pose = pose, index = index, onClick = onPoseClick)
                            }
                            if (state.hasMore) {
                                if (state.loadMoreState is OperationState.Loading) {
                                    item(span = StaggeredGridItemSpan.FullLine) {
                                        Box(
                                            modifier = Modifier.fillMaxWidth().padding(Spacing.md),
                                            contentAlignment = Alignment.Center,
                                        ) {
                                            CommunityLoadingIndicator()
                                        }
                                    }
                                } else if (state.loadMoreState is OperationState.Error) {
                                    item(span = StaggeredGridItemSpan.FullLine) {
                                        Column(
                                            modifier = Modifier
                                                .fillMaxWidth()
                                                .padding(Spacing.md)
                                                .testTag("load-more-error-state"),
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
                                                modifier = Modifier.testTag("retry-load-more-button"),
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

                        PullToRefreshContainer(
                            state = pullToRefreshState,
                            modifier = Modifier.align(Alignment.TopCenter),
                            containerColor = AiPoseColors.Surface,
                            contentColor = AiPoseColors.Primary
                        )
                    }
                }
            }
        }
    }
}

@Composable
internal fun CommunityLoadingIndicator(modifier: Modifier = Modifier) {
    CircularProgressIndicator(
        color = AiPoseColors.Subtext.copy(alpha = COMMUNITY_LOADING_ALPHA),
        modifier = modifier.size(COMMUNITY_LOADING_SIZE.dp),
        strokeWidth = COMMUNITY_LOADING_STROKE.dp,
        trackColor = AiPoseColors.Subtext.copy(alpha = 0.1f),
    )
}

@Composable
fun CommunityPoseCard(
    pose: CommunityPose,
    index: Int,
    onClick: (PosePreview) -> Unit,
    modifier: Modifier = Modifier
) {
    var sourceBounds by remember { androidx.compose.runtime.mutableStateOf<androidx.compose.ui.geometry.Rect?>(null) }
    val aspectRatio = communityCardAspectRatio(index)
    val cardShape = RoundedCornerShape(CornerRadius.md)

    // Single Coil model driven directly by AsyncImage/ImageRequest — thumbnail URL
    // with the skeleton URL as fallback when the thumbnail is blank. The shared
    // singleton ImageLoader (bounded memory + disk caches) owns all caching, so
    // there is no per-card fetch-and-stage / manual bitmap decode anymore.
    val model = remember(pose.thumbnailUrl, pose.skeletonUrl) {
        resolveCommunityImageModel(pose)
    }

    // Measured grid cell (already in px). Drives deterministic bounded sizing so
    // Coil downsamples to at most the displayed cell instead of the full remote image.
    var cellSizePx by remember { androidx.compose.runtime.mutableStateOf<IntSize?>(null) }

    val platformContext = LocalPlatformContext.current
    val request = remember(model, cellSizePx, platformContext) {
        val cell = cellSizePx
        if (model == null || cell == null) null
        else {
            val target = communityImageTargetSize(cell)
            ImageRequest.Builder(platformContext)
                .data(model)
                .size(target.width, target.height)
                .build()
        }
    }

    val isTransitioning = MatchedImageTransitionState.source?.key == "pose:${pose.poseId}" &&
            MatchedImageTransitionState.transitionPhase != com.aipose.navigation.SharedTransitionPhase.IDLE
    val contentModifier = Modifier
        .fillMaxSize()
        .onSizeChanged { cellSizePx = it }
        .onGloballyPositioned { sourceBounds = it.boundsInWindow() }

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(Spacing.sm)
    ) {
        NeoBrutalismContainer(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(aspectRatio)
                .testTag("pose-card-community-${pose.poseId}")
                .semantics { contentDescription = pose.name },
            shape = cardShape,
            backgroundColor = AiPoseColors.Surface,
            shadowOffset = 4.dp,
            onClick = {
                sourceBounds?.let {
                    MatchedImageTransitionState.capture(
                        key = "pose:${pose.poseId}",
                        bounds = it,
                        imageModel = model,
                        cornerRadius = CornerRadius.md,
                        contentScale = poseThumbnailContentScale()
                    )
                }
                onClick(
                    communityPosePreview(
                        pose = pose,
                        aspectRatio = aspectRatio,
                        cornerRadius = CornerRadius.md,
                    )
                )
            }
        ) {
            // Rounded, neutral loading / error surface (never a full-card red diagnostic
            // in release). PNG alpha is preserved by Coil + ContentScale.Crop.
            val imageModifier = contentModifier
                .graphicsLayer { alpha = if (isTransitioning) 0f else 1f }
                .clip(cardShape)
            when {
                model == null -> {
                    Icon(
                        imageVector = Icons.Default.Image,
                        contentDescription = null,
                        tint = AiPoseColors.Subtext,
                        modifier = imageModifier.size(40.dp)
                    )
                }
                request == null -> {
                    Box(modifier = imageModifier, contentAlignment = Alignment.Center) {
                        CommunityLoadingIndicator()
                    }
                }
                else -> {
                    SubcomposeAsyncImage(
                        model = request,
                        contentDescription = null,
                        modifier = imageModifier,
                        contentScale = poseThumbnailContentScale(),
                        loading = {
                            CommunityLoadingIndicator()
                        },
                        error = {
                            Icon(
                                imageVector = Icons.Default.Image,
                                contentDescription = null,
                                tint = AiPoseColors.Subtext,
                                modifier = Modifier.size(40.dp)
                            )
                        }
                    )
                }
            }
        }

        Text(
            text = pose.name,
            style = AiPoseTypography.BodyBold,
            color = AiPoseColors.Foreground,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(start = 2.dp)
        )
    }
}

@Composable
fun CountOnlyHeader(
    count: Int,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.End,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = "$count poses",
            style = AiPoseTypography.CaptionBold,
            color = AiPoseColors.Subtext,
            modifier = Modifier.testTag("poses-count-label")
        )
    }
}
