package com.aipose.data.auth

import io.ktor.client.HttpClient
import io.ktor.client.request.HttpRequestBuilder
import io.ktor.client.request.HttpRequestPipeline
import io.ktor.http.HttpHeaders
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow

enum class SessionEvent {
    SignInRequired,
    SignedOut,
    SignedIn,
}

class SessionBoundary(
    val tokenStorage: SecureTokenStorage,
) {
    // Replay the latest boundary event so late-created account/saved owners converge
    // on the same session projection. SignedIn is emitted when credentials are
    // established so a stale SignedOut/SignInRequired replay cannot survive login.
    private val _events = MutableSharedFlow<SessionEvent>(replay = 1, extraBufferCapacity = 1)
    val events: SharedFlow<SessionEvent> = _events
    private var generationId = 0L

    /** Monotonic session generation used to discard work that crossed sign-out. */
    val generation: Long get() = generationId

    suspend fun clearForUnauthorized() {
        tokenStorage.clearCredentials()
        generationId += 1
        _events.tryEmit(SessionEvent.SignInRequired)
    }

    /**
     * Clears only the local session. There is no invented backend sign-out endpoint;
     * repeating the operation is safe and leaves the same signed-out projection.
     */
    suspend fun signOut() {
        val hadCredentials = tokenStorage.loadCredentials() != null
        tokenStorage.clearCredentials()
        if (hadCredentials) {
            generationId += 1
            _events.tryEmit(SessionEvent.SignedOut)
        }
    }

    /** Establishes a backend-issued session and invalidates stale account work. */
    fun saveCredentials(credentials: SessionCredentials) {
        tokenStorage.saveCredentials(credentials)
        generationId += 1
        _events.tryEmit(SessionEvent.SignedIn)
    }

    /**
     * Refresh replaces credentials inside the same authenticated session. It must
     * not invalidate Account/Saved projections that are retrying the original read.
     */
    private fun saveRefreshedCredentials(credentials: SessionCredentials) {
        tokenStorage.saveCredentials(credentials)
    }

    suspend fun refresh(refresh: suspend (String) -> SessionCredentials?): Boolean {
        val refreshGeneration = generationId
        val refreshToken = tokenStorage.loadCredentials()?.refreshToken
        val updated = refreshToken?.let { refresh(it) }
        if (updated == null) {
            if (generationId == refreshGeneration) clearForUnauthorized()
            return false
        }
        if (generationId != refreshGeneration) return false
        saveRefreshedCredentials(updated)
        return true
    }
}

/** Installs the existing service client's mobile session transport and recovery seam. */
fun HttpClient.installSessionBoundary(boundary: SessionBoundary) {
    requestPipeline.intercept(HttpRequestPipeline.State) {
        val request: HttpRequestBuilder = context
        boundary.tokenStorage.loadCredentials()?.accessToken?.let { token ->
            request.headers.remove(HttpHeaders.Authorization)
            request.headers.append(HttpHeaders.Authorization, "Bearer $token")
        }
        proceed()
    }
}
