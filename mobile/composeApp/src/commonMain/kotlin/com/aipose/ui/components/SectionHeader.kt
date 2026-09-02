package com.aipose.ui.components

import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.em
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxWidth
import com.aipose.ui.theme.AiPoseColors
import com.aipose.ui.theme.AiPoseTypography

@Composable
fun SectionHeader(
    title: String,
    count: Int,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = androidx.compose.ui.Alignment.CenterVertically
    ) {
        Text(
            text = title.uppercase(),
            style = AiPoseTypography.MetaLabel,
            color = AiPoseColors.Foreground,
            letterSpacing = 0.04.em
        )
        Text(
            text = "$count PHOTOS",
            style = AiPoseTypography.MetaLabel,
            color = AiPoseColors.Foreground.copy(alpha = 0.4f),
            letterSpacing = 0.04.em
        )
    }
}
