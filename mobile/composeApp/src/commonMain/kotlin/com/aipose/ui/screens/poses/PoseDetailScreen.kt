package com.aipose.ui.screens.poses

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.ui.unit.dp
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Image
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.foundation.shape.RoundedCornerShape
import coil3.compose.AsyncImage
import com.aipose.Pose
import com.aipose.data.PreparedPoseReference
import com.aipose.data.PoseImageVerification
import com.aipose.data.PoseRepository
import com.aipose.data.PoseServiceLocator
import com.aipose.data.remote.CommunityPose
import com.aipose.data.remote.PoseApiException
import com.aipose.data.remote.PoseApiService
import com.aipose.ui.components.NeoBrutalismContainer
import com.aipose.navigation.MatchedImageDestination
import com.aipose.navigation.destinationChromeVisible
import com.aipose.ui.components.PrimaryButton
import com.aipose.ui.theme.AiPoseColors
import com.aipose.ui.theme.AiPoseTypography
import com.aipose.ui.theme.Spacing
import com.aipose.purchases.PaywallScreen
import com.aipose.purchases.PurchaseGateway
import com.aipose.purchases.UnconfiguredPurchaseGateway
import com.aipose.purchases.PurchaseGatewayProvider
import com.aipose.purchases.decidePaidAccess
import androidx.compose.ui.graphics.Color
import com.aipose.ui.theme.CornerRadius
import com.aipose.data.resolveImagePath
import io.ktor.client.call.body
import io.ktor.client.request.get
import io.ktor.util.decodeBase64Bytes
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import org.jetbrains.compose.resources.painterResource
import ai_pose.composeapp.generated.resources.Res
import ai_pose.composeapp.generated.resources.ic_chevron_left

sealed interface PoseDetailUiState {
    data object Loading : PoseDetailUiState
    data object NotFound : PoseDetailUiState
    data class Error(val message: String) : PoseDetailUiState
    data class Success(
        val name: String,
        val skeletonPath: String,
        val thumbnailPath: String?,
        val difficulty: String?,
        val author: String?,
        val isMine: Boolean,
        val pose: Pose? = null,
        val communityPose: CommunityPose? = null
    ) : PoseDetailUiState
}

sealed interface DetailActionState {
    data object Idle : DetailActionState
    data object Preparing : DetailActionState
    data class Error(val message: String) : DetailActionState
    data object Deleting : DetailActionState
}

internal fun posePreviewModel(state: PoseDetailUiState.Success): String? {
    val preview = state.thumbnailPath
    if (!preview.isNullOrBlank()) {
        return if (state.pose != null) resolveImagePath(preview) ?: preview else preview
    }
    val skeleton = state.skeletonPath
    if (skeleton.isNotBlank()) {
        return if (state.pose != null) resolveImagePath(skeleton) ?: skeleton else skeleton
    }
    return null
}

/**
 * Canonical hero image model for the detail state (Pose). While still [Loading]
 * the hero composes from the navigation [PosePreview.imageModel] (preview-first);
 * once enriched ([PoseDetailUiState.Success]) it uses [posePreviewModel]. Both are
 * the SAME canonical asset (the card's resolved thumbnail / remote URL), so the hero
 * model — and therefore the Coil cache identity — is never replaced or flashed across
 * Loading -> Success. The transition key `pose:<poseId>` and hero bounds stay stable too.
 */
internal fun poseHeroModel(state: PoseDetailUiState, preview: PosePreview): String? = when (state) {
    is PoseDetailUiState.Success -> posePreviewModel(state)
    else -> preview.imageModel
}

/**
 * Shared detail hero. Coil owns all decode/cache for the detail AND the flyer:
 * it renders the stable preview/[posePreviewModel] [coil3.compose.AsyncImage] directly,
 * so there is never a second full-resolution bitmap decoded by hand and no local
 * staging path. The single [MatchedImageDestination] wrapper measures the hero bounds
 * for the forward flight (even when [model] is null) and hides it while a flight is
 * active. Chrome/background and readiness are gated by [destinationChromeVisible] in
 * [PoseDetailHeroRegion] so no blank/spinner/stroke frame is exposed behind/after the
 * flyer — the unified Pose/Gallery readiness rule (see [com.aipose.navigation.destinationChromeVisible]).
 */
