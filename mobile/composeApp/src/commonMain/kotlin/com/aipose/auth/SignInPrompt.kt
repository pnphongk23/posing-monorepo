package com.aipose.auth

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.aipose.ui.components.PrimaryButton
import com.aipose.ui.theme.AiPoseColors
import com.aipose.ui.theme.AiPoseTypography
import com.aipose.ui.theme.Spacing

/** E-SIGNIN: stable test tags for the shared sign-in prompt. */
internal const val SIGNIN_PROMPT_TEST_TAG = "signin-prompt"
internal const val SIGNIN_CONTINUE_TEST_TAG = "signin-continue-google"
internal const val SIGNIN_NOT_NOW_TEST_TAG = "signin-not-now"

/**
 * Shared modal sign-in prompt for all three entry points (Save / Saved / Try Pose).
 * One primary CTA — always `Continue with Google` — and the secondary `Not now`.
 * The interrupted intent is single-use: on real success it resumes once; on
 * cancellation or terminal failure it is cleared so it never replays on a later
 * screen. Success is only ever reported through [SignInPromptController]'s injected
 * launcher (a real response boundary, never a local fake).
 */
@Composable
fun SignInPrompt(
    controller: SignInPromptController,
    visible: Boolean,
    onDismiss: () -> Unit,
) {
    if (!visible) return
    val state by controller.state.collectAsState()
    val dismissText = "Not now"
    var dismissLocal by remember(state.intent) { mutableStateOf(false) }

    LaunchedEffect(state.intent) {
        dismissLocal = false
    }

    // Safe dismiss: "Not now" cancels without side effects (controller clears intent).
    fun safeDismiss() {
        dismissLocal = true
        controller.notNow()
        onDismiss()
    }

    AlertDialog(
        onDismissRequest = { if (!state.isAuthenticating) safeDismiss() },
        modifier = Modifier.testTag(SIGNIN_PROMPT_TEST_TAG),
        shape = RoundedCornerShape(16.dp),
        containerColor = AiPoseColors.Surface,
        title = {
            Text(
                text = state.intent.promptTitle(),
                style = AiPoseTypography.ScreenTitle,
                color = AiPoseColors.Foreground,
            )
        },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
                Text(
                    text = "Your saved poses and Try Pose are tied to your account. " +
                        "Continue with Google to keep them synced.",
                    style = AiPoseTypography.Body,
                    color = AiPoseColors.Subtext,
                )
                val promptError = state.error
                if (promptError != null) {
                    Text(
                        text = promptError,
                        style = AiPoseTypography.Caption,
                        color = AiPoseColors.Error,
                        modifier = Modifier.testTag("signin-error"),
                    )
                }
            }
        },
        confirmButton = {
            Box(
                modifier = Modifier.fillMaxWidth(),
                contentAlignment = Alignment.Center,
            ) {
                if (state.isAuthenticating) {
                    CircularProgressIndicator(
                        color = AiPoseColors.Primary,
                        modifier = Modifier.size(28.dp).testTag("signin-progress"),
                    )
                } else {
                    PrimaryButton(
                        text = "Continue with Google",
                        onClick = { if (!dismissLocal) controller.continueWithGoogle() },
                        modifier = Modifier
                            .fillMaxWidth()
                            .testTag(SIGNIN_CONTINUE_TEST_TAG),
                    )
                }
                if (state.error != null && !state.isAuthenticating) {
                    Spacer(modifier = Modifier.height(Spacing.xs))
                }
            }
        },
        dismissButton = {
            if (!state.isAuthenticating) {
                TextButton(
                    onClick = { if (!dismissLocal) safeDismiss() },
                    modifier = Modifier.testTag(SIGNIN_NOT_NOW_TEST_TAG),
                ) {
                    Text(dismissText, color = AiPoseColors.Foreground)
                }
            }
        },
    )
}