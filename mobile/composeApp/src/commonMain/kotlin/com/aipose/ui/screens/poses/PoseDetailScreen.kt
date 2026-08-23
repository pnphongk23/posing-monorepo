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
import com.aipose.ui.components.PrimaryButton
import com.aipose.ui.theme.AiPoseColors
import com.aipose.ui.theme.AiPoseTypography
import com.aipose.ui.theme.Spacing
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
    viewModel: PoseDetailViewModel,
    onUseWithCamera: (PreparedPoseReference) -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val uiState by viewModel.uiState.collectAsState()
    val actionState by viewModel.actionState.collectAsState()
    var showDeleteDialog by remember { mutableStateOf(false) }
    val coroutineScope = rememberCoroutineScope()

    LaunchedEffect(viewModel) {
        viewModel.load()
    }

    Box(modifier = modifier.fillMaxSize().background(AiPoseColors.Background)) {
        when (val state = uiState) {
            PoseDetailUiState.Loading -> {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = AiPoseColors.Primary)
                }
            }

            PoseDetailUiState.NotFound -> {
                Column(
                    modifier = Modifier.fillMaxSize().padding(Spacing.lg),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center
                ) {
                    Text(
                        text = "POSE NOT FOUND",
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
                        text = "FAILED TO LOAD DETAIL",
                        style = AiPoseTypography.Heading3,
                        color = AiPoseColors.Error
                    )
                    Text(
                        text = state.message,
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

            is PoseDetailUiState.Success -> {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(Spacing.lg),
                    verticalArrangement = Arrangement.spacedBy(Spacing.lg)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        NeoBrutalismContainer(
                            modifier = Modifier.size(32.dp),
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

                        if (state.isMine) {
                            NeoBrutalismContainer(
                                modifier = Modifier.size(32.dp),
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
                    }

                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .weight(1f)
                            .background(AiPoseColors.Surface, RoundedCornerShape(CornerRadius.md)),
                        contentAlignment = Alignment.Center
                    ) {
                        if (state.skeletonPath.isNotBlank()) {
                            AsyncImage(
                                model = state.skeletonPath,
                                contentDescription = state.name,
                                modifier = Modifier.fillMaxSize(),
                                contentScale = ContentScale.Fit
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

                    Column(
                        modifier = Modifier.fillMaxWidth(),
                        verticalArrangement = Arrangement.spacedBy(Spacing.xs)
                    ) {
                        Text(
                            text = state.name.uppercase(),
                            style = AiPoseTypography.Heading2,
                            color = AiPoseColors.Foreground
                        )

                        if (state.difficulty != null) {
                            Text(
                                text = "Difficulty: ${state.difficulty.uppercase()}",
                                style = AiPoseTypography.BodyBold,
                                color = AiPoseColors.Primary
                            )
                        }
                        if (state.author != null) {
                            Text(
                                text = "Author: ${state.author}",
                                style = AiPoseTypography.Body,
                                color = AiPoseColors.Subtext
                            )
                        }
                        if (state.pose != null) {
                            Text(
                                text = "Created: ${state.pose.createdAt}",
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
                            coroutineScope.launch {
                                viewModel.tryPose(onSuccess = onUseWithCamera)
                            }
                        },
                        modifier = Modifier.fillMaxWidth()
                    )
                }

                if (showDeleteDialog) {
                    AlertDialog(
                        onDismissRequest = { showDeleteDialog = false },
                        title = { Text("Delete pose?") },
                        text = { Text("This will permanently remove ${state.name} from your library.") },
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
            }
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
    }
}
