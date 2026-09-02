// composeApp/src/commonMain/kotlin/com/aipose/ui/components/SecondaryButton.kt
package com.aipose.ui.components

import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.aipose.ui.theme.AiPoseColors
import com.aipose.ui.theme.AiPoseTypography
import com.aipose.ui.theme.CornerRadius

@Composable
fun SecondaryButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true
) {
    Button(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier
            .height(48.dp)
            .ghostBorder(),
        shape = RoundedCornerShape(CornerRadius.md),
        colors = ButtonDefaults.buttonColors(
            containerColor = AiPoseColors.Surface,
            contentColor = AiPoseColors.Foreground,
            disabledContainerColor = AiPoseColors.SurfaceVariant,
            disabledContentColor = AiPoseColors.Subtext
        )
    ) {
        Text(
            text = text,
            style = AiPoseTypography.Control
        )
    }
}
