package com.aipose.data.account

import com.aipose.data.auth.SessionBoundary
import com.aipose.data.auth.SessionEvent
import com.aipose.data.remote.AccountSummary
import com.aipose.data.remote.PoseApiException
import com.aipose.data.remote.PoseApiService
import com.aipose.data.remote.isUnauthorized
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch

/** Narrow read-only account adapter used by the Account screen. */
fun interface AccountSessionReader {
    suspend fun loadAccount(): AccountSummary
}

class ApiAccountSessionReader(
    private val apiService: PoseApiService,
) : AccountSessionReader {
    override suspend fun loadAccount(): AccountSummary = apiService.getCurrentAccount()
}

sealed interface AccountSessionState {
    data object Loading : AccountSessionState
    data object SignedOut : AccountSessionState
    data class SignedIn(val account: AccountSummary) : AccountSessionState
    data class Error(val message: String) : AccountSessionState
}

/**
 * Owns only the read-only Account projection and its session lifecycle. It never
 * writes profile data and invalidates in-flight reads when SessionBoundary changes.
 */
class AccountSessionController(
    private val reader: AccountSessionReader,
    private val sessionBoundary: SessionBoundary,
    private val scope: CoroutineScope,
) {
    private val _state = MutableStateFlow<AccountSessionState>(AccountSessionState.SignedOut)
    val state: StateFlow<AccountSessionState> = _state.asStateFlow()
    private var generationId = 0L

    init {
        scope.launch {
            sessionBoundary.events.collect { event ->
                when (event) {
                    SessionEvent.SignInRequired,
                    SessionEvent.SignedOut,
                    -> invalidateSession(AccountSessionState.SignedOut)
                    SessionEvent.SignedIn -> invalidateSession(AccountSessionState.Loading)
                }
            }
        }
    }

    fun load() {
        val currentGeneration = ++generationId
        val currentSessionGeneration = sessionBoundary.generation
        if (sessionBoundary.tokenStorage.loadCredentials() == null) {
            _state.value = AccountSessionState.SignedOut
            return
        }
        _state.value = AccountSessionState.Loading
        scope.launch {
            try {
                val account = reader.loadAccount()
                if (!isCurrent(currentGeneration, currentSessionGeneration)) return@launch
                if (sessionBoundary.tokenStorage.loadCredentials() == null) {
                    _state.value = AccountSessionState.SignedOut
                } else {
                    _state.value = AccountSessionState.SignedIn(account)
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: PoseApiException) {
                if (!isCurrent(currentGeneration, currentSessionGeneration)) return@launch
                _state.value = if (error.isUnauthorized()) {
                    AccountSessionState.SignedOut
                } else {
                    AccountSessionState.Error(error.message ?: "Unable to load your account.")
                }
            } catch (error: Exception) {
                if (!isCurrent(currentGeneration, currentSessionGeneration)) return@launch
                _state.value = AccountSessionState.Error(error.message ?: "Unable to load your account.")
            }
        }
    }

    fun retry() = load()

    /** Local, repeat-safe sign-out; no backend mutation is invented here. */
    fun signOut() {
        val currentGeneration = ++generationId
        scope.launch {
            sessionBoundary.signOut()
            if (generationId == currentGeneration) {
                _state.value = AccountSessionState.SignedOut
            }
        }
    }

    private fun invalidateSession(state: AccountSessionState) {
        generationId += 1
        _state.value = state
    }

    private fun isCurrent(requestGeneration: Long, sessionGeneration: Long): Boolean =
        generationId == requestGeneration && sessionBoundary.generation == sessionGeneration
}
