package com.aipose.settings

import com.aipose.platform.LegalDocument
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Settings owns presentation state only. Owner navigation, permission reads, and
 * platform/external actions stay behind typed ports so Settings cannot shadow them.
 */
class SettingsController(
    private val sessionProvider: SettingsSessionProvider,
    private val ownerNavigator: SettingsOwnerNavigator,
    private val permissionReader: SettingsPermissionReader,
    private val platformActions: SettingsPlatformActions,
    private val scope: CoroutineScope,
) {
    private val _state = MutableStateFlow(SettingsUiState())
    val state: StateFlow<SettingsUiState> = _state.asStateFlow()
    private var refreshGeneration = 0L
    private val inFlightRows = mutableSetOf<SettingsRowId>()

    fun refresh() {
        val requestGeneration = ++refreshGeneration
        val sessionGeneration = sessionProvider.generation
        val isInitial = _state.value.phase == SettingsPhase.Loading
        _state.value = _state.value.copy(
            phase = if (isInitial) SettingsPhase.Loading else SettingsPhase.Refreshing,
            message = null,
            session = if (isInitial) SettingsSessionState.Loading else _state.value.session,
            cameraPermission = if (isInitial) SettingsPermissionState.Loading else _state.value.cameraPermission,
        )
        scope.launch {
            try {
                val session = sessionProvider.readSession()
                if (!isCurrent(requestGeneration, sessionGeneration)) return@launch
                val permission = permissionReader.read(CAMERA_PERMISSION_ID)
                if (!isCurrent(requestGeneration, sessionGeneration)) return@launch
                _state.value = _state.value.copy(
                    phase = SettingsPhase.Ready,
                    session = session,
                    cameraPermission = permission,
                    message = null,
                )
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (!isCurrent(requestGeneration, sessionGeneration)) return@launch
                _state.value = _state.value.copy(
                    phase = SettingsPhase.Error,
                    message = error.message ?: "Settings are temporarily unavailable.",
                )
            }
        }
    }

    fun openAccount() = launchDestination(SettingsRowId.Account) { ownerNavigator.openAccount() }
    fun openSaved() = launchDestination(SettingsRowId.Saved) { ownerNavigator.openSaved() }
    fun openPremium() = launchDestination(SettingsRowId.Premium) { ownerNavigator.openPremium() }

    fun openCameraAccess() = launchDestination(SettingsRowId.CameraAccess) {
        platformActions.openPlatformSettings()
    }

    fun openTerms() = launchDestination(SettingsRowId.TermsOfService) {
        platformActions.openLegalDocument(LegalDocument.TERMS)
    }

    fun openPrivacy() = launchDestination(SettingsRowId.PrivacyPolicy) {
        platformActions.openLegalDocument(LegalDocument.PRIVACY)
    }

    fun openSupport() = launchDestination(SettingsRowId.Support) {
        platformActions.openSupport()
    }

    fun openAbout() = launchDestination(SettingsRowId.About) {
        // About is a fixed in-app surface; the row is still tracked as an owner action.
        SettingsDestinationResult.Opened
    }

    private fun launchDestination(
        row: SettingsRowId,
        action: suspend () -> SettingsDestinationResult,
    ) {
        if (!inFlightRows.add(row)) return
        scope.launch {
            try {
                val result = action()
                _state.value = _state.value.copy(
                    destinationResults = _state.value.destinationResults + (row to result),
                    message = when (result) {
                        SettingsDestinationResult.Opened -> null
                        SettingsDestinationResult.NotConfigured -> "This action is not configured on this host."
                        is SettingsDestinationResult.Failed -> result.message
                    },
                )
                if (result is SettingsDestinationResult.Opened &&
                    row != SettingsRowId.Account && row != SettingsRowId.Premium
                ) {
                    refresh()
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                _state.value = _state.value.copy(
                    destinationResults = _state.value.destinationResults + (
                        row to SettingsDestinationResult.Failed(
                            message = error.message ?: "Action failed",
                            retryable = true,
                        )
                    ),
                    message = error.message ?: "Action failed. Please try again.",
                )
            } finally {
                inFlightRows.remove(row)
            }
        }
    }

    private fun isCurrent(requestGeneration: Long, sessionGeneration: Long): Boolean =
        requestGeneration == refreshGeneration && sessionGeneration == sessionProvider.generation

    private companion object {
        const val CAMERA_PERMISSION_ID = "camera"
    }
}
