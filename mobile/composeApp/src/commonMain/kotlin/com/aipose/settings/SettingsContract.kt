package com.aipose.settings

import com.aipose.platform.LegalDocument

enum class SettingsRowId {
    Account,
    Saved,
    Premium,
    CameraAccess,
    TermsOfService,
    PrivacyPolicy,
    Support,
    About,
}

sealed interface SettingsSessionState {
    data object Loading : SettingsSessionState
    data object Guest : SettingsSessionState
    data class SignedIn(val accountSummary: AccountSummaryDisplay) : SettingsSessionState
    data object Expired : SettingsSessionState
}

data class AccountSummaryDisplay(
    val label: String,
    val providerLabel: String? = null,
)

enum class PermissionStatus {
    Granted,
    Denied,
    Restricted,
}

sealed interface SettingsPermissionState {
    data object Loading : SettingsPermissionState
    data class Ready(val status: PermissionStatus) : SettingsPermissionState
    data class Unavailable(val reason: String) : SettingsPermissionState
    data class Failed(val retryable: Boolean) : SettingsPermissionState
}

sealed interface SettingsDestinationResult {
    data object Opened : SettingsDestinationResult
    data object NotConfigured : SettingsDestinationResult
    data class Failed(val message: String, val retryable: Boolean) : SettingsDestinationResult
}

interface SettingsSessionProvider {
    val generation: Long
    suspend fun readSession(): SettingsSessionState
}

interface SettingsOwnerNavigator {
    suspend fun openAccount(): SettingsDestinationResult
    suspend fun openSaved(): SettingsDestinationResult
    suspend fun openPremium(): SettingsDestinationResult
}

interface SettingsPermissionReader {
    suspend fun read(permissionId: String): SettingsPermissionState
}

interface SettingsPlatformActions {
    suspend fun openPlatformSettings(): SettingsDestinationResult
    suspend fun openLegalDocument(document: LegalDocument): SettingsDestinationResult
    suspend fun openSupport(): SettingsDestinationResult
}

enum class SettingsPhase {
    Loading,
    Ready,
    Refreshing,
    Error,
}

data class SettingsUiState(
    val phase: SettingsPhase = SettingsPhase.Loading,
    val session: SettingsSessionState = SettingsSessionState.Loading,
    val cameraPermission: SettingsPermissionState = SettingsPermissionState.Loading,
    val destinationResults: Map<SettingsRowId, SettingsDestinationResult> = emptyMap(),
    val message: String? = null,
)
