// composeApp/src/commonMain/kotlin/com/aipose/ui/theme/Typography.kt
package com.aipose.ui.theme

import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp

object AiPoseTypography {
    val Display = TextStyle(
        fontSize = 32.sp,
        fontWeight = FontWeight(800),
        lineHeight = 35.2.sp,
        letterSpacing = (-0.02).em
    )
    val ScreenTitle = TextStyle(
        fontSize = 24.sp,
        fontWeight = FontWeight(700),
        lineHeight = 26.4.sp,
        letterSpacing = (-0.01).em
    )
    val NavigationTitle = TextStyle(
        fontSize = 20.sp,
        fontWeight = FontWeight(700),
        lineHeight = 22.sp,
        letterSpacing = (-0.01).em
    )
    val Heading3 = TextStyle(
        fontSize = 18.sp,
        fontWeight = FontWeight(700),
        lineHeight = 19.8.sp,
        letterSpacing = (-0.01).em
    )
    val Body = TextStyle(
        fontSize = 14.sp,
        fontWeight = FontWeight(400),
        lineHeight = 21.7.sp
    )
    val Caption = TextStyle(
        fontSize = 12.sp,
        fontWeight = FontWeight(500),
        lineHeight = 16.8.sp
    )
    val MetaLabel = TextStyle(
        fontSize = 13.sp,
        fontWeight = FontWeight(500),
        lineHeight = 18.2.sp
    )
    val Control = TextStyle(
        fontSize = 14.sp,
        fontWeight = FontWeight(700),
        lineHeight = 17.5.sp
    )
    val Input = TextStyle(
        fontSize = 16.sp,
        fontWeight = FontWeight(400),
        lineHeight = 22.4.sp
    )
    val Tab = TextStyle(
        fontSize = 13.sp,
        fontWeight = FontWeight(700),
        lineHeight = 16.25.sp
    )
    val PosesToolbarTab = TextStyle(
        fontSize = 15.sp,
        fontWeight = FontWeight(700),
        lineHeight = 21.sp,
        letterSpacing = 0.02.em
    )
}