@Composable
private fun PoseDetailHero(
    poseId: String,
    name: String,
    model: String?,
    onImageReady: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    var failed by remember(model) { mutableStateOf(false) }
    MatchedImageDestination(
        key = "pose:$poseId",
        imageModel = model,
        cornerRadius = CornerRadius.md,
        modifier = modifier.fillMaxSize(),
    ) {
        if (model != null && !failed) {
            // Coil-driven root: no local file staging, no hand-decoded bitmap, no
            // second decode. Readiness (Coil-painted media) drives the chrome/border
            // gate so no empty framed box is ever shown.
            AsyncImage(
                model = model,
                contentDescription = name,
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Crop,
                onLoading = { onImageReady(false) },
                onError = { failed = true; onImageReady(false) },
                onSuccess = { onImageReady(true) },
            )
        } else {
            Icon(
                imageVector = Icons.Default.Image,
                contentDescription = null,
                modifier = Modifier.size(64.dp),
                tint = AiPoseColors.Subtext
            )
        }
    }
}

/**
 * Persistent hero container. Composed OUTSIDE the state `when` (at the same slot
 * across Loading -> Success) so the hero wrapper — and its measured window bounds —
 * is never recreated or moved mid-flight. Its chrome (Surface background + rounded
 * shape) is gated on [destinationChromeVisible], the unified Pose/Gallery readiness
 * rule, so no empty/blank/spinner/stroke frame is exposed behind/after the flyer.
 */
@Composable
private fun PoseDetailHeroRegion(
    poseId: String,
    name: String,
    model: String?,
    modifier: Modifier = Modifier,
) {
    var imageReady by remember(poseId) { mutableStateOf(false) }
    val ready = destinationChromeVisible("pose:$poseId", imageReady)
    Box(
        modifier = modifier.then(
            if (ready) {
                Modifier.background(AiPoseColors.Surface, RoundedCornerShape(CornerRadius.md))
            } else {
                Modifier
            }
        ),
        contentAlignment = Alignment.Center
    ) {
        PoseDetailHero(
            poseId = poseId,
            name = name,
            model = model,
            onImageReady = { imageReady = it },
        )
    }
}

/**
 * Shared Loading/Success detail scaffold with a structurally-stable hero. The hero
 * container ([PoseDetailHeroRegion]) lives at a fixed slot in this Column, so the
 * Pose hero wrapper survives Loading -> Success unchanged (same key, model, bounds).
 * Only the header-trailing actions and the body below the hero are state-specific.
 */
@Composable
private fun PoseDetailScaffold(
    poseId: String,
    heroName: String,
    heroModel: String?,
    onBack: () -> Unit,
    headerTrailing: @Composable () -> Unit = {},
    body: @Composable () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .statusBarsPadding()
            .navigationBarsPadding()
            .padding(Spacing.lg),
        verticalArrangement = Arrangement.spacedBy(Spacing.lg)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            NeoBrutalismContainer(
                modifier = Modifier.size(44.dp),
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
            headerTrailing()
        }

        PoseDetailHeroRegion(
            poseId = poseId,
            name = heroName,
            model = heroModel,
            modifier = Modifier.fillMaxWidth().weight(1f),
        )

        body()
    }
}

