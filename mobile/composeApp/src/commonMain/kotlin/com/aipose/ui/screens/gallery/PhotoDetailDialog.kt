package com.aipose.ui.screens.gallery

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
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
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import com.aipose.data.resolveImagePath
import com.aipose.navigation.MatchedImageDestination
import com.aipose.navigation.destinationChromeVisible
import com.aipose.platform.saveToPhotos
import com.aipose.platform.shareImage
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import org.jetbrains.compose.resources.painterResource
import ai_pose.composeapp.generated.resources.Res
import ai_pose.composeapp.generated.resources.ic_chevron_left
import com.aipose.Photo
import com.aipose.ui.components.neoBorder
import com.aipose.ui.components.neoShadow
import com.aipose.ui.theme.AiPoseColors
import com.aipose.ui.theme.Spacing
import com.aipose.purchases.PaywallScreen
import com.aipose.purchases.PurchaseGateway
import com.aipose.purchases.UnconfiguredPurchaseGateway
import com.aipose.purchases.PurchaseGatewayProvider
import kotlinx.coroutines.launch

@Composable
fun GalleryPhotoDetailScreen(
    photo: Photo,
    onBack: () -> Unit,
    // The host must inject its platform share sheet here. The default is a
    // deliberate no-op, never a save alias, until that external capability is wired.
    onShare: ((Photo) -> Unit)? = null,
    purchaseGateway: PurchaseGateway = PurchaseGatewayProvider.current,
) {
    val viewModel = remember { GalleryViewModel() }
    val scope = rememberCoroutineScope()
    PhotoDetailDialog(
        photo = photo,
        onDismiss = onBack,
        onDelete = { id -> viewModel.deletePhoto(id); true },
        onToggleFavorite = { id ->
            scope.launch { viewModel.toggleFavorite(id) }
        },
        onSave = { selected ->
            val path = resolveImagePath(selected.imagePath) ?: selected.imagePath
            saveToPhotos(path, null)
        },
        onShare = onShare ?: { selected ->
            val path = resolveImagePath(selected.imagePath) ?: selected.imagePath
            shareImage(path, null)
        },
        purchaseGateway = purchaseGateway,
    )
}

