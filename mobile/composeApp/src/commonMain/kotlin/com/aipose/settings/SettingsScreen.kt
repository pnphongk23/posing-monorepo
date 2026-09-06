package com.aipose.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.HelpOutline
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.PrivacyTip
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.aipose.ui.components.NeoBrutalismContainer
import com.aipose.ui.theme.AiPoseColors
import com.aipose.ui.theme.AiPoseTypography
import com.aipose.ui.theme.CornerRadius
import com.aipose.ui.theme.Spacing

internal const val SETTINGS_BACK_TEST_TAG = "settings-back"
internal const val SETTINGS_ACCOUNT_ROW_TEST_TAG = "settings-account-row"
internal const val SETTINGS_SAVED_ROW_TEST_TAG = "settings-saved-row"
internal const val SETTINGS_PREMIUM_ROW_TEST_TAG = "settings-premium-row"
internal const val SETTINGS_CAMERA_ROW_TEST_TAG = "settings-camera-row"
internal const val SETTINGS_TERMS_ROW_TEST_TAG = "settings-terms-row"
internal const val SETTINGS_PRIVACY_ROW_TEST_TAG = "settings-privacy-row"
internal const val SETTINGS_SUPPORT_ROW_TEST_TAG = "settings-support-row"
internal const val SETTINGS_ABOUT_ROW_TEST_TAG = "settings-about-row"

@Composable
fun SettingsScreen(
    controller: SettingsController,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val uiState by controller.state.collectAsState()
    var showAbout by remember { mutableStateOf(false) }
    val accountDescription = when (uiState.session) {
        SettingsSessionState.Loading -> "Checking your session"
        SettingsSessionState.Guest -> "Manage your account and sign-in options"
        is SettingsSessionState.SignedIn -> "Manage your account and session"
        SettingsSessionState.Expired -> "Your session needs attention"
    }
    val cameraStatus = when (val permission = uiState.cameraPermission) {
        SettingsPermissionState.Loading -> "Checking permission status"
        is SettingsPermissionState.Ready -> permission.status.name.lowercase().replaceFirstChar { it.uppercase() }
        is SettingsPermissionState.Unavailable -> permission.reason
        is SettingsPermissionState.Failed -> "Permission status unavailable"
    }
    val cameraAction: (() -> Unit)? = when (uiState.cameraPermission) {
        is SettingsPermissionState.Unavailable -> null
        SettingsPermissionState.Loading -> null
        else -> controller::openCameraAccess
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(AiPoseColors.Background)
            .statusBarsPadding()
            .navigationBarsPadding()
            .verticalScroll(rememberScrollState())
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
                modifier = Modifier.testTag(SETTINGS_BACK_TEST_TAG),
            ) {
                Icon(
                    imageVector = Icons.Default.ArrowBack,
                    contentDescription = "Back",
                    tint = AiPoseColors.Foreground,
                )
            }
            Text(
                text = "Settings",
                style = AiPoseTypography.ScreenTitle,
                color = AiPoseColors.Foreground,
            )
        }

        uiState.message?.let { message ->
            Text(
                text = message,
                style = AiPoseTypography.Body,
                color = AiPoseColors.ErrorForeground,
                modifier = Modifier.testTag("settings-message"),
            )
        }

        SettingsSection(title = "Account") {
            SettingsActionRow(
                icon = Icons.Default.AccountCircle,
                title = "Account",
                description = accountDescription,
                testTag = SETTINGS_ACCOUNT_ROW_TEST_TAG,
                onClick = controller::openAccount,
            )
        }

        SettingsSection(title = "Your AI Pose") {
            SettingsActionRow(
                icon = Icons.Default.Bookmark,
                title = "Saved poses",
                description = "Open your saved collection",
                testTag = SETTINGS_SAVED_ROW_TEST_TAG,
                onClick = controller::openSaved,
            )
            SettingsActionRow(
                icon = Icons.Default.WorkspacePremium,
                title = "Premium",
                description = "Manage premium access",
                testTag = SETTINGS_PREMIUM_ROW_TEST_TAG,
                onClick = controller::openPremium,
            )
        }

        SettingsSection(title = "Privacy") {
            SettingsActionRow(
                icon = Icons.Default.CameraAlt,
                title = "Camera access",
                description = "Check permission status or open iOS Settings",
                meta = cameraStatus,
                testTag = SETTINGS_CAMERA_ROW_TEST_TAG,
                onClick = cameraAction,
            )
            SettingsActionRow(
                icon = Icons.Default.Description,
                title = "Terms of Service",
                description = "Read the terms",
                testTag = SETTINGS_TERMS_ROW_TEST_TAG,
                onClick = controller::openTerms,
            )
            SettingsActionRow(
                icon = Icons.Default.PrivacyTip,
                title = "Privacy Policy",
                description = "Read the privacy policy",
                testTag = SETTINGS_PRIVACY_ROW_TEST_TAG,
                onClick = controller::openPrivacy,
            )
        }

        SettingsSection(title = "Help & support") {
            SettingsActionRow(
                icon = Icons.Default.HelpOutline,
                title = "Support & feedback",
                description = "Send feedback or request help",
                testTag = SETTINGS_SUPPORT_ROW_TEST_TAG,
                onClick = controller::openSupport,
            )
            SettingsActionRow(
                icon = Icons.Default.Info,
                title = "About",
                description = "App version and information",
                testTag = SETTINGS_ABOUT_ROW_TEST_TAG,
                onClick = {
                    controller.openAbout()
                    showAbout = true
                },
            )
        }
    }

    if (showAbout) {
        AlertDialog(
            onDismissRequest = { showAbout = false },
            title = {
                Text(
                    text = "About AI Pose",
                    style = AiPoseTypography.Heading3,
                    color = AiPoseColors.Foreground,
                )
            },
            text = {
                Text(
                    text = "Strike the pose. Snap the moment.",
                    style = AiPoseTypography.Body,
                    color = AiPoseColors.Subtext,
                )
            },
            confirmButton = {
                TextButton(onClick = { showAbout = false }) {
                    Text("Close", color = AiPoseColors.Foreground)
                }
            },
        )
    }
}