class PoseDetailViewModel(
    private val poseId: String,
    private val repository: PoseRepository = PoseServiceLocator.repository,
    private val apiService: PoseApiService = PoseServiceLocator.apiService
) {
    private val _uiState = MutableStateFlow<PoseDetailUiState>(PoseDetailUiState.Loading)
    val uiState: StateFlow<PoseDetailUiState> = _uiState.asStateFlow()

    private val _actionState = MutableStateFlow<DetailActionState>(DetailActionState.Idle)
    val actionState: StateFlow<DetailActionState> = _actionState.asStateFlow()

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)


    suspend fun load() {
        repository.getPoseById(poseId).collectLatest { pose ->
            if (pose != null) {
                _uiState.value = PoseDetailUiState.Success(
                    name = pose.name,
                    skeletonPath = pose.skeletonPath,
                    thumbnailPath = pose.thumbnailPath,
                    difficulty = pose.difficulty,
                    author = pose.ownerAccountId,
                    isMine = pose.status == "local",
                    pose = pose
                )
                return@collectLatest
            }
            try {
                val communityPose = apiService.getCommunityPoseDetail(poseId)
                _uiState.value = PoseDetailUiState.Success(
                    name = communityPose.name,
                    skeletonPath = communityPose.skeletonUrl,
                    thumbnailPath = communityPose.thumbnailUrl,
                    difficulty = communityPose.difficulty,
                    author = null,
                    isMine = false,
                    communityPose = communityPose
                )
            } catch (e: PoseApiException) {
                _uiState.value = if (e.code == "NOT_FOUND" || e.code == "404") {
                    PoseDetailUiState.NotFound
                } else {
                    PoseDetailUiState.Error(e.message ?: "Failed to load pose")
                }
            } catch (e: Exception) {
                _uiState.value = PoseDetailUiState.Error(e.message ?: "Failed to load pose")
            }
        }
    }

    /**
     * Prepares a verified typed reference for the selected pose and emits it
     * via [onSuccess] only when preparation succeeds (E4). On any unreadable
     * local asset or failed published download/decode, the view model stays
     * on detail and exposes a recoverable [DetailActionState.Error] so the user
     * can retry; it never navigates with a missing skeleton.
     */
    suspend fun tryPose(onSuccess: (PreparedPoseReference) -> Unit) {
        val state = _uiState.value
        if (state !is PoseDetailUiState.Success) return
        _actionState.value = DetailActionState.Preparing
        try {
            val prepared = prepareReference(state)
            _actionState.value = DetailActionState.Idle
            onSuccess(prepared)
        } catch (e: Exception) {
            _actionState.value = DetailActionState.Error(
                e.message ?: "Could not prepare the pose image. Please try again."
            )
        }
    }

    private suspend fun prepareReference(state: PoseDetailUiState.Success): PreparedPoseReference {
        val skeletonPath = state.pose?.skeletonPath ?: state.communityPose?.skeletonUrl ?: state.skeletonPath
        if (skeletonPath.isBlank()) throw IllegalStateException("This pose has no skeleton to prepare.")
        val verifiedSkeletonPath = if (skeletonPath.startsWith("data:")) {
            val bytes = PoseImageVerification.decodeDataUriPayload(skeletonPath)
                ?: throw IllegalStateException("The skeleton image could not be read.")
            if (!PoseImageVerification.isValidImage(bytes)) {
                throw IllegalStateException("The skeleton image is not supported.")
            }
            skeletonPath
        } else if (state.pose != null) {
            resolveImagePath(skeletonPath)
                ?: throw IllegalStateException("The skeleton file could not be found.")
        } else {
            val bytes = apiService.downloadImageBytes(skeletonPath)
            val mimeType = PoseImageVerification.detectImageMimeType(bytes)
                ?: throw IllegalStateException("The skeleton image could not be decoded.")
            PoseImageVerification.toDataUri(bytes, mimeType)
        }
        return PreparedPoseReference(poseId = poseId, poseName = state.name, skeletonPath = verifiedSkeletonPath)
    }

    private val deleteMutex = Mutex()

    /**
     * Deletes the local pose locally. Published references never delete and
     * no server request is made (FR-006/BR-001). A second confirm while a
     * delete is already in flight is ignored: it cannot start another delete.
     */
    suspend fun delete(): Boolean {
        val state = _uiState.value
        if (state !is PoseDetailUiState.Success || state.pose == null) return false
        if (!deleteMutex.tryLock()) return false // double-confirm/double-delete guard
        _actionState.value = DetailActionState.Deleting
        return try {
            repository.deletePose(poseId)
            _actionState.value = DetailActionState.Idle
            true
        } catch (e: Exception) {
            _actionState.value = DetailActionState.Error(e.message ?: "Deletion failed.")
            false
        } finally {
            deleteMutex.unlock()
        }
    }

    fun clearActionError() {
        _actionState.value = DetailActionState.Idle
    }
}

