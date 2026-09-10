package com.aipose.ui.screens.poses

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.lazy.staggeredgrid.LazyVerticalStaggeredGrid
import androidx.compose.foundation.lazy.staggeredgrid.StaggeredGridCells
import androidx.compose.foundation.lazy.staggeredgrid.StaggeredGridItemSpan
import androidx.compose.foundation.lazy.staggeredgrid.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.unit.dp
import cafe.adriel.voyager.core.screen.Screen
import com.aipose.data.CommunitySearchPagingController
import com.aipose.data.CommunitySearchRepository
import com.aipose.data.PoseServiceLocator
import com.aipose.data.remote.CommunityPose
import com.aipose.ui.components.NeoBrutalismContainer
import com.aipose.ui.components.PrimaryButton
import com.aipose.ui.theme.AiPoseColors
import com.aipose.ui.theme.AiPoseTypography
import com.aipose.ui.theme.Spacing
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import org.jetbrains.compose.resources.painterResource
import ai_pose.composeapp.generated.resources.Res
import ai_pose.composeapp.generated.resources.ic_chevron_left

private val SearchPrototypeBackground = Color(0xFFFBF6EF)
private val SearchPrototypePink = Color(0xFFE89CAE)
private val SearchPrototypeBlack = Color(0xFF121212)
private val SearchPrototypeWhite = Color.White
private val searchSourceFilterLabels = listOf("All poses", "My poses", "Community")
private val recentSearchLabels = listOf("Dancing", "Stretching", "Warrior")

data class SearchUiState(
    val query: String = "",
    val publishedResults: List<CommunityPose> = emptyList(),
    val communityHasMore: Boolean = false,
    val isInitialLoading: Boolean = false,
    val isLoadingMore: Boolean = false,
    val searchError: String? = null,
    val loadMoreError: String? = null,
)

internal fun searchResultsCountLabel(total: Int, query: String): String {
    val unit = if (total == 1) "pose" else "poses"
    val trimmed = query.trim()
    return if (trimmed.isEmpty()) {
        "$total $unit"
    } else {
        "$total $unit for “$trimmed”"
    }
}

internal fun emptySearchTitle(): String = "No matching poses"

internal fun emptySearchSubtitle(query: String): String {
    val trimmed = query.trim()
    return if (trimmed.isEmpty()) {
        "No poses to search yet."
    } else {
        "No poses match “$trimmed”. Try a different title."
    }
}

internal fun clearSearchActionLabel(): String = "Clear search"

class SearchViewModel(
    private val communitySearchRepository: CommunitySearchRepository = PoseServiceLocator.communitySearchRepository,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main),
) {
    private val communityPaging = CommunitySearchPagingController(communitySearchRepository, scope)

    private val _uiState = MutableStateFlow(SearchUiState())
    val uiState: StateFlow<SearchUiState> = _uiState.asStateFlow()

    init {
        scope.launch {
            communityPaging.state.collectLatest { paging ->
                val currentTrimmed = _uiState.value.query.trim()
                if (currentTrimmed.isEmpty()) return@collectLatest
                if (paging.query.trim() != currentTrimmed) return@collectLatest
                _uiState.value = _uiState.value.copy(
                    publishedResults = paging.items,
                    communityHasMore = paging.hasMore,
                    isInitialLoading = paging.isInitialLoading,
                    isLoadingMore = paging.isLoadingMore,
                    searchError = paging.initialError,
                    loadMoreError = paging.loadMoreError,
                )
            }
        }
    }

    fun onQueryChange(newQuery: String) {
        _uiState.value = _uiState.value.copy(query = newQuery)
        val trimmed = newQuery.trim()
        if (trimmed.isNotEmpty()) {
            communityPaging.search(trimmed)
        } else {
            resetPublishedStateInMemory()
        }
    }

    fun clearQuery() {
        onQueryChange("")
    }

    fun retrySearch() {
        val trimmed = _uiState.value.query.trim()
        if (trimmed.isNotEmpty()) {
            communityPaging.retryInitial()
        }
    }

    fun loadMoreCommunity() {
        communityPaging.loadMore()
    }

    fun retryLoadMore() {
        communityPaging.retryLoadMore()
    }

    private fun resetPublishedStateInMemory() {
        _uiState.value = _uiState.value.copy(
            publishedResults = emptyList(),
            communityHasMore = false,
            isInitialLoading = false,
            isLoadingMore = false,
            searchError = null,
            loadMoreError = null,
        )
    }
}

