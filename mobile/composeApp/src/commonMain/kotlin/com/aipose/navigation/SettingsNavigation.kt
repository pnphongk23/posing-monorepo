package com.aipose.navigation

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import cafe.adriel.voyager.core.screen.Screen
import cafe.adriel.voyager.navigator.LocalNavigator
import cafe.adriel.voyager.navigator.currentOrThrow
import com.aipose.auth.SignInIntent
import com.aipose.auth.SignInPrompt
import com.aipose.auth.SignInPromptController
import com.aipose.auth.platformGoogleSignInLauncher
import com.aipose.data.PoseServiceLocator
import com.aipose.data.account.AccountSessionController
import com.aipose.data.account.ApiAccountSessionReader
import com.aipose.data.auth.SessionBoundary
import com.aipose.platform.LegalDocument
import com.aipose.settings.AccountSummaryDisplay
import com.aipose.settings.SettingsController
import com.aipose.settings.SettingsDestinationResult
import com.aipose.settings.SettingsOwnerNavigator
import com.aipose.settings.SettingsPermissionReader
import com.aipose.settings.SettingsPermissionState
import com.aipose.settings.SettingsPlatformActions
import com.aipose.settings.SettingsScreen
import com.aipose.settings.SettingsSessionProvider
import com.aipose.settings.SettingsSessionState
import com.aipose.settings.platformSettingsActions
import com.aipose.settings.platformSettingsPermissionReader
import com.aipose.ui.screens.account.AccountScreen

/** Exactly-once guard for a nested Account -> Settings push until Settings returns. */
internal class SettingsNavigationGate {
    private var isOpen = false

    fun tryOpen(open: () -> Unit): Boolean {
        if (isOpen) return false
        isOpen = true
        open()
        return true
    }

    fun reset() {
        isOpen = false
    }
}

internal fun resolveSettingsSavedDestination(
    hasSession: () -> Boolean,
    openSaved: () -> SettingsDestinationResult,
    requestSignIn: () -> Unit,
): SettingsDestinationResult =
    if (hasSession()) {
        openSaved()
    } else {
        requestSignIn()
        SettingsDestinationResult.Opened
    }

internal fun handleAccountSignInSuccess(
    intent: SignInIntent,
    dismissPrompt: () -> Unit,
    reloadAccount: () -> Unit,
) {
    if (intent == SignInIntent.OPEN_ACCOUNT) dismissPrompt()
    reloadAccount()
}

internal fun handleSavedSignInSuccess(
    intent: SignInIntent,
    dismissPrompt: () -> Unit,
    openSaved: () -> Unit,
) {
    if (intent == SignInIntent.OPEN_SAVED) {
        dismissPrompt()
        openSaved()
    }
}

/** Host wiring for non-Settings owners; Settings itself only sees typed ports. */
internal data class SettingsHostActions(
    val onSavedClick: (() -> SettingsDestinationResult)? = null,
    val onPremiumClick: (() -> SettingsDestinationResult)? = null,
    val onCameraAccessClick: (() -> SettingsDestinationResult)? = null,
    val onTermsClick: (() -> SettingsDestinationResult)? = null,
    val onPrivacyClick: (() -> SettingsDestinationResult)? = null,
    val onSupportClick: (() -> SettingsDestinationResult)? = null,
    val onAboutClick: (() -> SettingsDestinationResult)? = null,
)

private class StoredSessionSettingsProvider(
    private val boundary: SessionBoundary,
) : SettingsSessionProvider {
    override val generation: Long get() = boundary.generation

    override suspend fun readSession(): SettingsSessionState =
        if (boundary.tokenStorage.loadCredentials() == null) {
            SettingsSessionState.Guest
        } else {
            // Account owns identity/provider details; Settings only needs a truthful
            // signed-in label for row gating and never infers an auth provider.
            SettingsSessionState.SignedIn(AccountSummaryDisplay(label = "Signed in"))
        }
}

private class HostSettingsOwnerNavigator(
    private val sessionBoundary: SessionBoundary,
    private val onAccount: () -> Unit,
    private val onSavedSignInRequired: () -> Unit,
    private val actions: SettingsHostActions,
) : SettingsOwnerNavigator {
    override suspend fun openAccount(): SettingsDestinationResult {
        onAccount()
        return SettingsDestinationResult.Opened
    }

    override suspend fun openSaved(): SettingsDestinationResult =
        resolveSettingsSavedDestination(
            hasSession = { sessionBoundary.tokenStorage.loadCredentials() != null },
            openSaved = { actions.onSavedClick?.invoke() ?: SettingsDestinationResult.NotConfigured },
            requestSignIn = onSavedSignInRequired,
        )

    override suspend fun openPremium(): SettingsDestinationResult =
        actions.onPremiumClick?.invoke()
            ?: SettingsDestinationResult.NotConfigured
}

