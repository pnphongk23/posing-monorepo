package com.aipose.settings

import com.aipose.platform.LegalDocument
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

private class FakeSettingsSessionProvider(
    var result: SettingsSessionState = SettingsSessionState.Guest,
    override var generation: Long = 0L,
    private val delayed: CompletableDeferred<SettingsSessionState>? = null,
) : SettingsSessionProvider {
    override suspend fun readSession(): SettingsSessionState = delayed?.await() ?: result
}

private class FakeSettingsOwnerNavigator : SettingsOwnerNavigator {
    var accountCalls = 0
    var savedCalls = 0
    var premiumCalls = 0

    override suspend fun openAccount(): SettingsDestinationResult {
        accountCalls++
        return SettingsDestinationResult.Opened
    }

    override suspend fun openSaved(): SettingsDestinationResult {
        savedCalls++
        return SettingsDestinationResult.Opened
    }

    override suspend fun openPremium(): SettingsDestinationResult {
        premiumCalls++
        return SettingsDestinationResult.NotConfigured
    }
}

private class FakeSettingsPermissionReader : SettingsPermissionReader {
    var reads = 0
    override suspend fun read(permissionId: String): SettingsPermissionState {
        reads++
        return SettingsPermissionState.Ready(PermissionStatus.Granted)
    }
}

private class FakeSettingsPlatformActions : SettingsPlatformActions {
    var legalDocuments = 0
    override suspend fun openPlatformSettings() = SettingsDestinationResult.Opened
    override suspend fun openLegalDocument(document: LegalDocument): SettingsDestinationResult {
        legalDocuments++
        return SettingsDestinationResult.Opened
    }
    override suspend fun openSupport() = SettingsDestinationResult.NotConfigured
}

@OptIn(ExperimentalCoroutinesApi::class)
class SettingsControllerTest {
    @Test
    fun `refresh reads session and permission through typed ports`() = runTest {
        val session = FakeSettingsSessionProvider(
            result = SettingsSessionState.SignedIn(AccountSummaryDisplay("Signed in")),
        )
        val permission = FakeSettingsPermissionReader()
        val controller = SettingsController(
            sessionProvider = session,
            ownerNavigator = FakeSettingsOwnerNavigator(),
            permissionReader = permission,
            platformActions = FakeSettingsPlatformActions(),
            scope = this,
        )

        controller.refresh()
        advanceUntilIdle()

        assertEquals(SettingsPhase.Ready, controller.state.value.phase)
        assertEquals(session.result, controller.state.value.session)
        assertEquals(
            SettingsPermissionState.Ready(PermissionStatus.Granted),
            controller.state.value.cameraPermission,
        )
        assertEquals(1, permission.reads)
    }

    @Test
    fun `stale session generation cannot publish a completed read`() = runTest {
        val delayed = CompletableDeferred<SettingsSessionState>()
        val session = FakeSettingsSessionProvider(delayed = delayed)
        val controller = SettingsController(
            sessionProvider = session,
            ownerNavigator = FakeSettingsOwnerNavigator(),
            permissionReader = FakeSettingsPermissionReader(),
            platformActions = FakeSettingsPlatformActions(),
            scope = this,
        )

        controller.refresh()
        runCurrent()
        session.generation = 1L
        delayed.complete(SettingsSessionState.SignedIn(AccountSummaryDisplay("stale")))
        advanceUntilIdle()

        assertEquals(SettingsPhase.Loading, controller.state.value.phase)
        assertEquals(SettingsSessionState.Loading, controller.state.value.session)
    }

    @Test
    fun `owner action is idempotent while the same destination is in flight`() = runTest {
        val owners = FakeSettingsOwnerNavigator()
        val controller = SettingsController(
            sessionProvider = FakeSettingsSessionProvider(),
            ownerNavigator = owners,
            permissionReader = FakeSettingsPermissionReader(),
            platformActions = FakeSettingsPlatformActions(),
            scope = this,
        )

        controller.openSaved()
        controller.openSaved()
        advanceUntilIdle()

        assertEquals(1, owners.savedCalls)
        assertTrue(controller.state.value.destinationResults[SettingsRowId.Saved] is SettingsDestinationResult.Opened)
    }
}
