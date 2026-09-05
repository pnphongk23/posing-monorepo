package com.aipose.data

import com.aipose.data.auth.SessionBoundary
import com.aipose.data.auth.installSessionBoundary
import com.aipose.data.auth.platformSecureTokenStorage
import com.aipose.data.remote.PoseApiService
import com.aipose.data.remote.sharedJson
import io.ktor.client.HttpClient
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.serialization.kotlinx.json.json
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

object PoseServiceLocator {
    var baseUrl: String = "https://pose-extract-server-production.up.railway.app"

    /**
     * Holder for the last successfully prepared Try Pose selection so the
     * Camera handoff (Plan 260809-2241) can consume it after the tab switch
     * instead of having the selection discarded. WI-04 only emits this typed
     * contract; it does not render the overlay or persist it across relaunch.
     */
    var preparedReference: PreparedPoseReference? = null

    val sessionBoundary: SessionBoundary by lazy {
        SessionBoundary(platformSecureTokenStorage())
    }

    val httpClient: HttpClient by lazy {
        HttpClient {
            install(ContentNegotiation) {
                json(sharedJson)
            }
        }.also { it.installSessionBoundary(sessionBoundary) }
    }

    val apiService: PoseApiService by lazy {
        PoseApiService(httpClient, baseUrl, sessionBoundary)
    }

    // FEAT-010 / DEC-006: lazy so that merely touching this locator does not
    // force `apiService` during object initialization. The startup gate applies
    // the resolved endpoint to `baseUrl` before any of these are first used,
    // so the API service always captures the resolved endpoint.
    val communitySearchRepository: CommunitySearchRepository by lazy {
        LiveCommunitySearchRepository(apiService)
    }

    // WI-03/WI-04: account-scoped Saved collection over the same bearer seam.
    val savedPosesRepository: SavedPosesRepository by lazy {
        LiveSavedPosesRepository(apiService)
    }

    val database: AiPoseDatabase by lazy {
        DatabaseProvider.getOrCreate(DatabaseDriverFactory())
    }

    val repository: PoseRepository by lazy {
        PoseRepository(database, apiService)
    }

    val coordinator: PosesLibraryCoordinator by lazy {
        PosesLibraryCoordinator(
            repository,
            apiService,
            CoroutineScope(SupervisorJob() + Dispatchers.Main),
        )
    }
}