private class HostSettingsPlatformActions(
    private val actions: SettingsHostActions,
    private val fallback: SettingsPlatformActions,
) : SettingsPlatformActions {
    override suspend fun openPlatformSettings(): SettingsDestinationResult =
        actions.onCameraAccessClick?.invoke()
            ?: fallback.openPlatformSettings()

    override suspend fun openLegalDocument(document: LegalDocument): SettingsDestinationResult {
        val action = when (document) {
            LegalDocument.TERMS -> actions.onTermsClick
            LegalDocument.PRIVACY -> actions.onPrivacyClick
        }
        return action?.invoke()
            ?: fallback.openLegalDocument(document)
    }

    override suspend fun openSupport(): SettingsDestinationResult =
        actions.onSupportClick?.invoke()
            ?: fallback.openSupport()
}

/** Settings is a nested Poses flow; no global Account tab or Home Account entry. */
internal class SettingsVoyagerScreen(
    private val hostActions: SettingsHostActions = SettingsHostActions(),
    private val onReturned: (() -> Unit)? = null,
) : Screen {
    @Composable
    override fun Content() {
        val navigator = LocalNavigator.currentOrThrow
        val scope = rememberCoroutineScope()
        var showSignIn by remember { mutableStateOf(false) }
        val signInController = remember {
            SignInPromptController(platformGoogleSignInLauncher()) { intent ->
                handleSavedSignInSuccess(
                    intent = intent,
                    dismissPrompt = { showSignIn = false },
                    openSaved = { hostActions.onSavedClick?.invoke(); Unit },
                )
            }
        }
        DisposableEffect(onReturned) {
            onDispose { onReturned?.invoke() }
        }
        val controller = remember {
            SettingsController(
                sessionProvider = StoredSessionSettingsProvider(PoseServiceLocator.sessionBoundary),
                ownerNavigator = HostSettingsOwnerNavigator(
                    sessionBoundary = PoseServiceLocator.sessionBoundary,
                    onAccount = { navigator.push(AccountVoyagerScreen(hostActions)) },
                    onSavedSignInRequired = {
                        signInController.show(SignInIntent.OPEN_SAVED)
                        showSignIn = true
                    },
                    actions = hostActions,
                ),
                permissionReader = platformSettingsPermissionReader(),
                platformActions = HostSettingsPlatformActions(hostActions, platformSettingsActions()),
                scope = scope,
            )
        }
        LaunchedEffect(controller) { controller.refresh() }
        SettingsScreen(
            controller = controller,
            onBack = {
                onReturned?.invoke()
                navigator.pop()
            },
        )
        SignInPrompt(
            controller = signInController,
            visible = showSignIn && signInController.state.value.intent == SignInIntent.OPEN_SAVED,
            onDismiss = { showSignIn = false },
        )
    }
}

/** Account owns only the read-only session projection and routes back to Settings. */
internal class AccountVoyagerScreen(
    private val hostActions: SettingsHostActions = SettingsHostActions(),
) : Screen {
    @Composable
    override fun Content() {
        val navigator = LocalNavigator.currentOrThrow
        val scope = rememberCoroutineScope()
        val accountController = remember {
            AccountSessionController(
                reader = ApiAccountSessionReader(PoseServiceLocator.apiService),
                sessionBoundary = PoseServiceLocator.sessionBoundary,
                scope = scope,
            )
        }
        LaunchedEffect(accountController) {
            accountController.load()
        }

        var showSignIn by remember { mutableStateOf(false) }
        val signInController = remember {
            SignInPromptController(platformGoogleSignInLauncher()) { intent ->
                handleAccountSignInSuccess(
                    intent = intent,
                    dismissPrompt = { showSignIn = false },
                    reloadAccount = accountController::load,
                )
            }
        }
        val settingsNavigationGate = remember { SettingsNavigationGate() }

        AccountScreen(
            controller = accountController,
            onBack = { navigator.pop() },
            onSettingsClick = {
                settingsNavigationGate.tryOpen {
                    navigator.push(
                        SettingsVoyagerScreen(
                            hostActions = hostActions,
                            onReturned = settingsNavigationGate::reset,
                        ),
                    )
                }
            },
            onSavedClick = hostActions.onSavedClick?.let { action ->
                { action(); Unit }
            },
            onSignInClick = {
                signInController.show(SignInIntent.OPEN_ACCOUNT)
                showSignIn = true
            },
        )
        SignInPrompt(
            controller = signInController,
            visible = showSignIn && signInController.state.value.intent == SignInIntent.OPEN_ACCOUNT,
            onDismiss = { showSignIn = false },
        )
    }
}
