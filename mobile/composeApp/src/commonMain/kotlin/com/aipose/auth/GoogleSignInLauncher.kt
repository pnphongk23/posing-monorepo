package com.aipose.auth

/**
 * Real-response boundary for the Google sign-in trigger. The prompt never fakes
 * success: a launcher MUST resolve with a real [GoogleSignInResult] observed from
 * the platform OAuth seam (or a terminal failure). WI-04 keeps the Swift observer
 * (owned by the iosApp lane) behind this boundary — launching posts a request and
 * resolves only on a genuine response notification.
 */
interface GoogleSignInLauncher {
    fun start(onResult: (GoogleSignInResult) -> Unit)
}

sealed interface GoogleSignInResult {
    data object Success : GoogleSignInResult
    data class Failure(val message: String) : GoogleSignInResult
}

/** Platform-provided launcher. iOS actual follows the app's NSNotification bridge pattern. */
expect fun platformGoogleSignInLauncher(): GoogleSignInLauncher