@Composable
fun PoseDetailScreen(
    poseId: String,
    preview: PosePreview,
    viewModel: PoseDetailViewModel,
    onUseWithCamera: (PreparedPoseReference) -> Unit,
    onBack: () -> Unit,
    purchaseGateway: PurchaseGateway = PurchaseGatewayProvider.current,
    modifier: Modifier = Modifier
) {
    val uiState by viewModel.uiState.collectAsState()
    val actionState by viewModel.actionState.collectAsState()
      var showDeleteDialog by remember { mutableStateOf(false) }
      var showPaywall by remember { mutableStateOf(false) }
    val coroutineScope = rememberCoroutineScope()

    LaunchedEffect(viewModel) {
        viewModel.load()
    }

    Box(modifier = modifier.fillMaxSize().background(AiPoseColors.Background)) {
        // The detail body scaffold (header + persistent hero + body) is composed
        // OUTSIDE the state `when` so the hero wrapper/key/model/bounds survive
        // Loading -> Success unchanged (no recreate, no target movement mid-flight).
        // Only for Loading-with-preview (preview-first) and enriched Success.
        val showDetailBody = when (val s = uiState) {
            is PoseDetailUiState.Success -> true
            PoseDetailUiState.Loading -> preview.imageModel != null
            else -> false
        }
        if (showDetailBody) {
            val heroName = when (val s = uiState) {
                is PoseDetailUiState.Success -> s.name
                else -> preview.name
            }
            val successState = uiState as? PoseDetailUiState.Success
            PoseDetailScaffold(
                poseId = poseId,
                heroName = heroName,
                heroModel = poseHeroModel(uiState, preview),
                onBack = onBack,
                headerTrailing = {
                    if (successState?.isMine == true) {
                        NeoBrutalismContainer(
                            modifier = Modifier.size(44.dp),
                            shape = RoundedCornerShape(10.dp),
                            backgroundColor = AiPoseColors.Background,
                            shadowOffset = 2.dp,
                            borderWidth = 2.dp,
                            onClick = {
                                // Do not open the delete dialog while a delete is in flight.
                                if (actionState !is DetailActionState.Deleting) {
                                    showDeleteDialog = true
                                }
                            }
                        ) {
                            Icon(
                                imageVector = Icons.Default.Delete,
                                contentDescription = "Delete pose",
                                tint = AiPoseColors.Foreground,
                                modifier = Modifier.size(16.dp)
                            )
                        }
                    }
                },
                body = {
                    when (val s = uiState) {
                        is PoseDetailUiState.Success -> {
                            Column(
                                modifier = Modifier.fillMaxWidth(),
                                verticalArrangement = Arrangement.spacedBy(Spacing.xs)
                            ) {
                                Text(
                                    text = s.name,
                                    style = AiPoseTypography.Heading2,
                                    color = AiPoseColors.Foreground
                                )

                                if (s.difficulty != null) {
                                    Text(
                                        text = "Difficulty: ${s.difficulty}",
                                        style = AiPoseTypography.BodyBold,
                                        color = AiPoseColors.Primary
                                    )
                                }
                                if (s.author != null) {
                                    Text(
                                        text = "Author: ${s.author}",
                                        style = AiPoseTypography.Body,
                                        color = AiPoseColors.Subtext
                                    )
                                }
                                if (s.pose != null) {
                                    Text(
                                        text = "Created: ${s.pose.createdAt}",
                                        style = AiPoseTypography.Caption,
                                        color = AiPoseColors.Subtext
                                    )
                                }
                            }

                            if (actionState is DetailActionState.Error) {
                                Text(
                                    text = (actionState as DetailActionState.Error).message,
                                    style = AiPoseTypography.Caption,
                                    color = AiPoseColors.Error,
                                    modifier = Modifier.padding(vertical = Spacing.xs)
                                )
                            }

                            PrimaryButton(
                                text = "Try Pose",
                                  onClick = {
                                      if (decidePaidAccess(purchaseGateway.snapshot.value).allowAction) {
                                          coroutineScope.launch { viewModel.tryPose(onSuccess = onUseWithCamera) }
                                      } else showPaywall = true
                                  },
                                modifier = Modifier.fillMaxWidth()
                            )
                        }
                        else -> {
                            // Preview-first Loading body below the persistent hero.
                            Column(
                                modifier = Modifier.fillMaxWidth(),
                                verticalArrangement = Arrangement.spacedBy(Spacing.xs)
                            ) {
                                Text(
                                    text = preview.name,
                                    style = AiPoseTypography.Heading2,
                                    color = AiPoseColors.Foreground
                                )
                                Text(
                                    text = "Loading details…",
                                    style = AiPoseTypography.Body,
                                    color = AiPoseColors.Subtext
                                )
                            }
                        }
                    }
                }
            )
        }

        when (val s = uiState) {
            PoseDetailUiState.Loading -> {
                // No navigation preview model (blank/error card, deep link): the
                // standalone initial-load spinner remains (not a transition frame).
                if (preview.imageModel == null) {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = AiPoseColors.Primary)
                    }
                }
            }

            PoseDetailUiState.NotFound -> {
                Column(
                    modifier = Modifier.fillMaxSize().padding(Spacing.lg),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center
                ) {
                    Text(
                        text = "Pose not found",
                        style = AiPoseTypography.Heading3,
                        color = AiPoseColors.Foreground
                    )
                    Text(
                        text = "The requested pose record does not exist or has been deleted.",
                        style = AiPoseTypography.Body,
                        color = AiPoseColors.Subtext,
                        modifier = Modifier.padding(top = Spacing.sm, bottom = Spacing.lg)
                    )
                    PrimaryButton(onClick = onBack, text = "Go back")
                }
            }

            is PoseDetailUiState.Error -> {
                Column(
                    modifier = Modifier.fillMaxSize().padding(Spacing.lg),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center
                ) {
                    Text(
                        text = "Failed to load detail",
                        style = AiPoseTypography.Heading3,
                        color = AiPoseColors.Error
                    )
                    Text(
                        text = s.message,
                        style = AiPoseTypography.Body,
                        color = AiPoseColors.Subtext,
                        modifier = Modifier.padding(top = Spacing.sm, bottom = Spacing.lg)
                    )
                    PrimaryButton(
                        text = "Retry",
                        onClick = { coroutineScope.launch { viewModel.load() } },
                        modifier = Modifier.fillMaxWidth()
                    )
                    PrimaryButton(
                        text = "Go back",
                        onClick = onBack,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            }

            is PoseDetailUiState.Success -> Unit
        }

          if (showDeleteDialog) {
            AlertDialog(
                onDismissRequest = { showDeleteDialog = false },
                title = { Text("Delete pose?") },
                text = { Text("This will permanently remove ${(uiState as? PoseDetailUiState.Success)?.name ?: ""} from your library.") },
                confirmButton = {
                    TextButton(
                        onClick = {
                            showDeleteDialog = false
                            coroutineScope.launch {
                                val success = viewModel.delete()
                                if (success) {
                                    onBack()
          }

                            }
                        }
                    ) {
                        Text("Delete")
                    }
                },
                dismissButton = {
                    TextButton(onClick = { showDeleteDialog = false }) {
                        Text("Cancel")
                    }
                }
            )
        }

        // Overlay spinner for preparing or deleting state
        if (actionState is DetailActionState.Preparing || actionState is DetailActionState.Deleting) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.5f)),
                contentAlignment = Alignment.Center
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    CircularProgressIndicator(color = AiPoseColors.Primary)
                    Text(
                        text = if (actionState is DetailActionState.Preparing) "Preparing reference image..." else "Deleting pose...",
                        style = AiPoseTypography.Caption,
                        color = Color.White,
                        modifier = Modifier.padding(top = Spacing.sm)
                    )
                }
            }
        }
        if (showPaywall) {
            PaywallScreen(
                gateway = purchaseGateway,
                onDismiss = { showPaywall = false },
                modifier = Modifier.fillMaxSize(),
            )
        }
    }
}
