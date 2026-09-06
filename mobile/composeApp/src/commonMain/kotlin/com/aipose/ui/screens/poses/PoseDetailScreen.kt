package com.aipose.ui.screens.poses

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bookmark
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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.foundation.shape.RoundedCornerShape
import coil3.compose.AsyncImage
import com.aipose.Pose
import com.aipose.auth.SignInIntent
import com.aipose.auth.hasValidStoredSession
import com.aipose.data.PreparedPoseReference
import com.aipose.data.PoseImageVerification
import com.aipose.data.PoseRepository
import com.aipose.data.PoseServiceLocator
import com.aipose.data.SavedPosesRepository
import com.aipose.data.remote.CommunityPose
import com.aipose.data.remote.PoseApiException
import com.aipose.data.remote.PoseApiService
import com.aipose.data.remote.isUnauthorized
import com.aipose.navigation.PoseDetailOrigin
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
import com.aipose.purchases.premiumTestBypassEnabled
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

/** Exact required copy for a removed/unpublished pose; never softened to "not found". */
const val REMOVED_POSE_COPY = "Pose này đã xoá hoặc đã ẩn."

/**
 * WI-04 confirmed Saved status. [isSaved] only flips after HTTP 200 (save) / 204
 * (unsave); [isPending] keeps the last confirmed visual during a mutation;
 * [unavailable] means the pose was removed while open (exact [REMOVED_POSE_COPY],
 * Try blocked, SavedEntry never deleted, mutation never reports success).
 */
