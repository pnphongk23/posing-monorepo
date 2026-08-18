package com.aipose.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.em
import com.aipose.ui.components.neoBorder
import com.aipose.ui.theme.AiPoseColors
import com.aipose.ui.theme.AiPoseTypography
import com.aipose.ui.theme.CornerRadius
import com.aipose.ui.theme.Spacing

import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp

@Composable
fun TabSwitcher(
    tabs: List<String>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
    disabledIndices: Set<Int> = emptySet(),
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .neoBorder(cornerRadius = CornerRadius.md)
            .background(AiPoseColors.Surface, RoundedCornerShape(CornerRadius.md))
            .padding(Spacing.xs),
        horizontalArrangement = Arrangement.spacedBy(Spacing.xs)
    ) {
        tabs.forEachIndexed { index, title ->
            val isSelected = index == selectedIndex
            val isDisabled = index in disabledIndices
            val backgroundColor = when {
                isSelected -> AiPoseColors.Primary
                else -> AiPoseColors.Surface
            }
            val textColor = when {
                isDisabled -> AiPoseColors.Subtext
                isSelected -> AiPoseColors.Foreground
                else -> AiPoseColors.Foreground
            }

            NeoBrutalismContainer(
                modifier = Modifier
                    .weight(1f)
                    .testTag("tab-${title.lowercase().replace(" ", "-")}"),
                shape = RoundedCornerShape(CornerRadius.sm),
                backgroundColor = backgroundColor,
                borderWidth = 0.dp,
                hasShadow = false,
                shadowOffset = 0.dp,
                onClick = if (!isDisabled) { { onSelect(index) } } else null
            ) {
                Row(
                    modifier = Modifier.padding(vertical = Spacing.md),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = title.uppercase(),
                        style = AiPoseTypography.CaptionBold,
                        color = textColor,
                        letterSpacing = 0.08.em
                    )
                }
            }
        }
    }
}
