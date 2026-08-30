// composeApp/src/commonMain/kotlin/com/aipose/config/RemoteConfigFetcher.kt
package com.aipose.config

/** Outcome of one bounded fetch-and-activate attempt. */
sealed interface FetchResult {
    /** Activation succeeded; [rawValue] is the activated raw string (may be absent/invalid). */
    data class Success(val rawValue: String?) : FetchResult

    /** Firebase is not configured/unavailable on this device. */
    data object Unavailable : FetchResult

    /** The bounded wait elapsed without a completion callback. */
    data object Timeout : FetchResult

    /** Offline, fetch failure, throttled, or malformed activation response. */
    data object Error : FetchResult
}

/**
 * Pure Kotlin contract/test-only abstraction over a Remote Config source.
 * Production iOS resolution does NOT use this interface: the shipped path is the
 * native Swift bridge in `AppDelegate.swift`, which reuses
 * [AppStartupConfig.resolveEndpointValue] and [AppStartupConfig.applyEndpoint].
 * This contract exists for unit tests and to document the boundary.
 */
interface RemoteConfigFetcher {
    val isAvailable: Boolean

    /** Last-known-good activated value from the persisted SDK cache, or null. */
    fun cachedValue(key: String): String?

    /**
     * One bounded fetchAndActivate attempt at app start (DEC-006 step 5).
     * Must never throw and never route through PoseApiService.
     */
    suspend fun fetchAndActivate(timeoutMs: Long): FetchResult
}

/** No-op fetcher used when the platform bridge reports Firebase unavailable. */
object UnavailableRemoteConfigFetcher : RemoteConfigFetcher {
    override val isAvailable: Boolean get() = false
    override fun cachedValue(key: String): String? = null
    override suspend fun fetchAndActivate(timeoutMs: Long): FetchResult = FetchResult.Unavailable
}

/** Convenience so callers can obtain the DEC-006 cached value for api_baseurl. */
fun RemoteConfigFetcher.cachedBaseUrl(): String? =
    cachedValue(EndpointPolicy.REMOTE_CONFIG_KEY)
