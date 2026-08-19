package com.aipose.ui.screens.poses

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.selection.selectable
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Search
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
import androidx.compose.ui.graphics.Color
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import org.jetbrains.compose.resources.painterResource
import ai_pose.composeapp.generated.resources.Res
import ai_pose.composeapp.generated.resources.ic_refresh_cw
import coil3.compose.AsyncImage
import com.aipose.Pose
import com.aipose.data.AppConfig
import com.aipose.data.CommunityLibraryState
import com.aipose.data.OperationState
import com.aipose.data.PoseServiceLocator
import com.aipose.data.PosesLibraryCoordinator
import com.aipose.data.remote.CommunityPose
import com.aipose.navigation.MainDockContentInset
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
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

/** E-SEARCH-WIRED: stable test tag for the poses-list search affordance. */
internal const val POSES_SEARCH_BUTTON_TEST_TAG = "poses-search-button"

data class PosesUiState(
    val myPoses: List<Pose> = emptyList(),
    val communityState: CommunityLibraryState = CommunityLibraryState(),
    val isLoading: Boolean = true,
    val selectedTab: Int = 0
)

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

    suspend fun load() {
        coordinator.getMyPoses().collectLatest { poses ->
            _uiState.value = _uiState.value.copy(myPoses = poses, isLoading = false)
        }
    }

    fun selectTab(index: Int) {
        _uiState.value = _uiState.value.copy(selectedTab = index)
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
    onPoseClick: (Long) -> Unit,
    onExtractPoseClick: () -> Unit,
    onCommunityPoseClick: (CommunityPose) -> Unit = {},
    onBack: (() -> Unit)? = null,
    onSearchClick: (() -> Unit)? = null,
    modifier: Modifier = Modifier
) {
    val uiState by viewModel.uiState.collectAsState()

    LaunchedEffect(viewModel) {
        viewModel.load()
    }

    LaunchedEffect(uiState.selectedTab) {
        if (uiState.selectedTab == 1 && uiState.communityState.items.isEmpty()) {
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
            Row(
                modifier = Modifier.fillMaxWidth().height(52.dp),
                horizontalArrangement = Arrangement.Start,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(
                    horizontalArrangement = Arrangement.Start,
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.weight(1f)
                ) {
                    ToolbarTab(
                        title = "My Poses",
                        isSelected = uiState.selectedTab == 0,
                        onClick = { viewModel.selectTab(0) },
                        modifier = Modifier.testTag("tab-my-poses")
                    )
                    ToolbarTab(
                        title = "Community",
                        isSelected = uiState.selectedTab == 1,
                        onClick = { viewModel.selectTab(1) },
                        modifier = Modifier.testTag("tab-community")
                    )
                }

                Row(
                    horizontalArrangement = Arrangement.spacedBy(2.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    NeoBrutalismContainer(
                        modifier = Modifier.size(44.dp).testTag(POSES_SEARCH_BUTTON_TEST_TAG),
                        shape = RoundedCornerShape(10.dp),
                        backgroundColor = AiPoseColors.Background,
                        shadowOffset = 2.dp,
                        borderWidth = 2.dp,
                        onClick = { onSearchClick?.invoke() }
                    ) {
                        Icon(
                            imageVector = Icons.Default.Search,
                            contentDescription = "Search poses",
                            tint = AiPoseColors.Foreground,
                            modifier = Modifier.size(16.dp)
                        )
                    }

                    NeoBrutalismContainer(
                        modifier = Modifier.size(44.dp).testTag("extract-pose-button"),
                        shape = RoundedCornerShape(10.dp),
                        backgroundColor = AiPoseColors.Background,
                        shadowOffset = 2.dp,
                        borderWidth = 2.dp,
                        onClick = onExtractPoseClick
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

            when (uiState.selectedTab) {
                0 -> MyPosesContent(
                    uiState = uiState,
                    onPoseClick = onPoseClick,
                    onExtractPoseClick = onExtractPoseClick
                )
                1 -> CommunityContent(
                    uiState = uiState,
                    onPoseClick = onCommunityPoseClick,
                    onLoadMore = viewModel::loadMoreCommunityPoses,
                    onRefresh = { viewModel.loadCommunityPoses(refresh = true) },
                    onRetryInitial = { viewModel.loadCommunityPoses(refresh = false) },
                    onRetryLoadMore = viewModel::loadMoreCommunityPoses,
                    onRetryRefresh = { viewModel.loadCommunityPoses(refresh = true) }
                )
            }
        }
    }
}

@Composable
private fun MyPosesContent(
    uiState: PosesUiState,
    onPoseClick: (Long) -> Unit,
    onExtractPoseClick: () -> Unit
) {
    when {
        uiState.isLoading -> {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = AiPoseColors.Primary)
            }
        }
        uiState.myPoses.isEmpty() -> {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = Spacing.lg),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                Text(
                    text = "No poses found.",
                    style = AiPoseTypography.Body,
                    color = AiPoseColors.Subtext,
                    modifier = Modifier.padding(bottom = Spacing.lg).testTag("empty-poses-text")
                )
                PrimaryButton(
                    text = "Create Pose",
                    onClick = onExtractPoseClick,
                    modifier = Modifier.testTag("extract-pose-cta")
                )
            }
        }
        else -> {
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
                CountOnlyHeader(count = uiState.myPoses.size)
                LazyVerticalGrid(
                    modifier = Modifier.fillMaxSize(),
                    columns = GridCells.Fixed(2),
                    contentPadding = PaddingValues(bottom = MainDockContentInset),
                    horizontalArrangement = Arrangement.spacedBy(Spacing.md),
                    verticalArrangement = Arrangement.spacedBy(Spacing.md)
                ) {
                    itemsIndexed(uiState.myPoses, key = { _, pose -> pose.id }) { index, pose ->
                        PoseCard(pose = pose, index = index, onClick = { onPoseClick(pose.id) })
                    }
                }
            }
        }
    }
}

