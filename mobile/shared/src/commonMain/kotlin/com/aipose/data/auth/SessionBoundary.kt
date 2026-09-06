package com.aipose.data.auth

import io.ktor.client.HttpClient
import io.ktor.client.request.HttpRequestBuilder
import io.ktor.client.request.HttpRequestPipeline
import io.ktor.http.HttpHeaders
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow

enum class SessionEvent {
    SignInRequired,
}

class SessionBoundary(
    val tokenStorage: SecureTokenStorage,
) {
    private val _events = MutableSharedFlow<SessionEvent>(extraBufferCapacity = 1)
    val events: SharedFlow<SessionEvent> = _events

    suspend fun clearForUnauthorized() {
        tokenStorage.clearCredentials()
        _events.tryEmit(SessionEvent.SignInRequired)
    }

    suspend fun refresh(refresh: suspend (String) -> SessionCredentials?): Boolean {
        val refreshToken = tokenStorage.loadCredentials()?.refreshToken
        val updated = refreshToken?.let { refresh(it) }
        if (updated == null) {
            clearForUnauthorized()
            return false
        }
        tokenStorage.saveCredentials(updated)
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
