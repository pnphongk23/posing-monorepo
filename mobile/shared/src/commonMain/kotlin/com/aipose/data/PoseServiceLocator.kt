package com.aipose.data

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

    val httpClient: HttpClient by lazy {
        HttpClient {
            install(ContentNegotiation) {
                json(sharedJson)
            }
        }
    }

    val apiService: PoseApiService by lazy {
        PoseApiService(httpClient, baseUrl)
    }

    var communitySearchRepository: CommunitySearchRepository = LiveCommunitySearchRepository(apiService)

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
