package com.aipose.camera

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Image
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import coil3.compose.LocalPlatformContext
import coil3.compose.SubcomposeAsyncImage
import coil3.request.ImageRequest
import com.aipose.auth.SignInIntent
import com.aipose.auth.SignInPrompt
import com.aipose.auth.SignInPromptController
import com.aipose.auth.hasValidStoredSession
import com.aipose.auth.platformGoogleSignInLauncher
import com.aipose.data.OperationState
import com.aipose.data.PoseImageVerification
import com.aipose.data.PoseServiceLocator
import com.aipose.data.PreparedPoseReference
import com.aipose.data.PosesLibraryCoordinator
import com.aipose.data.remote.CommunityPose
import com.aipose.data.remote.PoseApiService
import com.aipose.ui.components.NeoBrutalismContainer
import com.aipose.ui.components.PrimaryButton
import com.aipose.ui.screens.poses.COMMUNITY_LOADING_ALPHA
import com.aipose.ui.screens.poses.COMMUNITY_LOADING_SIZE
import com.aipose.ui.screens.poses.COMMUNITY_LOADING_STROKE
import com.aipose.ui.screens.poses.communityImageTargetSize
import com.aipose.ui.screens.poses.communityPoseGridKey
import com.aipose.ui.screens.poses.poseThumbnailContentScale
import com.aipose.ui.screens.poses.resolveCommunityImageModel
import com.aipose.ui.theme.AiPoseColors
import com.aipose.ui.theme.AiPoseTypography
import com.aipose.ui.theme.CornerRadius
import com.aipose.ui.theme.Spacing
import kotlinx.coroutines.launch

internal const val POSE_GUIDE_PICKER_TEST_TAG = "pose-guide-picker"
internal const val POSE_GUIDE_PICKER_BACK_TEST_TAG = "pose-guide-picker-back"

sealed interface PoseGuidePickerActionState {
    data object Idle : PoseGuidePickerActionState
    data object Preparing : PoseGuidePickerActionState
    data class Error(val message: String) : PoseGuidePickerActionState
}

/**
 * Downloads and verifies a published community skeleton into the existing
 * [PreparedPoseReference] contract. Throws on blank URL, download failure, or
 * unsupported MIME — the picker retains selection and surfaces retry in place.
 */
internal suspend fun prepareCommunityPoseReference(
    pose: CommunityPose,
    downloadBytes: suspend (String) -> ByteArray,
): PreparedPoseReference {
    val skeletonUrl = pose.skeletonUrl
    if (skeletonUrl.isBlank()) {
        throw IllegalStateException("This pose has no skeleton to prepare.")
    }
    val bytes = downloadBytes(skeletonUrl)
    val mimeType = PoseImageVerification.detectImageMimeType(bytes)
        ?: throw IllegalStateException("The skeleton image could not be decoded.")
    val verifiedPath = PoseImageVerification.toDataUri(bytes, mimeType)
    return PreparedPoseReference(
        poseId = pose.poseId,
        poseName = pose.name,
        skeletonPath = verifiedPath,
    )
}

/** Prototype accent rotation for guide cards (pose-guide.html surface colors). */
internal fun guideCardAccentColor(index: Int): Color = when (index % 4) {
    0 -> AiPoseColors.Warning
    1 -> AiPoseColors.Primary
    2 -> AiPoseColors.AccentBlue
    else -> AiPoseColors.Success
}

/** Dismiss sign-in before resuming preparation so error/retry UI stays interactable. */
internal fun resumeGuestTryPosePreparation(
    selectedPose: CommunityPose?,
    dismissSignIn: () -> Unit,
): CommunityPose? {
    dismissSignIn()
    return selectedPose
}

internal suspend fun prepareSelectedPose(
    pose: CommunityPose,
    downloadBytes: suspend (String) -> ByteArray,
    onSuccess: (PreparedPoseReference) -> Unit,
    onActionState: (PoseGuidePickerActionState) -> Unit,
) {
    onActionState(PoseGuidePickerActionState.Preparing)
    try {
        val prepared = prepareCommunityPoseReference(pose, downloadBytes)
        onActionState(PoseGuidePickerActionState.Idle)
        onSuccess(prepared)
    } catch (e: Exception) {
        onActionState(
            PoseGuidePickerActionState.Error(
                e.message ?: "Could not prepare the pose image. Please try again.",
            ),
        )
    }
}

