package com.aipose.auth

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * The three entry points that may interrupt a user with the shared [SignInPrompt]:
 * saving a pose from detail, opening the Saved collection from the Poses header,
 * and trying a pose from detail. Each intent owns its sign-in prompt copy and its
 * post-sign-in resume action.
 */
enum class SignInIntent {
    SAVE_POSE,
    OPEN_SAVED,
    TRY_POSE,
}

fun SignInIntent.promptTitle(): String = when (this) {
    SignInIntent.SAVE_POSE -> "Sign in to save poses to your account."
    SignInIntent.OPEN_SAVED -> "Sign in to view your saved poses."
    SignInIntent.TRY_POSE -> "Sign in to try this pose."
}

/**
 * Single-use interrupted-intent store. The prompt only ever holds one interrupted
 * intent; it is cleared after success, cancellation, or terminal failure so a
 * later screen can never replay a stale intent.
 */
class InterruptedIntentStore {
    private val _pending = MutableStateFlow<SignInIntent?>(null)
    val pending: StateFlow<SignInIntent?> = _pending.asStateFlow()

    fun set(intent: SignInIntent) {
        _pending.value = intent
    }

    /** Consumes and clears the pending intent; returns it for the resume action. */
    fun consume(): SignInIntent? = _pending.value.also { _pending.value = null }

    fun clear() {
        _pending.value = null
    }
}

/** App-wide single interrupted intent; wiped on sign-in success/cancel/failure. */
val globalInterruptedIntentStore = InterruptedIntentStore()