@Composable
private fun CommunityContent(
    uiState: PosesUiState,
    onPoseClick: (CommunityPose) -> Unit,
    onLoadMore: () -> Unit,
    onRefresh: () -> Unit,
    onRetryInitial: () -> Unit,
    onRetryLoadMore: () -> Unit,
    onRetryRefresh: () -> Unit
) {
    val state = uiState.communityState

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
                        text = "FAILED TO LOAD POSES",
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
                    PrimaryButton(
                        text = "Refresh",
                        onClick = onRefresh,
                        modifier = Modifier
                            .padding(top = Spacing.md)
                            .testTag("community-empty-refresh-button")
                    )
                }
            }
            else -> {
                Column(
                    modifier = Modifier.weight(1f).fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(Spacing.md)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        CountOnlyHeader(count = state.total, modifier = Modifier.weight(1f))
                        NeoBrutalismContainer(
                            modifier = Modifier
                                .size(36.dp)
                                .testTag("community-refresh-button"),
                            shape = RoundedCornerShape(8.dp),
                            backgroundColor = AiPoseColors.Background,
                            shadowOffset = 2.dp,
                            borderWidth = 2.dp,
                            onClick = onRefresh
                        ) {
                            Icon(
                                painter = painterResource(Res.drawable.ic_refresh_cw),
                                contentDescription = "Refresh community poses",
                                tint = AiPoseColors.Foreground,
                                modifier = Modifier.size(16.dp)
                            )
                        }
                    }
                    LazyVerticalGrid(
                        modifier = Modifier.fillMaxSize(),
                        columns = GridCells.Fixed(2),
                        contentPadding = PaddingValues(bottom = MainDockContentInset),
                        horizontalArrangement = Arrangement.spacedBy(Spacing.md),
                        verticalArrangement = Arrangement.spacedBy(Spacing.md)
                    ) {
                        itemsIndexed(state.items, key = { _, pose -> pose.id }) { index, pose ->
                            CommunityPoseCard(pose = pose, index = index, onClick = { onPoseClick(pose) })
                        }
                        if (state.hasMore) {
                            if (state.loadMoreState is OperationState.Loading) {
                                item {
                                    Box(
                                        modifier = Modifier.fillMaxWidth().padding(Spacing.md),
                                        contentAlignment = Alignment.Center
                                    ) {
                                        CircularProgressIndicator(color = AiPoseColors.Primary)
                                    }
                                }
                            } else if (state.loadMoreState is OperationState.Error) {
                                item {
                                    Column(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .padding(Spacing.md)
                                            .testTag("load-more-error-state"),
                                        horizontalAlignment = Alignment.CenterHorizontally,
                                        verticalArrangement = Arrangement.spacedBy(Spacing.xs)
                                    ) {
                                        Text(
                                            text = "Load more failed.",
                                            style = AiPoseTypography.Caption,
                                            color = AiPoseColors.Error
                                        )
                                        PrimaryButton(
                                            text = "Retry",
                                            onClick = onRetryLoadMore,
                                            modifier = Modifier.testTag("retry-load-more-button")
                                        )
                                    }
                                }
                            } else {
                                item {
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

@Composable
fun CommunityPoseCard(
    pose: CommunityPose,
    index: Int,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val aspectRatios = listOf(1f / 1.25f, 1f, 1.25f / 1f)
    val aspectRatio = aspectRatios[index % 3]

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(Spacing.sm)
    ) {
        NeoBrutalismContainer(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(aspectRatio)
                .testTag("pose-card-community-${pose.id}")
                .semantics { contentDescription = pose.name },
            shape = RoundedCornerShape(CornerRadius.md),
            backgroundColor = AiPoseColors.Surface,
            shadowOffset = 4.dp,
            onClick = onClick
        ) {
            val imageModel = pose.thumbnailPath ?: pose.imagePath
            if (imageModel.isNotBlank()) {
                AsyncImage(
                    model = imageModel,
                    contentDescription = null,
                    modifier = Modifier.fillMaxWidth(),
                    contentScale = ContentScale.Crop
                )
            } else {
                Icon(
                    imageVector = Icons.Default.Image,
                    contentDescription = null,
                    modifier = Modifier.size(40.dp),
                    tint = AiPoseColors.Subtext
                )
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
            text = "$count Poses",
            style = AiPoseTypography.Caption,
            color = AiPoseColors.Subtext,
            modifier = Modifier.testTag("poses-count-label")
        )
    }
}

@Composable
fun ToolbarTab(
    title: String,
    isSelected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val interactionSource = remember { MutableInteractionSource() }
    Box(
        modifier = modifier
            .selectable(
                selected = isSelected,
                interactionSource = interactionSource,
                indication = null,
                role = Role.Tab,
                onClick = onClick
            )
            .padding(horizontal = Spacing.sm, vertical = 8.dp),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text(
                text = title,
                style = AiPoseTypography.BodyBold,
                color = if (isSelected) AiPoseColors.Foreground else AiPoseColors.Subtext
            )
            Box(
                modifier = Modifier
                    .width(48.dp)
                    .height(4.dp)
                    .background(
                        color = if (isSelected) AiPoseColors.AccentBlue else Color.Transparent,
                        shape = RoundedCornerShape(topStart = 2.dp, topEnd = 2.dp)
                    )
                    .border(
                        width = 1.5.dp,
                        color = if (isSelected) AiPoseColors.Foreground else Color.Transparent,
                        shape = RoundedCornerShape(topStart = 2.dp, topEnd = 2.dp)
                    )
            )
        }
    }
}
