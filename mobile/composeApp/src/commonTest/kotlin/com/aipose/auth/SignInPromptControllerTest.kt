package com.aipose.auth

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * WI-04 SignInPrompt intent lifecycle evidence:
 * - success only ever reported through a real launcher result (never faked);
 * - success fires the single-use resume exactly once and clears the store;
 * - "Not now" / failure clears the interrupted intent so it never replays.
 */
class SignInPromptControllerTest {

    private class FakeLauncher(
        var result: GoogleSignInResult? = null,
    ) : GoogleSignInLauncher {
        var startCalls = 0
        var capturedCallback: ((GoogleSignInResult) -> Unit)? = null
        override fun start(onResult: (GoogleSignInResult) -> Unit) {
            startCalls++
            capturedCallback = onResult
            result?.let { onResult(it) }
        }
    }

    @Test
    fun `show retains the interrupted intent and clears on not now`() {
        val store = InterruptedIntentStore()
        val launcher = FakeLauncher()
        val controller = SignInPromptController(launcher, store)

        controller.show(SignInIntent.SAVE_POSE)
        assertEquals(SignInIntent.SAVE_POSE, store.pending.value)

        controller.notNow()
        assertNull(store.pending.value, "cancellation must clear the single-use intent")
    }

    @Test
    fun `real success fires resume exactly once and clears intent`() {
        val store = InterruptedIntentStore()
        val launcher = FakeLauncher(result = GoogleSignInResult.Success)
        var resumeCount = 0
        var resumedIntent: SignInIntent? = null
        val controller = SignInPromptController(launcher, store) { resumedIntent = it; resumeCount++ }

        controller.show(SignInIntent.TRY_POSE)
        controller.continueWithGoogle()

        assertEquals(1, resumeCount, "resume must fire exactly once")
        assertEquals(SignInIntent.TRY_POSE, resumedIntent)
        assertNull(store.pending.value)
        assertEquals(true, controller.state.value.resolved)
    }

    @Test
    fun `failure keeps retryable error and clears the intent`() {
        val store = InterruptedIntentStore()
        val launcher = FakeLauncher(result = GoogleSignInResult.Failure("Provider unavailable"))
        val controller = SignInPromptController(launcher, store)

        controller.show(SignInIntent.OPEN_SAVED)
        controller.continueWithGoogle()

        assertEquals("Provider unavailable", controller.state.value.error)
        assertFalse(controller.state.value.isAuthenticating)
        assertNull(store.pending.value, "terminal failure must clear the pending intent")
    }

    @Test
    fun `duplicate tap while authenticating is ignored`() {
        val launcher = FakeLauncher() // no result: stays pending (never fabricated)
        val store = InterruptedIntentStore()
        val controller = SignInPromptController(launcher, store)

        controller.show(SignInIntent.SAVE_POSE)
        controller.continueWithGoogle()
        controller.continueWithGoogle()

        assertEquals(1, launcher.startCalls, "second tap while pending must be ignored")
        assertEquals(true, controller.state.value.isAuthenticating)
        assertEquals(SignInIntent.SAVE_POSE, store.pending.value)
    }

    @Test
    fun `pending launcher that never answers produces no fabricated success`() {
        val launcher = FakeLauncher()
        val store = InterruptedIntentStore()
        var resumed = false
        val controller = SignInPromptController(launcher, store) { resumed = true }
        controller.show(SignInIntent.OPEN_SAVED)
        controller.continueWithGoogle()

        // No result delivered: must stay pending, not resolved, not resumed.
        assertEquals(true, controller.state.value.isAuthenticating)
        assertEquals(false, controller.state.value.resolved)
        assertFalse(resumed)
        launcher.capturedCallback?.invoke(GoogleSignInResult.Success)
        assertTrue(resumed)
    }
}