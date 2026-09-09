package com.aipose.ui.screens.gallery

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.SaveAlt
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.aipose.Photo
import com.aipose.navigation.MatchedImageDestination
import com.aipose.navigation.destinationChromeVisible
import com.aipose.platform.deletePhotoConfirmation
import com.aipose.purchases.PaywallScreen
import com.aipose.purchases.PurchaseGateway
import com.aipose.purchases.PurchaseGatewayProvider
import com.aipose.purchases.premiumTestBypassEnabled
import com.aipose.ui.components.neoBorder
import com.aipose.ui.components.neoShadow
import com.aipose.ui.theme.AiPoseColors
import com.aipose.ui.theme.AiPoseTypography
import com.aipose.ui.theme.Spacing
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import org.jetbrains.compose.resources.painterResource
import ai_pose.composeapp.generated.resources.Res
import ai_pose.composeapp.generated.resources.ic_chevron_left

@Composable
fun GalleryPhotoImageContent(
    model: String?,
    attempt: Int,
    contentDescription: String?,
    modifier: Modifier,
    onLoading: () -> Unit,
    onSuccess: () -> Unit,
    onError: () -> Unit,
) {
    key(attempt) {
        AsyncImage(
            model = model,
            contentDescription = contentDescription,
            modifier = modifier,
            contentScale = ContentScale.Crop,
            onLoading = { onLoading() },
            onSuccess = { onSuccess() },
            onError = { onError() },
        )
    }
}

@Composable
fun GalleryPhotoDetailScreen(
    photo: Photo,
    onBack: () -> Unit,
    onDelete: suspend (Long) -> Boolean,
    onSave: suspend (Photo) -> Boolean,
    onShare: ((Photo) -> Unit)? = null,
    purchaseGateway: PurchaseGateway = PurchaseGatewayProvider.current,
    imageContent: @Composable (
        model: String?,
        attempt: Int,
        contentDescription: String?,
        modifier: Modifier,
        onLoading: () -> Unit,
        onSuccess: () -> Unit,
        onError: () -> Unit,
    ) -> Unit = { model, attempt, contentDescription, modifier, onLoading, onSuccess, onError ->
        GalleryPhotoImageContent(
            model, attempt, contentDescription, modifier, onLoading, onSuccess, onError,
        )
    },
) {
    PhotoDetailDialog(
        photo = photo,
        onDismiss = onBack,
        onDelete = onDelete,
        onSave = onSave,
        onShare = onShare ?: {},
        purchaseGateway = purchaseGateway,
        imageContent = imageContent,
    )
}

