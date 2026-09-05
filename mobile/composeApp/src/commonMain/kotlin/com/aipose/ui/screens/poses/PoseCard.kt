package com.aipose.ui.screens.poses

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Image
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.aipose.Pose
import com.aipose.ui.components.Badge
import com.aipose.ui.components.BadgeType
import com.aipose.ui.components.cardChrome
import com.aipose.ui.theme.AiPoseColors
import com.aipose.ui.theme.AiPoseTypography
import com.aipose.ui.theme.CornerRadius
import com.aipose.ui.theme.Spacing

import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import com.aipose.ui.components.NeoBrutalismContainer
import com.aipose.navigation.MatchedImageTransitionState

import com.aipose.data.resolveImagePath

import androidx.compose.ui.graphics.graphicsLayer
import com.aipose.navigation.SharedTransitionPhase

@Composable
fun PoseCard(
    pose: Pose,
    index: Int,
    onClick: (PosePreview) -> Unit,
    modifier: Modifier = Modifier
) {
    val aspectRatios = listOf(1f / 1.25f, 1f, 1.25f / 1f)
    var sourceBounds by remember { androidx.compose.runtime.mutableStateOf<androidx.compose.ui.geometry.Rect?>(null) }
    val aspectRatio = aspectRatios[index % 3]
    val resolvedPath = remember(pose.thumbnailPath) {
        resolveImagePath(pose.thumbnailPath) ?: pose.thumbnailPath.takeIf { it.isNotBlank() }
    }
    val isTransitioning = MatchedImageTransitionState.source?.key == "pose:${pose.poseId}" &&
            MatchedImageTransitionState.transitionPhase != SharedTransitionPhase.IDLE

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(Spacing.sm)
    ) {
        val cardShape = RoundedCornerShape(CornerRadius.md)
        NeoBrutalismContainer(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(aspectRatio)
                .testTag("pose-card-personal-${pose.poseId}")
                .semantics { contentDescription = pose.name },
            shape = cardShape,
            backgroundColor = AiPoseColors.Surface,
            shadowOffset = 4.dp,
            onClick = {
                sourceBounds?.let {
                    MatchedImageTransitionState.capture(
                        key = "pose:${pose.poseId}",
                        bounds = it,
                        imageModel = resolvedPath,
                        cornerRadius = CornerRadius.md,
                        contentScale = poseThumbnailContentScale()
                    )
                }
                onClick(
                    localPosePreview(
                        pose = pose,
                        resolvedImage = resolvedPath,
                        aspectRatio = aspectRatio,
                        cornerRadius = CornerRadius.md,
                    )
                )
            }
        ) {
            if (!resolvedPath.isNullOrBlank()) {
                AsyncImage(
                    model = resolvedPath,
                    contentDescription = null,
                    modifier = Modifier
                        .fillMaxSize()
                        .onGloballyPositioned { sourceBounds = it.boundsInWindow() }
                        .clip(cardShape)
                        .graphicsLayer { alpha = if (isTransitioning) 0f else 1f },
                    contentScale = poseThumbnailContentScale()
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
            style = AiPoseTypography.Control,
            color = AiPoseColors.Foreground,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(start = 2.dp)
        )
    }
}