class SearchScreen(
    private val onPublishedPoseClick: (PosePreview) -> Unit,
    private val onBack: () -> Unit,
) : Screen {

    @Composable
    override fun Content() {
        val viewModel = remember { SearchViewModel() }
        val uiState by viewModel.uiState.collectAsState()
        val focusRequester = remember { FocusRequester() }
        val focusManager = LocalFocusManager.current
        val keyboardController = LocalSoftwareKeyboardController.current
        var selectedSourceFilter by remember { mutableStateOf(searchSourceFilterLabels.first()) }

        val hasActiveQuery = uiState.query.trim().isNotEmpty()
        val displayedResults = if (selectedSourceFilter == "My poses") {
            emptyList()
        } else {
            uiState.publishedResults
        }
        val displayedCount = displayedResults.size
        val showResultsPanel = hasActiveQuery || uiState.searchError != null
        val showEmptyState =
            showResultsPanel &&
            !uiState.isInitialLoading &&
                displayedCount == 0 &&
                uiState.searchError == null

        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(SearchPrototypeBackground)
                .statusBarsPadding()
                .padding(Spacing.lg)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    onClick = {
                        focusManager.clearFocus()
                        keyboardController?.hide()
                    }
                ),
        ) {
            Column(
                modifier = Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(44.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    NeoBrutalismContainer(
                        modifier = Modifier.size(44.dp),
                        shape = RoundedCornerShape(10.dp),
                        backgroundColor = SearchPrototypeWhite,
                        shadowColor = SearchPrototypeBlack,
                        shadowOffset = 3.dp,
                        borderWidth = 2.dp,
                        onClick = onBack,
                    ) {
                        Icon(
                            painter = painterResource(Res.drawable.ic_chevron_left),
                            contentDescription = "Back",
                            tint = SearchPrototypeBlack,
                            modifier = Modifier.size(20.dp),
                        )
                    }
                    Box(
                        modifier = Modifier.weight(1f),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            text = "Search",
                            style = AiPoseTypography.NavigationTitle,
                            color = SearchPrototypeBlack,
                        )
                    }
                    Spacer(modifier = Modifier.size(44.dp))
                }

                NeoBrutalismContainer(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(56.dp)
                        .testTag("search-field")
                        .semantics { contentDescription = "Search poses by title" },
                    shape = RoundedCornerShape(14.dp),
                    backgroundColor = SearchPrototypeWhite,
                    shadowColor = SearchPrototypeBlack,
                    shadowOffset = 3.dp,
                    borderWidth = 2.dp,
                ) {
                    BasicTextField(
                        value = uiState.query,
                        onValueChange = viewModel::onQueryChange,
                        modifier = Modifier
                            .fillMaxSize()
                            .focusRequester(focusRequester),
                        textStyle = AiPoseTypography.Input.copy(color = SearchPrototypeBlack),
                        singleLine = true,
                        cursorBrush = SolidColor(SearchPrototypeBlack),
                        decorationBox = { innerTextField ->
                            Row(
                                modifier = Modifier
                                    .fillMaxSize()
                                    .padding(start = 12.dp, end = 2.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Icon(
                                    imageVector = Icons.Default.Search,
                                    contentDescription = null,
                                    tint = SearchPrototypeBlack,
                                    modifier = Modifier.size(20.dp),
                                )
                                Box(
                                    modifier = Modifier
                                        .weight(1f)
                                        .padding(horizontal = 8.dp),
                                    contentAlignment = Alignment.CenterStart,
                                ) {
                                    if (uiState.query.isEmpty()) {
                                        Text(
                                            text = "Search poses",
                                            style = AiPoseTypography.Input,
                                            color = AiPoseColors.Subtext,
                                        )
                                    }
                                    innerTextField()
                                }
                                if (uiState.query.isNotEmpty()) {
                                    IconButton(
                                        onClick = {
                                            selectedSourceFilter = searchSourceFilterLabels.first()
                                            viewModel.clearQuery()
                                        },
                                        modifier = Modifier
                                            .size(44.dp)
                                            .testTag("search-clear-button"),
                                    ) {
                                        Icon(
                                            imageVector = Icons.Default.Close,
                                            contentDescription = "Clear",
                                            tint = SearchPrototypeBlack,
                                        )
                                    }
                                } else {
                                    Spacer(modifier = Modifier.size(44.dp))
                                }
                            }
                        },
                    )
                }

                if (!hasActiveQuery && uiState.searchError == null) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .testTag("recent-searches"),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text(
                            text = "Recent searches",
                            style = AiPoseTypography.Heading3,
                            color = SearchPrototypeBlack,
                        )
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .horizontalScroll(rememberScrollState()),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            recentSearchLabels.forEach { label ->
                                NeoBrutalismContainer(
                                    modifier = Modifier
                                        .height(44.dp)
                                        .semantics {
                                            testTag = "recent-search-chip-${label.lowercase()}"
                                            contentDescription = "Search recent $label"
                                        },
                                    shape = RoundedCornerShape(10.dp),
                                    backgroundColor = SearchPrototypeWhite,
                                    shadowColor = SearchPrototypeBlack,
                                    shadowOffset = 1.5.dp,
                                    borderWidth = 1.5.dp,
                                    onClick = {
                                        selectedSourceFilter = searchSourceFilterLabels.first()
                                        viewModel.onQueryChange(label)
                                    },
                                ) {
                                    Text(
                                        text = label,
                                        style = AiPoseTypography.Control,
                                        color = SearchPrototypeBlack,
                                        modifier = Modifier.padding(horizontal = 12.dp),
                                    )
                                }
                            }
                        }
                    }
                }

                uiState.searchError?.let { message ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(AiPoseColors.Error.copy(alpha = 0.15f))
                            .padding(Spacing.md)
                            .testTag("search-error-banner"),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            text = message,
                            style = AiPoseTypography.Caption,
                            color = AiPoseColors.Error,
                        )
                        PrimaryButton(
                            text = "Retry",
                            onClick = viewModel::retrySearch,
                            modifier = Modifier
                                .size(width = 80.dp, height = 30.dp)
                                .testTag("search-retry-button"),
                        )
                    }
                }

                if (showResultsPanel) {
                    Column(
                        modifier = Modifier.fillMaxWidth(),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.Bottom,
                            horizontalArrangement = Arrangement.SpaceBetween,
                        ) {
                            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                Text(
                                    text = "YOUR MATCHES",
                                    style = AiPoseTypography.MetaLabel,
                                    color = AiPoseColors.Subtext,
                                )
                                Text(
                                    text = "Results",
                                    style = AiPoseTypography.Heading3,
                                    color = SearchPrototypeBlack,
                                )
                            }
                            Text(
                                text = when {
                                    uiState.isInitialLoading -> "Loading"
                                    uiState.searchError != null && displayedCount == 0 -> "Unavailable"
                                    else -> searchResultsCountLabel(displayedCount, uiState.query)
                                },
                                style = AiPoseTypography.Caption,
                                color = AiPoseColors.Subtext,
                                modifier = Modifier.testTag("search-results-count"),
                            )
                        }
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .horizontalScroll(rememberScrollState())
                                .testTag("search-source-filters"),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            searchSourceFilterLabels.forEach { label ->
                                val isActive = selectedSourceFilter == label
                                NeoBrutalismContainer(
                                    modifier = Modifier
                                        .height(44.dp)
                                        .semantics {
                                            testTag = "search-source-filter-${label.lowercase().replace(' ', '-') }"
                                            contentDescription = "$label search filter"
                                        },
                                    shape = RoundedCornerShape(10.dp),
                                    backgroundColor = if (isActive) SearchPrototypePink else SearchPrototypeWhite,
                                    shadowColor = SearchPrototypeBlack,
                                    shadowOffset = if (isActive) 1.5.dp else 0.dp,
                                    borderWidth = if (isActive) 2.dp else 1.5.dp,
                                    hasShadow = isActive,
                                    onClick = { selectedSourceFilter = label },
                                ) {
                                    Text(
                                        text = label,
                                        style = AiPoseTypography.Control,
                                        color = SearchPrototypeBlack,
                                        modifier = Modifier.padding(horizontal = 12.dp),
                                    )
                                }
                            }
                        }
                    }
                }

                if (showEmptyState) {
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(horizontal = Spacing.lg)
                            .testTag("empty-search-state"),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center,
                    ) {
                        Text(
                            text = emptySearchTitle(),
                            style = AiPoseTypography.Control,
                            color = AiPoseColors.Foreground,
                            modifier = Modifier.testTag("empty-search-title"),
                        )
                        Spacer(modifier = Modifier.height(Spacing.sm))
                        Text(
                            text = emptySearchSubtitle(uiState.query),
                            style = AiPoseTypography.Body,
                            color = AiPoseColors.Subtext,
                            modifier = Modifier.testTag("empty-search-subtitle"),
                        )
                        if (hasActiveQuery) {
                            Spacer(modifier = Modifier.height(Spacing.md))
                            PrimaryButton(
                                text = clearSearchActionLabel(),
                                onClick = viewModel::clearQuery,
                                modifier = Modifier.testTag("search-reset-button"),
                            )
                        }
                    }
                } else if (uiState.isInitialLoading && displayedCount == 0 && hasActiveQuery) {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .testTag("search-initial-loading"),
                        contentAlignment = Alignment.Center,
                    ) {
                        CircularProgressIndicator(color = AiPoseColors.Primary)
                    }
                } else if (displayedCount > 0) {
                    LazyVerticalStaggeredGrid(
                        modifier = Modifier.fillMaxSize(),
                        columns = StaggeredGridCells.Fixed(2),
                        horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                        verticalItemSpacing = Spacing.sm,
                    ) {
                        itemsIndexed(
                            displayedResults,
                            key = { index, pose -> "published-${communityPoseGridKey(pose, index)}" },
                        ) { index, pose ->
                            CommunityPoseCard(
                                pose = pose,
                                index = index,
                                onClick = onPublishedPoseClick,
                            )
                        }

                        if (uiState.communityHasMore && selectedSourceFilter != "My poses") {
                            if (uiState.isLoadingMore) {
                                item(span = StaggeredGridItemSpan.FullLine) {
                                    Box(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .padding(Spacing.md)
                                            .testTag("search-load-more-loading"),
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
                                            .testTag("search-load-more-error"),
                                        horizontalAlignment = Alignment.CenterHorizontally,
                                        verticalArrangement = Arrangement.spacedBy(Spacing.xs),
                                    ) {
                                        Text(
                                            text = uiState.loadMoreError ?: "Load more failed.",
                                            style = AiPoseTypography.Caption,
                                            color = AiPoseColors.Error,
                                        )
                                        PrimaryButton(
                                            text = "Retry",
                                            onClick = viewModel::retryLoadMore,
                                            modifier = Modifier.testTag("search-retry-load-more-button"),
                                        )
                                    }
                                }
                            } else {
                                item(span = StaggeredGridItemSpan.FullLine) {
                                    LaunchedEffect(uiState.publishedResults.size) {
                                        viewModel.loadMoreCommunity()
                                    }
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
