// composeApp/src/commonMain/kotlin/com/aipose/config/AppStartupConfig.kt
package com.aipose.config

import com.aipose.data.AppConfig
import com.aipose.data.PoseServiceLocator
import com.aipose.observability.AnalyticsEvents
import com.aipose.observability.Observability

/**
 * FEAT-010 / DEC-006 startup gate.
 *
 * Owns root configuration before any API-backed state is constructed. The gate
 * must run before `PoseServiceLocator` is first used so that its lazy
 * `apiService` captures the resolved endpoint rather than the compiled default.
 *
 * Single application path (DEC-006 step 6): the resolved endpoint is written to
 * [PoseServiceLocator.baseUrl] FIRST (which forces the locator's lazy
 * construction, capturing this URL), then mirrored to [AppConfig.SERVER_BASE_URL]
 * so both holders are always identical. Because [PoseServiceLocator]'s
 * repository is now lazy, touching the locator here does not eagerly build the
 * API service until the endpoint is already set.
 */
object AppStartupConfig {

    const val DEFAULT_FETCH_TIMEOUT_MS = 5_000L

    /**
     * Kotlin-orchestration variant of the startup gate. **Pure contract/
     * test-only**: the shipped iOS path is the native Swift bridge in
     * `AppDelegate.swift`, which reuses [resolveEndpointValue] and [applyEndpoint]
     * instead of this suspend helper.
     */
    suspend fun resolveAndApply(
        fetcher: RemoteConfigFetcher,
        observability: Observability,
        timeoutMs: Long = DEFAULT_FETCH_TIMEOUT_MS,
    ): EndpointResolution {
        val startedAt = kotlin.time.TimeSource.Monotonic.markNow()

        val fetchResult: FetchResult = if (fetcher.isAvailable) {
            runCatching { fetcher.fetchAndActivate(timeoutMs) }.getOrElse { FetchResult.Error }
        } else {
            FetchResult.Unavailable
        }

        val cachedRaw = if (fetcher.isAvailable) fetcher.cachedBaseUrl() else null
        val resolution = RuntimeConfigResolver.resolve(
            defaultUrl = AppConfig.SERVER_BASE_URL,
            cachedRaw = cachedRaw,
            fetchResult = fetchResult,
        )

        applyEndpoint(resolution.url)

        val durationMs = startedAt.elapsedNow().inWholeMilliseconds
        observability.logEvent(
            AnalyticsEvents.ENDPOINT_RESOLVED,
            mapOf(
                "source" to resolution.source.name.lowercase(),
                "outcome" to resolution.outcome.wireName,
                "duration_ms" to durationMs.toString(),
            ),
        )
        observability.breadcrumb(
            key = "endpoint_source",
            value = resolution.source.name.lowercase(),
        )
        return resolution
    }

    /**
     * Pure fetch/cache/default decision. This is the single source of truth for
     * endpoint precedence and is reused by the production iOS path
     * (AppDelegate.swift) so its behavior is covered by common tests.
     *
     * Precedence (DEC-006): valid fetched value -> valid pre-fetch cache ->
     * [defaultUrl]. An invalid or unavailable fetch never overwrites a valid
     * cache: [cachedRaw] is the value captured *before* fetchAndActivate, and
     * [fetchedRaw] is the post-activation value. Both are validated; the first
     * valid one wins, otherwise [defaultUrl] is used.
     *
     * Contract/test-only seam: production iOS resolution lives in native Swift
     * (AppDelegate.swift), which delegates the decision here. The shared pieces
     * reused by that path are [EndpointPolicy.validate] and [applyEndpoint].
     */
    fun resolveEndpointValue(defaultUrl: String, cachedRaw: String?, fetchedRaw: String?): String {
        EndpointPolicy.validate(fetchedRaw)?.let { return it }
        EndpointPolicy.validate(cachedRaw)?.let { return it }
        return defaultUrl
    }

    /**
     * The one path that writes both endpoint holders to the same value, in an
     * order that guarantees the lazy API service sees it. Exposed for tests and
     * reused by the native Swift bridge.
     */
    fun applyEndpoint(url: String) {
        // Write the locator first: forcing its construction now captures this URL.
        PoseServiceLocator.baseUrl = url
        // Mirror to the compile-time holder so the whole app agrees.
        AppConfig.SERVER_BASE_URL = url
    }
}
