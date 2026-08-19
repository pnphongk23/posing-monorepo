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
import kotlinx.coroutines.launch

@Composable
fun PhotoDetailDialog(
    photo: Photo,
    onDismiss: () -> Unit,
    onDelete: suspend (Long) -> Boolean,
    onToggleFavorite: (Long) -> Unit,
    onSave: (Photo) -> Unit,
) {
    var showDeleteConfirm by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val resolvedPath = remember(photo.imagePath) { resolveImagePath(photo.imagePath) }

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
                        .size(32.dp)
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
                    // Save Button (Mapped to Share icon to match Subframe)
                    Box(
                        modifier = Modifier
                            .size(32.dp)
                            .neoShadow(offsetX = 2.dp, offsetY = 2.dp, cornerRadius = 10.dp)
                            .background(AiPoseColors.Background, RoundedCornerShape(10.dp))
                            .neoBorder(width = 2.dp, cornerRadius = 10.dp)
                            .clip(RoundedCornerShape(10.dp))
                            .clickable { onSave(photo) },
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = Icons.Default.Share,
                            contentDescription = "Save",
                            tint = AiPoseColors.Foreground,
                            modifier = Modifier.size(16.dp)
                        )
                    }

                    // Trash Button
                    Box(
                        modifier = Modifier
                            .size(32.dp)
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
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f) // Takes remaining vertical space
                    .padding(horizontal = 4.dp)
                    .padding(bottom = Spacing.lg)
                    .neoShadow(offsetX = 4.dp, offsetY = 4.dp, cornerRadius = 16.dp)
                    .background(AiPoseColors.Surface, RoundedCornerShape(16.dp))
                    .neoBorder(width = 2.dp, cornerRadius = 16.dp)
                    .clip(RoundedCornerShape(16.dp)),
                contentAlignment = Alignment.Center
            ) {
                AsyncImage(
                    model = resolvedPath,
                    contentDescription = photo.poseName,
                    modifier = Modifier.fillMaxSize(),
                    contentScale = ContentScale.Crop // Matches object-cover in Subframe
                )
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
                    Text("DELETE", color = AiPoseColors.Error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirm = false }) {
                    Text("CANCEL")
                }
            }
        )
    }
}
