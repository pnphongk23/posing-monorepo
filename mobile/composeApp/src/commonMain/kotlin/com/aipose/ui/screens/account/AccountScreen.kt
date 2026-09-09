package com.aipose.ui.screens.account

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.aipose.data.account.AccountSessionController
import com.aipose.data.account.AccountSessionState
import com.aipose.ui.components.NeoBrutalismContainer
import com.aipose.ui.components.PrimaryButton
import com.aipose.ui.components.SecondaryButton
import com.aipose.settings.SettingsActionRow
import com.aipose.ui.theme.AiPoseColors
import com.aipose.ui.theme.AiPoseTypography
import com.aipose.ui.theme.CornerRadius
import com.aipose.ui.theme.Spacing

internal const val ACCOUNT_BACK_TEST_TAG = "account-back"
internal const val ACCOUNT_SETTINGS_ROW_TEST_TAG = "account-settings-row"
internal const val ACCOUNT_SAVED_ROW_TEST_TAG = "account-saved-row"
internal const val ACCOUNT_SIGN_IN_TEST_TAG = "account-sign-in"
internal const val ACCOUNT_SIGN_OUT_TEST_TAG = "account-sign-out"
internal const val ACCOUNT_RETRY_TEST_TAG = "account-retry"

@Composable
fun AccountScreen(
    controller: AccountSessionController,
    onBack: () -> Unit,
    onSettingsClick: () -> Unit,
    onSavedClick: (() -> Unit)?,
    onSignInClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val state by controller.state.collectAsState()
    Column(
        modifier = modifier
            .fillMaxSize()
            .background(AiPoseColors.Background)
            .statusBarsPadding()
            .navigationBarsPadding()
            .padding(Spacing.lg),
        verticalArrangement = Arrangement.spacedBy(Spacing.xl),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
        ) {
            IconButton(
                onClick = onBack,
                modifier = Modifier.testTag(ACCOUNT_BACK_TEST_TAG),
            ) {
                Icon(
                    imageVector = Icons.Default.ArrowBack,
                    contentDescription = "Back",
                    tint = AiPoseColors.Foreground,
                )
            }
            Text(
                text = "Account",
                style = AiPoseTypography.ScreenTitle,
                color = AiPoseColors.Foreground,
            )
        }

        when (val current = state) {
            AccountSessionState.Loading -> LoadingAccount()
            AccountSessionState.SignedOut -> SignedOutAccount(onSignInClick)
            is AccountSessionState.Error -> ErrorAccount(current.message, controller::retry)
            is AccountSessionState.SignedIn -> SignedInAccount(
                account = current.account,
                onSettingsClick = onSettingsClick,
                onSavedClick = onSavedClick,
                onSignOut = controller::signOut,
            )
        }
    }
}

@Composable
private fun LoadingAccount() {
    Column(
        modifier = Modifier.fillMaxWidth().padding(top = Spacing.xxl),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.md),
    ) {
        CircularProgressIndicator(
            color = AiPoseColors.Primary700,
            modifier = Modifier.size(32.dp),
        )
        Text(
            text = "Loading account…",
            style = AiPoseTypography.Body,
            color = AiPoseColors.Subtext,
        )
    }
}

@Composable
private fun SignedOutAccount(onSignInClick: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
        Text(
            text = "You’re signed out",
            style = AiPoseTypography.Heading3,
            color = AiPoseColors.Foreground,
        )
        Text(
            text = "Sign in to view your account and account-scoped Saved poses.",
            style = AiPoseTypography.Body,
            color = AiPoseColors.Subtext,
        )
        PrimaryButton(
            text = "Continue with Google",
            onClick = onSignInClick,
            modifier = Modifier.fillMaxWidth().testTag(ACCOUNT_SIGN_IN_TEST_TAG),
        )
    }
}

@Composable
private fun ErrorAccount(message: String, onRetry: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
        Text(
            text = "Account unavailable",
            style = AiPoseTypography.Heading3,
            color = AiPoseColors.Foreground,
        )
        Text(
            text = message,
            style = AiPoseTypography.Body,
            color = AiPoseColors.ErrorForeground,
        )
        SecondaryButton(
            text = "Retry",
            onClick = onRetry,
            modifier = Modifier.fillMaxWidth().testTag(ACCOUNT_RETRY_TEST_TAG),
        )
    }
}

@Composable
private fun SignedInAccount(
    account: com.aipose.data.remote.AccountSummary,
    onSettingsClick: () -> Unit,
    onSavedClick: (() -> Unit)?,
    onSignOut: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.lg)) {
        NeoBrutalismContainer(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(CornerRadius.md),
            backgroundColor = AiPoseColors.Primary50,
            shadowOffset = 2.dp,
        ) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(Spacing.lg),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Spacing.md),
            ) {
                Icon(
                    imageVector = Icons.Default.AccountCircle,
                    contentDescription = null,
                    tint = AiPoseColors.Foreground,
                    modifier = Modifier.size(40.dp),
                )
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = account.displayName.ifBlank { "Signed-in account" },
                        style = AiPoseTypography.Heading3,
                        color = AiPoseColors.Foreground,
                    )
                    Text(
                        text = account.id,
                        style = AiPoseTypography.Caption,
                        color = AiPoseColors.Subtext,
                    )
                }
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            SettingsActionRow(
                icon = Icons.Default.Settings,
                title = "Settings",
                description = "Manage app settings",
                testTag = ACCOUNT_SETTINGS_ROW_TEST_TAG,
                onClick = onSettingsClick,
            )
            SettingsActionRow(
                icon = Icons.Default.Bookmark,
                title = "Saved poses",
                description = "Open your saved collection",
                testTag = ACCOUNT_SAVED_ROW_TEST_TAG,
                onClick = onSavedClick,
            )
        }

        SecondaryButton(
            text = "Sign out",
            onClick = onSignOut,
            modifier = Modifier.fillMaxWidth().testTag(ACCOUNT_SIGN_OUT_TEST_TAG),
        )
    }
}
