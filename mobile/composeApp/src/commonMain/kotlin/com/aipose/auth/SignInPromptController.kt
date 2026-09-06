package com.aipose.auth

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

data class SignInPromptUiState(
    val intent: SignInIntent,
    val isAuthenticating: Boolean = false,
    val error: String? = null,
    val resolved: Boolean = false,
)

/**
 * Sign-in prompt logic controller. Guarantees:
 * - primary CTA is always "Continue with Google", secondary "Not now";
 * - success is only reported through a real [GoogleSignInResult.Success] from the
 *   injected launcher (never faked), and it fires the single-use [onSuccess] resume
 *   exactly once;
 * - cancellation/failure clears the interrupted intent so it never replays on a
 *   later screen;
 * - a pending launcher that never answers keeps the prompt in its pending state
 *   (no fabricated result).
 */
class SignInPromptController(
    private val launcher: GoogleSignInLauncher,
    private val store: InterruptedIntentStore = globalInterruptedIntentStore,
    private val onSuccess: (SignInIntent) -> Unit = {},
) {
    private val _state = MutableStateFlow(
        SignInPromptUiState(intent = SignInIntent.OPEN_SAVED)
    )
    val state: StateFlow<SignInPromptUiState> = _state.asStateFlow()

    fun show(intent: SignInIntent) {
        store.set(intent)
        _state.value = SignInPromptUiState(intent = intent)
    }

    fun continueWithGoogle() {
        val current = _state.value
        if (current.isAuthenticating || current.resolved) return
        _state.value = current.copy(isAuthenticating = true, error = null)
        launcher.start { result ->
            when (result) {
                is GoogleSignInResult.Success -> {
                    val intent = store.consume() ?: current.intent
                    _state.value = current.copy(isAuthenticating = false, resolved = true, error = null)
                    onSuccess(intent)
                }
                is GoogleSignInResult.Failure -> {
                    store.clear()
                    _state.value = current.copy(
                        isAuthenticating = false,
                        error = result.message,
                        resolved = false,
                    )
                }
            }
        }
    }

    /** "Not now": cancel with no side effect and clear the interrupted intent. */
    fun notNow() {
        store.clear()
        _state.value = _state.value.copy(isAuthenticating = false, resolved = false)
    }

    fun retryFailure() {
        if (_state.value.error != null) {
            _state.value = _state.value.copy(error = null)
            continueWithGoogle()
        }
    }
}