@Composable
fun PhotoDetailDialog(
    photo: Photo,
    onDismiss: () -> Unit,
    onDelete: suspend (Long) -> Boolean,
    onToggleFavorite: (Long) -> Unit,
    onSave: (Photo) -> Unit,
    onShare: (Photo) -> Unit = {},
    purchaseGateway: PurchaseGateway = PurchaseGatewayProvider.current,
) {
    var showDeleteConfirm by remember { mutableStateOf(false) }
    var showPaywall by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val resolvedPath = remember(photo.imagePath) {
        resolveImagePath(photo.imagePath) ?: photo.imagePath.takeIf { it.isNotBlank() }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(AiPoseColors.Background)
            .windowInsetsPadding(WindowInsets.systemBars)
            .padding(horizontal = Spacing.md, vertical = Spacing.md)
    ) {
        Column(
            modifier = Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            // Top Bar
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = Spacing.lg),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Back button
                Box(
                    modifier = Modifier
                        .size(44.dp)
                        .neoShadow(offsetX = 2.dp, offsetY = 2.dp, cornerRadius = 10.dp)
                        .background(AiPoseColors.Background, RoundedCornerShape(10.dp))
                        .neoBorder(width = 2.dp, cornerRadius = 10.dp)
                        .clip(RoundedCornerShape(10.dp))
                        .clickable { onDismiss() },
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        painter = painterResource(Res.drawable.ic_chevron_left),
                        contentDescription = "Back",
                        tint = AiPoseColors.Foreground,
                        modifier = Modifier.size(16.dp)
                    )
                }

                // Title removed as requested

                // Right actions
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // Save Button
                    Box(
                        modifier = Modifier
                            .size(44.dp)
                            .neoShadow(offsetX = 2.dp, offsetY = 2.dp, cornerRadius = 10.dp)
                            .background(AiPoseColors.Background, RoundedCornerShape(10.dp))
                            .neoBorder(width = 2.dp, cornerRadius = 10.dp)
                            .clip(RoundedCornerShape(10.dp))
                          .clickable {
                              if (purchaseGateway.snapshot.value.hasConfirmedPremium) onSave(photo) else showPaywall = true
                          },
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = Icons.Default.Share,
                            contentDescription = "Save",
                            tint = AiPoseColors.Foreground,
                            modifier = Modifier.size(16.dp)
                        )
                    }

                    // Share Button uses the same confirmed-entitlement gate.
                    Box(
                        modifier = Modifier
                            .size(44.dp)
                            .neoShadow(offsetX = 2.dp, offsetY = 2.dp, cornerRadius = 10.dp)
                            .background(AiPoseColors.Background, RoundedCornerShape(10.dp))
                            .neoBorder(width = 2.dp, cornerRadius = 10.dp)
                            .clip(RoundedCornerShape(10.dp))
                            .clickable {
                                if (purchaseGateway.snapshot.value.hasConfirmedPremium) onShare(photo) else showPaywall = true
                            },
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(Icons.Default.Share, "Share", tint = AiPoseColors.Foreground, modifier = Modifier.size(16.dp))
                    }

                    // Trash Button
                    Box(
                        modifier = Modifier
                            .size(44.dp)
                            .neoShadow(offsetX = 2.dp, offsetY = 2.dp, cornerRadius = 10.dp)
                            .background(AiPoseColors.Background, RoundedCornerShape(10.dp))
                            .neoBorder(width = 2.dp, cornerRadius = 10.dp)
                            .clip(RoundedCornerShape(10.dp))
                            .clickable { showDeleteConfirm = true },
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = Icons.Default.Delete,
                            contentDescription = "Delete",
                            tint = AiPoseColors.Foreground,
                            modifier = Modifier.size(16.dp)
                        )
                    }
                }
            }

            // Image Container
            val detailKey = "photo:${photo.id}"
            var imageReady by remember(detailKey) { mutableStateOf(false) }
            // Gate the whole border/background/stroke/clip on the readiness
            // boundary: it is revealed only once the flyer has covered the
            // destination or the Coil painter has loaded the media — never as an
            // empty frame. Stable key + same resolved model == same cache identity.
            val chromeVisible = destinationChromeVisible(detailKey, imageReady)
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f) // Takes remaining vertical space
                    .padding(horizontal = 4.dp)
                    .padding(bottom = Spacing.lg)
                    .then(
                        if (chromeVisible) {
                            Modifier
                                .neoShadow(offsetX = 4.dp, offsetY = 4.dp, cornerRadius = 16.dp)
                                .background(AiPoseColors.Surface, RoundedCornerShape(16.dp))
                                .neoBorder(width = 2.dp, cornerRadius = 16.dp)
                                .clip(RoundedCornerShape(16.dp))
                        } else {
                            Modifier
                        }
                    ),
                contentAlignment = Alignment.Center
            ) {
                MatchedImageDestination(
                    key = detailKey,
                    imageModel = resolvedPath,
                    cornerRadius = 16.dp,
                    modifier = Modifier.fillMaxSize(),
                ) {
                    AsyncImage(
                        model = resolvedPath,
                        contentDescription = photo.poseName,
                        modifier = Modifier.fillMaxSize(),
                        contentScale = ContentScale.Crop,
                        onLoading = { imageReady = false },
                        onSuccess = { imageReady = true },
                        onError = { imageReady = false },
                    )
                }
            }
        }
    }

    // Delete confirmation dialog
      if (showDeleteConfirm) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            title = { Text("Delete Photo") },
            text = { Text("This photo will be permanently deleted.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        scope.launch {
                            val deleted = onDelete(photo.id)
                            // Dismiss the detail dialog only on success; on
                            // failure the caller shows a snackbar and this
                            // dialog stays open so the user can retry.
                            if (deleted) {
                                onDismiss()
                            } else {
                                showDeleteConfirm = false
      }

                        }
                    }
                ) {
                    Text("Delete", color = AiPoseColors.Error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirm = false }) {
                    Text("Cancel")
                }
            }
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
