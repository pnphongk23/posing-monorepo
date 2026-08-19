package com.aipose.ui.screens.gallery

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import org.jetbrains.compose.resources.painterResource
import ai_pose.composeapp.generated.resources.Res
import ai_pose.composeapp.generated.resources.ic_heart
import ai_pose.composeapp.generated.resources.ic_heart_filled
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Image
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import com.aipose.data.resolveImagePath
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import com.aipose.Photo
import com.aipose.ui.components.NeoBrutalismContainer
import com.aipose.ui.components.cardChrome
import com.aipose.ui.components.neoBorder
import com.aipose.ui.components.neoShadow
import com.aipose.ui.theme.AiPoseColors
import com.aipose.ui.theme.AiPoseTypography
import com.aipose.ui.theme.CornerRadius
import com.aipose.ui.theme.Spacing

@Composable
fun PhotoCard(
    photo: Photo,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    dense: Boolean = false,
) {
    if (dense) {
        GalleryDensePhotoCard(
            photo = photo,
            onClick = onClick,
            modifier = modifier,
        )
        return
    }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .semantics { testTag = "gallery-photo-item" },
        verticalArrangement = Arrangement.spacedBy(Spacing.xs)
    ) {
        NeoBrutalismContainer(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(1f)
                .clip(RoundedCornerShape(12.dp)),
            shape = RoundedCornerShape(12.dp),
            backgroundColor = AiPoseColors.Surface,
            shadowOffset = 2.dp,
            borderWidth = 2.dp,
            onClick = onClick
        ) {
            val resolvedPath = remember(photo.imagePath) { resolveImagePath(photo.imagePath) }
            if (resolvedPath != null) {
                AsyncImage(
                    model = resolvedPath,
                    contentDescription = photo.poseName,
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

            if (photo.poseName.isNotBlank()) {
                val badgeColor = when (photo.id % 4) {
                    0L -> AiPoseColors.Primary
                    1L -> AiPoseColors.Warning
                    2L -> AiPoseColors.AccentBlue
                    else -> AiPoseColors.Success
                }
                Text(
                    text = photo.poseName.uppercase(),
                    style = AiPoseTypography.Caption,
                    fontSize = 8.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 0.06.em,
                    color = AiPoseColors.Foreground,
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(6.dp)
                        .neoShadow(offsetX = 1.dp, offsetY = 1.dp, cornerRadius = 8.dp)
                        .background(badgeColor, RoundedCornerShape(8.dp))
                        .neoBorder(width = 2.dp, cornerRadius = 8.dp)
                        .padding(horizontal = 6.dp, vertical = 2.dp)
                )
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 2.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            val timeStr = formatEpochToTime(photo.createdAt)
            Text(
                text = timeStr,
                style = AiPoseTypography.Caption,
                color = AiPoseColors.Foreground.copy(alpha = 0.5f),
                fontWeight = FontWeight.SemiBold,
                letterSpacing = 0.08.em,
                fontSize = 9.sp
            )
            Icon(
                painter = painterResource(if (photo.isFavorite == 1L) Res.drawable.ic_heart_filled else Res.drawable.ic_heart),
                contentDescription = null,
                modifier = Modifier.size(10.dp),
                tint = if (photo.isFavorite == 1L) AiPoseColors.Primary else AiPoseColors.Foreground.copy(alpha = 0.3f)
            )
        }
    }
}

/** Prototype `.nb-card--gallery-dense`: square tile, cover crop, hairline border, no shadow. */
@Composable
private fun GalleryDensePhotoCard(
    photo: Photo,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val shape = RoundedCornerShape(DensePhotoCardDefaults.BORDER_RADIUS)
    Box(
        modifier = modifier
            .fillMaxWidth()
            .aspectRatio(DensePhotoCardDefaults.ASPECT_RATIO)
            .clip(shape)
            .border(DensePhotoCardDefaults.BORDER_WIDTH, AiPoseColors.Foreground.copy(alpha = 0.15f), shape)
            .background(AiPoseColors.Surface)
            .clickable(onClick = onClick)
            .semantics { testTag = "gallery-photo-item" },
        contentAlignment = Alignment.Center,
    ) {
        val resolvedPath = remember(photo.imagePath) { resolveImagePath(photo.imagePath) }
        if (resolvedPath != null) {
            AsyncImage(
                model = resolvedPath,
                contentDescription = photo.poseName.ifBlank { "Gallery photo" },
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Crop,
            )
        } else {
            Icon(
                imageVector = Icons.Default.Image,
                contentDescription = null,
                modifier = Modifier.size(32.dp),
                tint = AiPoseColors.Subtext,
            )
        }
    }
}

private fun formatEpochToTime(createdAt: String): String {
    return try {
        val millis = createdAt.toLong()
        val totalSeconds = millis / 1000
        val totalMinutes = totalSeconds / 60
        val totalHours = totalMinutes / 60
        val minutes = totalMinutes % 60
        // UTC hours; simple display
        val hoursUtc = totalHours % 24
        val amPm = if (hoursUtc < 12) "AM" else "PM"
        val hours12 = when {
            hoursUtc == 0L -> 12L
            hoursUtc > 12L -> hoursUtc - 12L
            else -> hoursUtc
        }
        val minStr = if (minutes < 10) "0$minutes" else "$minutes"
        "$hours12:$minStr $amPm"
    } catch (e: Exception) {
        createdAt
    }
}