@Composable
fun PhotoDetailDialog(
    photo: Photo,
    onDismiss: () -> Unit,
    onDelete: suspend (Long) -> Boolean,
    onSave: suspend (Photo) -> Boolean,
    onShare: (Photo) -> Unit,
    purchaseGateway: PurchaseGateway = PurchaseGatewayProvider.current,
    imageContent: @Composable (
        model: String?,
        attempt: Int,
        contentDescription: String?,
        modifier: Modifier,
        onLoading: () -> Unit,
        onSuccess: () -> Unit,
        onError: () -> Unit,
    ) -> Unit = { model, attempt, contentDescription, modifier, onLoading, onSuccess, onError ->
        GalleryPhotoImageContent(
            model, attempt, contentDescription, modifier, onLoading, onSuccess, onError,
        )
    },
) {
    var state by remember(photo.id) { mutableStateOf(initialGalleryPhotoViewerState(photo)) }
    var showDeleteConfirm by remember { mutableStateOf(false) }
    var showPaywall by remember { mutableStateOf(false) }
    var deleteInFlight by remember { mutableStateOf(false) }
    var deleteFlowActive by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val snackbarHostState = remember { SnackbarHostState() }
    val dateTime = remember(photo.createdAt) { formatGalleryPhotoCreatedAt(photo.createdAt) }
    val actionsEnabled = viewerActionsEnabled(state.media, deleteInFlight, state.save)
    val trashEnabled = viewerTrashEnabled(state.media, deleteFlowActive, deleteInFlight, state.save)
    val backEnabled = viewerBackEnabled(deleteInFlight, state.save)

    fun dispatch(event: GalleryPhotoViewerEvent) {
        state = reduce(state, event)
    }

    suspend fun performSave() {
        val saved = try {
            onSave(state.photo)
        } catch (ce: CancellationException) {
            throw ce
        } catch (_: Exception) {
            false
        }
        dispatch(GalleryPhotoViewerEvent.SaveResult(saved))
    }

    fun launchSaveRetry() {
        dispatch(GalleryPhotoViewerEvent.RetrySave)
        scope.launch { performSave() }
    }

    suspend fun executeDelete(): Boolean = try {
        onDelete(state.photo.id)
    } catch (ce: CancellationException) {
        throw ce
    } catch (_: Exception) {
        false
    }

    suspend fun executeDeleteWithGuard(): Boolean {
        if (deleteInFlight) return false
        deleteInFlight = true
        try {
            return executeDelete()
        } finally {
            deleteInFlight = false
        }
    }

    suspend fun runDeleteCoordination() {
        coordinateGalleryDeleteWithRetry(
            executeDelete = { executeDeleteWithGuard() },
            onDismiss = onDismiss,
            presentFailureSnackbar = {
                snackbarHostState.showSnackbar(
                    message = deletePhotoConfirmation(false),
                    actionLabel = "Retry",
                ) == SnackbarResult.ActionPerformed
            },
        )
    }

    fun launchDeleteFlow() {
        if (!canLaunchGalleryDeleteFlow(deleteFlowActive)) return
        showDeleteConfirm = false
        deleteFlowActive = true
        scope.launch {
            try {
                runDeleteCoordination()
            } finally {
                deleteFlowActive = false
            }
        }
    }

    LaunchedEffect(state.feedback) {
        val feedback = state.feedback ?: return@LaunchedEffect
        when (feedback) {
            is FeedbackMessage.Info -> {
                snackbarHostState.showSnackbar(feedback.text)
                dispatch(GalleryPhotoViewerEvent.FeedbackAcknowledged)
            }
            is FeedbackMessage.Error -> {
                val result = if (feedback.canRetry) {
                    snackbarHostState.showSnackbar(
                        message = feedback.text,
                        actionLabel = "Retry",
                    )
                } else {
                    snackbarHostState.showSnackbar(feedback.text)
                    SnackbarResult.Dismissed
                }
                dispatch(GalleryPhotoViewerEvent.FeedbackAcknowledged)
                if (feedback.canRetry && result == SnackbarResult.ActionPerformed) {
                    launchSaveRetry()
                }
            }
        }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        containerColor = AiPoseColors.Background,
        modifier = Modifier
            .fillMaxSize()
            .windowInsetsPadding(WindowInsets.systemBars),
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .padding(horizontal = Spacing.md, vertical = Spacing.md),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = Spacing.lg),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    modifier = Modifier
                        .size(44.dp)
                        .neoShadow(offsetX = 2.dp, offsetY = 2.dp, cornerRadius = 10.dp)
                        .background(AiPoseColors.Background, RoundedCornerShape(10.dp))
                        .neoBorder(width = 2.dp, cornerRadius = 10.dp)
                        .clip(RoundedCornerShape(10.dp))
                        .clickable(enabled = backEnabled) { onDismiss() }
                        .semantics { contentDescription = "Back" },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        painter = painterResource(Res.drawable.ic_chevron_left),
                        contentDescription = null,
                        tint = AiPoseColors.Foreground,
                        modifier = Modifier.size(16.dp),
                    )
                }

                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        text = dateTime?.dateLine ?: "—",
                        style = AiPoseTypography.Heading3,
                        color = AiPoseColors.Foreground,
                    )
                    Text(
                        text = dateTime?.timeLine ?: "",
                        style = AiPoseTypography.Caption,
                        color = AiPoseColors.Subtext,
                    )
                }

                Spacer(modifier = Modifier.size(44.dp))
            }

            val imageReady = state.media == MediaStatus.Ready
            val chromeVisible = destinationChromeVisible(state.transitionKey, imageReady)
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f)
                    .padding(horizontal = 4.dp)
                    .padding(bottom = Spacing.md)
                    .then(
                        if (chromeVisible && state.media != MediaStatus.Missing) {
                            Modifier
                                .neoShadow(offsetX = 4.dp, offsetY = 4.dp, cornerRadius = 16.dp)
                                .background(AiPoseColors.Surface, RoundedCornerShape(16.dp))
                                .neoBorder(width = 2.dp, cornerRadius = 16.dp)
                                .clip(RoundedCornerShape(16.dp))
                        } else {
                            Modifier
                        },
                    ),
                contentAlignment = Alignment.Center,
            ) {
                when (state.media) {
                    MediaStatus.Missing -> {
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(Spacing.sm),
                            modifier = Modifier.padding(Spacing.lg),
                        ) {
                            Icon(
                                imageVector = Icons.Default.Image,
                                contentDescription = null,
                                tint = AiPoseColors.Subtext,
                                modifier = Modifier.size(48.dp),
                            )
                            Text("Photo unavailable", style = AiPoseTypography.Heading3)
                            Text(
                                "This local file is missing, but the gallery record is still safe to recover.",
                                style = AiPoseTypography.Caption,
                                color = AiPoseColors.Subtext,
                            )
                            TextButton(
                                onClick = { dispatch(GalleryPhotoViewerEvent.RetryImage) },
                                enabled = backEnabled && !deleteInFlight,
                            ) {
                                Text("Try again")
                            }
                        }
                    }
                    else -> {
                        MatchedImageDestination(
                            key = state.transitionKey,
                            imageModel = state.resolvedPath,
                            cornerRadius = 16.dp,
                            modifier = Modifier.fillMaxSize(),
                        ) {
                            imageContent(
                                state.resolvedPath,
                                state.loadAttempt,
                                state.photo.poseName,
                                Modifier.fillMaxSize(),
                                { dispatch(GalleryPhotoViewerEvent.ImageLoading) },
                                { dispatch(GalleryPhotoViewerEvent.ImageReady) },
                                { dispatch(GalleryPhotoViewerEvent.ImageFailed) },
                            )
                        }
                    }
                }
            }

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = Spacing.sm),
                horizontalArrangement = Arrangement.SpaceEvenly,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                ViewerActionButton(
                    label = "Share",
                    icon = Icons.Default.Share,
                    enabled = actionsEnabled,
                    onClick = {
                        if (!actionsEnabled) return@ViewerActionButton
                        if (purchaseGateway.snapshot.value.hasConfirmedPremium || premiumTestBypassEnabled) {
                            onShare(state.photo)
                            scope.launch { snackbarHostState.showSnackbar("Share sheet ready") }
                        } else {
                            showPaywall = true
                        }
                    },
                )
                ViewerActionButton(
                    label = "Save",
                    icon = Icons.Default.SaveAlt,
                    enabled = actionsEnabled,
                    onClick = {
                        if (!actionsEnabled) return@ViewerActionButton
                        if (purchaseGateway.snapshot.value.hasConfirmedPremium || premiumTestBypassEnabled) {
                            dispatch(GalleryPhotoViewerEvent.SaveRequested)
                            scope.launch { performSave() }
                        } else {
                            showPaywall = true
                        }
                    },
                )
                ViewerActionButton(
                    label = "Trash",
                    icon = Icons.Default.Delete,
                    enabled = trashEnabled,
                    onClick = {
                        if (!trashEnabled) return@ViewerActionButton
                        if (!canLaunchGalleryDeleteFlow(deleteFlowActive)) return@ViewerActionButton
                        showDeleteConfirm = true
                    },
                )
            }
        }
    }

    if (showDeleteConfirm) {
        AlertDialog(
            onDismissRequest = {
                if (!deleteInFlight && canLaunchGalleryDeleteFlow(deleteFlowActive)) {
                    showDeleteConfirm = false
                }
            },
            title = { Text("Delete this photo?") },
            text = { Text("The photo will be removed from this device. This cannot be undone.") },
            confirmButton = {
                TextButton(
                    enabled = !deleteInFlight && canLaunchGalleryDeleteFlow(deleteFlowActive),
                    onClick = { launchDeleteFlow() },
                ) {
                    Text("Delete", color = AiPoseColors.Error)
                }
            },
            dismissButton = {
                TextButton(
                    onClick = { showDeleteConfirm = false },
                    enabled = !deleteInFlight && canLaunchGalleryDeleteFlow(deleteFlowActive),
                ) {
                    Text("Keep photo")
                }
            },
        )
    }

    if (showPaywall) {
        PaywallScreen(
            gateway = purchaseGateway,
            onDismiss = { showPaywall = false },
            modifier = Modifier.fillMaxSize(),
        )
    }
}

@Composable
private fun ViewerActionButton(
    label: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
        modifier = Modifier
            .clickable(enabled = enabled, onClick = onClick)
            .semantics { contentDescription = label }
            .padding(horizontal = Spacing.sm, vertical = Spacing.xs),
    ) {
        Box(
            modifier = Modifier
                .size(44.dp)
                .neoShadow(offsetX = 2.dp, offsetY = 2.dp, cornerRadius = 10.dp)
                .background(
                    if (enabled) AiPoseColors.Background else AiPoseColors.Surface,
                    RoundedCornerShape(10.dp),
                )
                .neoBorder(width = 2.dp, cornerRadius = 10.dp)
                .clip(RoundedCornerShape(10.dp)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = if (enabled) AiPoseColors.Foreground else AiPoseColors.Subtext,
                modifier = Modifier.size(18.dp),
            )
        }
        Text(
            text = label,
            style = AiPoseTypography.Caption,
            color = if (enabled) AiPoseColors.Foreground else AiPoseColors.Subtext,
        )
    }
}