data class SavedStatusState(
    val isSaved: Boolean = false,
    val isPending: Boolean = false,
    val error: String? = null,
    val unavailable: Boolean = false,
)

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
private fun UnavailableRemovedPanel(
    origin: PoseDetailOrigin,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(AiPoseColors.SurfaceVariant, RoundedCornerShape(CornerRadius.md))
            .padding(Spacing.lg)
            .testTag("detail-unavailable-removed")
            .semantics { contentDescription = REMOVED_POSE_COPY },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.sm),
    ) {
        Text(
            text = REMOVED_POSE_COPY,
            style = AiPoseTypography.Heading3,
            color = AiPoseColors.Foreground,
        )
        Text(
            text = "Pose này không còn khả dụng. Bạn không thể lưu hoặc thử pose này nữa.",
            style = AiPoseTypography.Body,
            color = AiPoseColors.Subtext,
        )
        PrimaryButton(
            text = if (origin == PoseDetailOrigin.SAVED) "Back to Saved" else "Back to Community",
            onClick = onBack,
            modifier = Modifier.fillMaxWidth().padding(top = Spacing.sm),
        )
    }
}

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
            modifier = Modifier
                .fillMaxWidth()
                .height(44.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier.size(44.dp),
                contentAlignment = Alignment.CenterStart
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
            }
            Text(
                text = heroName,
                style = AiPoseTypography.NavigationTitle,
                color = AiPoseColors.Foreground,
                textAlign = TextAlign.Center,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier
                    .weight(1f)
                    .padding(horizontal = Spacing.sm),
            )
            Box(
                modifier = Modifier.size(44.dp),
                contentAlignment = Alignment.CenterEnd
            ) {
                headerTrailing()
            }
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
    private val apiService: PoseApiService = PoseServiceLocator.apiService,
    private val savedRepository: SavedPosesRepository = PoseServiceLocator.savedPosesRepository,
    private val initialSaved: Boolean = false,
    private val origin: PoseDetailOrigin = PoseDetailOrigin.COMMUNITY,
    private val initialCommunityPose: CommunityPose? = null,
    viewModelScope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main),
) {
    private val _uiState = MutableStateFlow<PoseDetailUiState>(
        initialCommunityPose?.let { communityPose ->
            PoseDetailUiState.Success(
                name = communityPose.name,
                skeletonPath = communityPose.skeletonUrl,
                thumbnailPath = communityPose.thumbnailUrl,
                difficulty = communityPose.difficulty,
                author = null,
                isMine = false,
                communityPose = communityPose,
            )
        } ?: PoseDetailUiState.Loading
    )
    val uiState: StateFlow<PoseDetailUiState> = _uiState.asStateFlow()

    private val _actionState = MutableStateFlow<DetailActionState>(DetailActionState.Idle)
    val actionState: StateFlow<DetailActionState> = _actionState.asStateFlow()

    /** WI-04: confirmed Saved status + mutation state. `isSaved` only changes after HTTP 200/204. */
    private val _savedStatus = MutableStateFlow(SavedStatusState(isSaved = initialSaved))
    val savedStatus: StateFlow<SavedStatusState> = _savedStatus.asStateFlow()

    /** Single-use interrupted sign-in intent (Save/Try) awaiting a successful auth. */
    private val _signInIntent = MutableStateFlow<SignInIntent?>(null)
    val signInIntent: StateFlow<SignInIntent?> = _signInIntent.asStateFlow()

    /**
     * Session-expired signal (any backend 401 variant). Clears account-scoped state,
     * exposes the shared sign-in requirement, and is never degraded to a generic
     * inline error as the only response.
     */
    private val _signInRequired = MutableStateFlow(false)
    val signInRequired: StateFlow<Boolean> = _signInRequired.asStateFlow()

    private var pendingTrySuccess: ((PreparedPoseReference) -> Unit)? = null

    private val scope = viewModelScope

    fun isSignedIn(): Boolean = hasValidStoredSession()


    suspend fun load(forceRefresh: Boolean = false) {
        // ponytail: no deep-link/freshness consumer exists in this lane; reintroduce an explicit fetch only when that contract exists.
        if (initialCommunityPose != null && !forceRefresh) return
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
        }
    }

    /**
     * Prepares a verified typed reference for the selected pose and emits it
     * via [onSuccess] only when preparation succeeds (E4). On any unreadable
     * local asset or failed published download/decode, the view model stays
     * on detail and exposes a recoverable [DetailActionState.Error] so the user
     * can retry; it never navigates with a missing skeleton. A guest is gated:
     * the interrupted Try intent is retained single-use and resumed only after
     * a real sign-in success via [resumeSignInIntent].
     */
    suspend fun tryPose(onSuccess: (PreparedPoseReference) -> Unit) {
        val state = _uiState.value
        if (state !is PoseDetailUiState.Success) return
        if (!isSignedIn() && state.communityPose != null) {
            pendingTrySuccess = onSuccess
            _signInIntent.value = SignInIntent.TRY_POSE
            return
        }
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

    // ── WI-04: confirmed-only Save/Unsave ────────────────────────────────────────

    /**
     * Guest gate + confirmed mutation. A guest only opens the shared sign-in prompt
     * (no request); a signed-in user PUT/DELETEs and the confirmed state flips only
     * after HTTP 200 / 204. Pending keeps the last confirmed visual; failures keep
     * the confirmed state with an inline retryable error; 404 while open resolves to
     * the unavailable/removed panel and never reports success.
     */
    fun toggleSave() {
        val state = _uiState.value
        if (state !is PoseDetailUiState.Success || state.communityPose == null) return
        if (_savedStatus.value.isPending) return
        if (!isSignedIn()) {
            _signInIntent.value = SignInIntent.SAVE_POSE
            return
        }
        val targetSaved = !_savedStatus.value.isSaved
        _savedStatus.value = _savedStatus.value.copy(isPending = true, error = null)
        scope.launch {
            try {
                if (targetSaved) {
                    savedRepository.savePose(poseId)
                    // 200 confirmed
                    _savedStatus.value = SavedStatusState(isSaved = true, isPending = false)
                } else {
                    savedRepository.unsavePose(poseId)
                    // 204 confirmed
                    _savedStatus.value = SavedStatusState(isSaved = false, isPending = false)
                }
            } catch (e: PoseApiException) {
                if (e.code == "NOT_FOUND" || e.code == "404") {
                    // Removal while open: never success; stop mutation; show unavailable.
                    _savedStatus.value = SavedStatusState(isSaved = _savedStatus.value.isSaved, isPending = false, unavailable = true, error = REMOVED_POSE_COPY)
                } else if (e.isUnauthorized()) {
                    // One 401 policy: any variant surfaces the existing sign-in flow with
                    // the interrupted action retained (single-use), never a generic inline
                    // error as the only response; confirmed state is preserved.
                    _savedStatus.value = _savedStatus.value.copy(isPending = false, error = null)
                    _signInIntent.value = SignInIntent.SAVE_POSE
                } else {
                    _savedStatus.value = _savedStatus.value.copy(isPending = false, error = e.message ?: "Could not update Saved pose.")
                }
            } catch (e: Exception) {
                _savedStatus.value = _savedStatus.value.copy(isPending = false, error = e.message ?: "Could not update Saved pose.")
            }
        }
    }

    /** Clears the single-use intent on cancellation/terminal failure (never replays). */
    fun clearSignInIntent() {
        _signInIntent.value = null
        pendingTrySuccess = null
    }

    /**
     * Resumes the interrupted intent only after real auth success (single-use).
     * Save: re-run the confirmed mutation. Try: prepare the already-projected
     * published detail through the existing image verification flow.
     */
    fun resumeSignInIntent(onTrySuccess: (PreparedPoseReference) -> Unit) {
        val intent = _signInIntent.value ?: return
        when (intent) {
            SignInIntent.SAVE_POSE -> {
                _signInIntent.value = null
                toggleSave()
            }
            SignInIntent.TRY_POSE -> {
                val pending = pendingTrySuccess ?: onTrySuccess
                _signInIntent.value = null
                pendingTrySuccess = null
                scope.launch {
                    tryPose(onSuccess = pending)
                }
            }
            SignInIntent.OPEN_ACCOUNT -> _signInIntent.value = null // handled by Account navigation
            SignInIntent.OPEN_SAVED -> _signInIntent.value = null // handled by navigation, not detail
        }
    }

    fun clearSavedError() {
        _savedStatus.value = _savedStatus.value.copy(error = null)
    }

    /**
     * Clears the session-expired signal after a real sign-in success. Used when a
     * 401 fired during load/toggle (no pending interrupted Save intent) so the UI
     * does not auto-mutate; the detail then reloads with the fresh session.
     */
    fun clearSignInRequired() {
        _signInRequired.value = false
    }

    /** Reloads the detail with the now-valid session after a 401 recovery. */
    fun reloadAfterSignIn() {
        clearSignInRequired()
        scope.launch { load(forceRefresh = true) }
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
    origin: PoseDetailOrigin = PoseDetailOrigin.COMMUNITY,
    onSignInRequired: (SignInIntent) -> Unit = {},
    onConfirmedUnsave: (() -> Unit)? = null,
    purchaseGateway: PurchaseGateway = PurchaseGatewayProvider.current,
    modifier: Modifier = Modifier
) {
    val uiState by viewModel.uiState.collectAsState()
    val actionState by viewModel.actionState.collectAsState()
    val savedStatus by viewModel.savedStatus.collectAsState()
    val signInIntent by viewModel.signInIntent.collectAsState()
    val signInRequired by viewModel.signInRequired.collectAsState()
      var showDeleteDialog by remember { mutableStateOf(false) }
      var showPaywall by remember { mutableStateOf(false) }
    val coroutineScope = rememberCoroutineScope()

    // Surface a single-use sign-in requirement (Save/Try) to the navigator layer.
    LaunchedEffect(signInIntent) {
        signInIntent?.let { onSignInRequired(it) }
    }

    // One 401 policy: any expired-session signal on load/toggle opens the shared
    // sign-in requirement (never an inline generic error as the only response).
    LaunchedEffect(signInRequired) {
        if (signInRequired) onSignInRequired(SignInIntent.SAVE_POSE)
    }

    // After a confirmed 204 unsave, let the origin SAVED list drop the entry —
    // only after the server response, never optimistically.
    var wasPending by remember { mutableStateOf(false) }
    LaunchedEffect(savedStatus) {
        val completedUnsave = wasPending && !savedStatus.isPending && !savedStatus.isSaved && !savedStatus.unavailable
        if (completedUnsave) onConfirmedUnsave?.invoke()
        wasPending = savedStatus.isPending
    }

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
                                verticalArrangement = Arrangement.spacedBy(Spacing.md)
                            ) {
                                Column(
                                    modifier = Modifier.fillMaxWidth(),
                                    verticalArrangement = Arrangement.spacedBy(Spacing.xs)
                                ) {
                                    val sourceText = when {
                                        s.pose != null -> "My Poses"
                                        origin == PoseDetailOrigin.SAVED -> "Saved"
                                        else -> "Community"
                                    }
                                    val sourceBg = when {
                                        s.pose != null -> AiPoseColors.Success
                                        else -> AiPoseColors.AccentBlue
                                    }
                                    Box(
                                        modifier = Modifier
                                            .background(sourceBg, RoundedCornerShape(CornerRadius.sm))
                                            .border(1.dp, AiPoseColors.Foreground, RoundedCornerShape(CornerRadius.sm))
                                            .padding(horizontal = Spacing.sm, vertical = 4.dp),
                                    ) {
                                        Text(
                                            text = sourceText,
                                            style = AiPoseTypography.MetaLabel,
                                            color = AiPoseColors.Foreground,
                                        )
                                    }

                                    Text(
                                        text = s.name,
                                        style = AiPoseTypography.Heading3,
                                        color = AiPoseColors.Foreground
                                    )

                                    val contextText = when {
                                        s.pose != null -> "Personal"
                                        origin == PoseDetailOrigin.SAVED -> "Saved · Community"
                                        else -> "Published · Community"
                                    }
                                    Text(
                                        text = contextText,
                                        style = AiPoseTypography.Caption,
                                        color = AiPoseColors.Subtext
                                    )
                                }

                                val metadataItems = buildList {
                                    s.author?.takeIf { it.isNotBlank() }?.let { add("Author: $it") }
                                    s.difficulty?.takeIf { it.isNotBlank() }?.let { add("Difficulty: $it") }
                                    if (s.pose != null && !s.pose.createdAt.isNullOrBlank()) {
                                        add("Created: ${s.pose.createdAt}")
                                    }
                                }
                                if (metadataItems.isNotEmpty()) {
                                    Row(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .semantics { contentDescription = "Pose metadata" },
                                        horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                                        verticalAlignment = Alignment.CenterVertically,
                                    ) {
                                        for (item in metadataItems) {
                                            Box(
                                                modifier = Modifier
                                                    .background(AiPoseColors.Surface, RoundedCornerShape(CornerRadius.full))
                                                    .border(1.dp, AiPoseColors.Foreground, RoundedCornerShape(CornerRadius.full))
                                                    .padding(horizontal = Spacing.sm, vertical = 4.dp),
                                            ) {
                                                Text(
                                                    text = item,
                                                    style = AiPoseTypography.MetaLabel,
                                                    color = AiPoseColors.Foreground,
                                                )
                                            }
                                        }
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

                                // WI-04 confirmed Saved status + inline retryable mutation error.
                                if (savedStatus.error != null && !savedStatus.unavailable) {
                                    Text(
                                        text = savedStatus.error!!,
                                        style = AiPoseTypography.Caption,
                                        color = AiPoseColors.Error,
                                        modifier = Modifier.padding(vertical = Spacing.xs)
                                    )
                                }

                                val isCommunity = s.communityPose != null
                                val savedControlEnabled = isCommunity &&
                                    !savedStatus.isPending &&
                                    !savedStatus.unavailable &&
                                    actionState !is DetailActionState.Preparing
                                if (savedStatus.unavailable) {
                                    // Removal/unavailable: visibly render the exact frozen copy,
                                    // block Try and mutation, never report success.
                                    UnavailableRemovedPanel(
                                        origin = origin,
                                        onBack = onBack,
                                        modifier = Modifier.fillMaxWidth(),
                                    )
                                } else {
                                    // Offline/stale: Save/Unsave/Try gated with a clear reconnect action.
                                    if (savedStatus.error != null && !savedStatus.unavailable) {
                                        PrimaryButton(
                                            text = "Reconnect & Retry",
                                            onClick = {
                                                viewModel.clearSavedError()
                                                viewModel.toggleSave()
                                            },
                                            modifier = Modifier.fillMaxWidth().padding(bottom = Spacing.sm),
                                        )
                                    }

                                    Row(
                                        modifier = Modifier.fillMaxWidth(),
                                        horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                                        verticalAlignment = Alignment.CenterVertically,
                                    ) {
                                        PrimaryButton(
                                            text = "Try Pose",
                                            enabled = !savedStatus.unavailable,
                                            onClick = {
                                                if (premiumTestBypassEnabled || decidePaidAccess(purchaseGateway.snapshot.value).allowAction) {
                                                    coroutineScope.launch {
                                                        if (savedStatus.unavailable) return@launch // Try blocked on removed pose
                                                        viewModel.tryPose(onSuccess = onUseWithCamera)
                                                    }
                                                } else showPaywall = true
                                            },
                                            modifier = if (isCommunity) Modifier.weight(1f) else Modifier.fillMaxWidth()
                                        )

                                        if (isCommunity) {
                                            NeoBrutalismContainer(
                                                modifier = Modifier
                                                    .height(48.dp)
                                                    .testTag("detail-save-toggle")
                                                    .semantics {
                                                        contentDescription = if (savedStatus.isSaved) "Remove pose from Saved" else "Save pose"
                                                    },
                                                shape = RoundedCornerShape(CornerRadius.sm),
                                                backgroundColor = if (savedStatus.isSaved) AiPoseColors.Primary else AiPoseColors.Surface,
                                                shadowOffset = 2.dp,
                                                borderWidth = 2.dp,
                                                onClick = {
                                                    if (savedControlEnabled) {
                                                        viewModel.toggleSave()
                                                    }
                                                },
                                            ) {
                                                Row(
                                                    modifier = Modifier
                                                        .height(48.dp)
                                                        .padding(horizontal = Spacing.md),
                                                    horizontalArrangement = Arrangement.spacedBy(Spacing.xs),
                                                    verticalAlignment = Alignment.CenterVertically,
                                                ) {
                                                    if (savedStatus.isPending) {
                                                        CircularProgressIndicator(
                                                            color = if (savedStatus.isSaved) AiPoseColors.Foreground else AiPoseColors.Primary,
                                                            modifier = Modifier.size(18.dp),
                                                            strokeWidth = 2.dp,
                                                        )
                                                    } else {
                                                        Icon(
                                                            imageVector = Icons.Default.Bookmark,
                                                            contentDescription = null,
                                                            tint = AiPoseColors.Foreground,
                                                            modifier = Modifier.size(18.dp),
                                                        )
                                                    }
                                                    Text(
                                                        text = if (savedStatus.isSaved) "Saved" else "Save",
                                                        style = AiPoseTypography.Control,
                                                        color = AiPoseColors.Foreground,
                                                    )
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        else -> {
                            // Preview-first Loading body below the persistent hero.
                            Column(
                                modifier = Modifier.fillMaxWidth(),
                                verticalArrangement = Arrangement.spacedBy(Spacing.xs)
                            ) {
                                Text(
                                    text = preview.name,
                                    style = AiPoseTypography.Heading3,
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
                        text = REMOVED_POSE_COPY,
                        style = AiPoseTypography.Heading3,
                        color = AiPoseColors.Foreground
                    )
                    Text(
                        text = "Pose này không còn khả dụng trong danh sách Saved.",
                        style = AiPoseTypography.Body,
                        color = AiPoseColors.Subtext,
                        modifier = Modifier.padding(top = Spacing.sm, bottom = Spacing.lg)
                    )
                    PrimaryButton(
                        onClick = onBack,
                        text = if (origin == PoseDetailOrigin.SAVED) "Back to Saved" else "Back to Community"
                    )
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
                        onClick = { coroutineScope.launch { viewModel.load(forceRefresh = true) } },
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