@Composable
fun PoseGuidePickerScreen(
    modifier: Modifier = Modifier,
    coordinator: PosesLibraryCoordinator = PoseServiceLocator.coordinator,
    apiService: PoseApiService = PoseServiceLocator.apiService,
    onBack: () -> Unit,
    onVerifiedSelection: (PreparedPoseReference) -> Unit,
) {
    val communityState by coordinator.communityState.collectAsState()
    val scope = rememberCoroutineScope()
    var selectedPose by remember { mutableStateOf<CommunityPose?>(null) }
    var actionState by remember { mutableStateOf<PoseGuidePickerActionState>(PoseGuidePickerActionState.Idle) }
    var showSignIn by remember { mutableStateOf(false) }
    val signInController = remember {
        SignInPromptController(platformGoogleSignInLauncher()) { intent ->
            if (intent == SignInIntent.TRY_POSE) {
                val pose = resumeGuestTryPosePreparation(selectedPose) { showSignIn = false }
                if (pose != null) {
                    scope.launch {
                        prepareSelectedPose(
                            pose = pose,
                            downloadBytes = { url -> apiService.downloadImageBytes(url) },
                            onSuccess = onVerifiedSelection,
                            onActionState = { actionState = it },
                        )
                    }
                }
            }
        }
    }

    LaunchedEffect(Unit) {
        if (communityState.items.isEmpty() && communityState.initialLoadState !is OperationState.Loading) {
            coordinator.loadCommunityInitial()
        }
    }

    fun onPoseSelected(pose: CommunityPose) {
        selectedPose = pose
        actionState = PoseGuidePickerActionState.Idle
        if (!hasValidStoredSession()) {
            signInController.show(SignInIntent.TRY_POSE)
            showSignIn = true
            return
        }
        scope.launch {
            prepareSelectedPose(
                pose = pose,
                downloadBytes = { url -> apiService.downloadImageBytes(url) },
                onSuccess = onVerifiedSelection,
                onActionState = { actionState = it },
            )
        }
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(AiPoseColors.Background)
            .statusBarsPadding()
            .navigationBarsPadding()
            .testTag(POSE_GUIDE_PICKER_TEST_TAG),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = Spacing.md, vertical = Spacing.sm),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
        ) {
            NeoBrutalismContainer(
                modifier = Modifier
                    .size(44.dp)
                    .testTag(POSE_GUIDE_PICKER_BACK_TEST_TAG)
                    .semantics { contentDescription = "Back to Camera" },
                shape = RoundedCornerShape(10.dp),
                backgroundColor = AiPoseColors.Surface,
                shadowColor = AiPoseColors.Foreground,
                shadowOffset = 3.dp,
                onClick = onBack,
            ) {
                Text("←", color = AiPoseColors.Foreground, style = AiPoseTypography.Control)
            }
            Text(
                text = "Choose a guide",
                style = AiPoseTypography.ScreenTitle,
                color = AiPoseColors.Foreground,
                modifier = Modifier.weight(1f),
            )
        }

        if (actionState is PoseGuidePickerActionState.Error) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = Spacing.md, vertical = Spacing.xs)
                    .background(AiPoseColors.Error.copy(alpha = 0.12f))
                    .padding(Spacing.sm)
                    .testTag("pose-guide-prepare-error"),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = (actionState as PoseGuidePickerActionState.Error).message,
                    style = AiPoseTypography.Caption,
                    color = AiPoseColors.Error,
                    modifier = Modifier.weight(1f),
                )
                PrimaryButton(
                    text = "Retry",
                    onClick = {
                        selectedPose?.let { onPoseSelected(it) }
                    },
                    modifier = Modifier
                        .size(width = 80.dp, height = 32.dp)
                        .testTag("pose-guide-prepare-retry"),
                )
            }
        }

        when {
            communityState.initialLoadState is OperationState.Loading && communityState.items.isEmpty() -> {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = AiPoseColors.Primary)
                }
            }
            communityState.initialLoadState is OperationState.Error && communityState.items.isEmpty() -> {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(Spacing.lg)
                        .testTag("pose-guide-initial-error"),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    Text("Failed to load guides", style = AiPoseTypography.Heading3, color = AiPoseColors.Error)
                    PrimaryButton(
                        text = "Retry",
                        onClick = { coordinator.loadCommunityInitial() },
                        modifier = Modifier.padding(top = Spacing.md).testTag("pose-guide-retry-initial"),
                    )
                }
            }
            communityState.items.isEmpty() -> {
                Box(
                    modifier = Modifier.fillMaxSize().testTag("pose-guide-empty"),
                    contentAlignment = Alignment.Center,
                ) {
                    Text("No guides available.", style = AiPoseTypography.Body, color = AiPoseColors.Subtext)
                }
            }
            else -> {
                val gridState = rememberLazyGridState()
                LazyVerticalGrid(
                    columns = GridCells.Fixed(2),
                    state = gridState,
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(horizontal = Spacing.md, vertical = Spacing.sm),
                    horizontalArrangement = Arrangement.spacedBy(Spacing.md),
                    verticalArrangement = Arrangement.spacedBy(Spacing.md),
                ) {
                    itemsIndexed(
                        communityState.items,
                        key = { index, pose -> communityPoseGridKey(pose, index) },
                    ) { index, pose ->
                        val isSelected = selectedPose?.poseId == pose.poseId
                        val isPreparing = isSelected && actionState is PoseGuidePickerActionState.Preparing
                        GuidePickerCard(
                            pose = pose,
                            index = index,
                            isSelected = isSelected,
                            isPreparing = isPreparing,
                            onClick = { if (!isPreparing) onPoseSelected(pose) },
                        )
                    }
                    if (communityState.hasMore) {
                        when (communityState.loadMoreState) {
                            is OperationState.Loading -> {
                                item(span = { GridItemSpan(2) }) {
                                    Box(
                                        modifier = Modifier.fillMaxWidth().padding(Spacing.md),
                                        contentAlignment = Alignment.Center,
                                    ) {
                                        CircularProgressIndicator(
                                            color = AiPoseColors.Subtext.copy(alpha = COMMUNITY_LOADING_ALPHA),
                                            modifier = Modifier.size(COMMUNITY_LOADING_SIZE.dp),
                                            strokeWidth = COMMUNITY_LOADING_STROKE.dp,
                                        )
                                    }
                                }
                            }
                            is OperationState.Error -> {
                                item(span = { GridItemSpan(2) }) {
                                    Column(
                                        modifier = Modifier.fillMaxWidth().padding(Spacing.md).testTag("pose-guide-load-more-error"),
                                        horizontalAlignment = Alignment.CenterHorizontally,
                                    ) {
                                        Text("Load more failed.", style = AiPoseTypography.Caption, color = AiPoseColors.Error)
                                        PrimaryButton(
                                            text = "Retry",
                                            onClick = { coordinator.loadMoreCommunity() },
                                            modifier = Modifier.padding(top = Spacing.xs).testTag("pose-guide-retry-load-more"),
                                        )
                                    }
                                }
                            }
                            else -> {
                                item(span = { GridItemSpan(2) }) {
                                    LaunchedEffect(communityState.items.size) {
                                        coordinator.loadMoreCommunity()
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

    SignInPrompt(
        controller = signInController,
        visible = showSignIn,
        onDismiss = { showSignIn = false },
    )
}

@Composable
private fun GuidePickerCard(
    pose: CommunityPose,
    index: Int,
    isSelected: Boolean,
    isPreparing: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val model = remember(pose.thumbnailUrl, pose.skeletonUrl) { resolveCommunityImageModel(pose) }
    var cellSizePx by remember { mutableStateOf<IntSize?>(null) }
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
    val cardShape = RoundedCornerShape(CornerRadius.md)

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(Spacing.xs),
    ) {
        NeoBrutalismContainer(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(1f)
                .clip(cardShape)
                .semantics { contentDescription = "Use ${pose.name} guide" }
                .testTag("pose-guide-card-${pose.poseId}"),
            shape = cardShape,
            backgroundColor = guideCardAccentColor(index),
            borderWidth = if (isSelected) 3.dp else 2.dp,
            shadowOffset = if (isSelected) 4.dp else 2.dp,
            onClick = onClick,
        ) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .onSizeChanged { cellSizePx = it }
                    .padding(Spacing.sm),
                contentAlignment = Alignment.Center,
            ) {
                when {
                    isPreparing -> CircularProgressIndicator(
                        color = AiPoseColors.Foreground,
                        modifier = Modifier.size(28.dp),
                    )
                    model == null -> Icon(
                        imageVector = Icons.Default.Image,
                        contentDescription = null,
                        tint = AiPoseColors.Foreground.copy(alpha = 0.7f),
                        modifier = Modifier.size(40.dp),
                    )
                    request != null -> SubcomposeAsyncImage(
                        model = request,
                        contentDescription = pose.name,
                        contentScale = poseThumbnailContentScale(),
                        modifier = Modifier.fillMaxSize().clip(cardShape),
                        loading = {
                            CircularProgressIndicator(
                                color = AiPoseColors.Foreground.copy(alpha = COMMUNITY_LOADING_ALPHA),
                                modifier = Modifier.size(COMMUNITY_LOADING_SIZE.dp),
                                strokeWidth = COMMUNITY_LOADING_STROKE.dp,
                            )
                        },
                        error = {
                            Icon(
                                imageVector = Icons.Default.Image,
                                contentDescription = null,
                                tint = AiPoseColors.Foreground.copy(alpha = 0.7f),
                                modifier = Modifier.size(40.dp),
                            )
                        },
                    )
                }
            }
        }
        Text(
            text = pose.name,
            style = AiPoseTypography.Control,
            color = AiPoseColors.Foreground,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(horizontal = 2.dp),
        )
    }
}
