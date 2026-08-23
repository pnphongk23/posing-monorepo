// composeApp/src/commonMain/kotlin/com/aipose/ui/components/PrimaryButton.kt
package com.aipose.ui.components

import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import com.aipose.ui.theme.AiPoseColors
import com.aipose.ui.theme.AiPoseTypography
import com.aipose.ui.theme.CornerRadius

@Composable
fun PrimaryButton(
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
            .neoShadow(cornerRadius = CornerRadius.sm)
            .neoBorder(),
        shape = RoundedCornerShape(CornerRadius.sm),
        colors = ButtonDefaults.buttonColors(
            containerColor = AiPoseColors.Primary,
            contentColor = AiPoseColors.Foreground,
            disabledContainerColor = AiPoseColors.Border,
            disabledContentColor = AiPoseColors.Subtext
        )
    ) {
        Text(
            text = text.uppercase(),
            style = AiPoseTypography.BodyBold,
            letterSpacing = 0.08.em
        )
    }
}