@Composable
private fun SettingsSection(
    title: String,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        Text(
            text = title,
            style = AiPoseTypography.MetaLabel,
            color = AiPoseColors.Subtext,
        )
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(Spacing.sm),
            content = content,
        )
    }
}

/** Shared row treatment keeps Settings and Account visually on the same baseline. */
@Composable
internal fun SettingsActionRow(
    icon: ImageVector,
    title: String,
    description: String,
    testTag: String,
    onClick: (() -> Unit)?,
    meta: String? = null,
    backgroundColor: Color = AiPoseColors.Surface,
) {
    NeoBrutalismContainer(
        modifier = Modifier
            .fillMaxWidth()
            .testTag(testTag),
        shape = RoundedCornerShape(CornerRadius.md),
        backgroundColor = if (onClick == null) AiPoseColors.SurfaceVariant else backgroundColor,
        borderColor = AiPoseColors.Foreground,
        borderWidth = 2.dp,
        shadowOffset = 2.dp,
        onClick = onClick,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(Spacing.md),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Spacing.md),
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = if (onClick == null) AiPoseColors.Subtext else AiPoseColors.Foreground,
                modifier = Modifier.size(24.dp),
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = title,
                    style = AiPoseTypography.Control,
                    color = if (onClick == null) AiPoseColors.Subtext else AiPoseColors.Foreground,
                )
                Text(
                    text = description,
                    style = AiPoseTypography.Caption,
                    color = AiPoseColors.Subtext,
                )
            }
            if (meta != null) {
                Text(
                    text = meta,
                    style = AiPoseTypography.Caption,
                    color = AiPoseColors.Subtext,
                )
            }
            if (onClick != null) {
                Icon(
                    imageVector = Icons.Default.ChevronRight,
                    contentDescription = null,
                    tint = AiPoseColors.Subtext,
                    modifier = Modifier.size(20.dp),
                )
            }
        }
    }
}
