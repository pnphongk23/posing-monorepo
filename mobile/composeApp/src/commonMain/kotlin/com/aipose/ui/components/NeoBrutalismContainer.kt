package com.aipose.ui.components

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.offset
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import com.aipose.ui.theme.AiPoseColors

@Composable
fun NeoBrutalismContainer(
    modifier: Modifier = Modifier,
    shape: Shape,
    backgroundColor: Color,
    borderColor: Color = AiPoseColors.Foreground,
    borderWidth: Dp = 2.dp,
    shadowColor: Color = Color.Black,
    shadowOffset: Dp = 4.dp,
    hasShadow: Boolean = true,
    contentAlignment: Alignment = Alignment.Center,
    onClick: (() -> Unit)? = null,
    interactionSource: MutableInteractionSource = remember { MutableInteractionSource() },
    content: @Composable BoxScope.() -> Unit
) {
    val isPressed by interactionSource.collectIsPressedAsState()

    val animatedTranslation by animateDpAsState(
        targetValue = if (isPressed) shadowOffset else 0.dp,
        animationSpec = tween(durationMillis = 100)
    )

    val clickableModifier = if (onClick != null) {
        Modifier.clickable(
            interactionSource = interactionSource,
            indication = null,
            role = Role.Button,
            onClick = onClick
        )
    } else Modifier

    Box(
        modifier = modifier.then(clickableModifier),
        propagateMinConstraints = true
    ) {
        // Shadow layer – behind content via zIndex & matching graphicsLayer context
        if (hasShadow) {
            Box(
                modifier = Modifier
                    .matchParentSize()
                    .graphicsLayer {
                        translationX = shadowOffset.toPx()
                        translationY = shadowOffset.toPx()
                    }
                    .background(shadowColor, shape)
                    .zIndex(-1f)
            )
        }
        // Content layer – drives the parent size (không dùng matchParentSize)
        Box(
            modifier = Modifier
                .graphicsLayer {
                    translationX = animatedTranslation.toPx()
                    translationY = animatedTranslation.toPx()
                }
                .background(backgroundColor, shape)
                .border(borderWidth, borderColor, shape),
            contentAlignment = contentAlignment
        ) {
            content()
        }
    }
}

