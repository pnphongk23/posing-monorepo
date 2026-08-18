package com.aipose.ui.screens.poses

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Image
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
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

@Composable
fun PoseCard(
    pose: Pose,
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
                .testTag("pose-card-personal-${pose.id}")
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
