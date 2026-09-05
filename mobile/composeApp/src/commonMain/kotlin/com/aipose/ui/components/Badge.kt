package com.aipose.ui.components

import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.em
import com.aipose.ui.theme.AiPoseColors
import com.aipose.ui.theme.AiPoseTypography

@Composable
fun Badge(
    text: String,
    type: BadgeType,
    modifier: Modifier = Modifier
) {
    Text(
        text = text.uppercase(),
        modifier = modifier.badgeChrome(type.backgroundColor),
        style = AiPoseTypography.MetaLabel,
        color = type.contentColor,
        letterSpacing = 0.04.em
    )
}

enum class BadgeType(
    val backgroundColor: androidx.compose.ui.graphics.Color,
    val contentColor: androidx.compose.ui.graphics.Color
) {
    MINE(AiPoseColors.Primary, AiPoseColors.Foreground),
    HOT(AiPoseColors.Error, AiPoseColors.Surface),
    NEW(AiPoseColors.Warning, AiPoseColors.Foreground)
}
