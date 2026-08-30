// composeApp/src/commonMain/kotlin/com/aipose/config/RuntimeConfigResolver.kt
package com.aipose.config

/** Where the finally-applied endpoint came from (DEC-006 step ordering). */
enum class EndpointSource { DEFAULT, CACHE, FETCH }

/** Wire-friendly outcome for Analytics (never pose/camera/payment detail). */
enum class FetchOutcome(val wireName: String) {
    APPLIED("applied"),
    UNAVAILABLE("unavailable"),
    TIMEOUT("timeout"),
    ERROR("error"),
    EMPTY_OR_INVALID("empty_or_invalid"),
}

/**
 * Pure decision for DEC-006: final endpoint = valid(fetch) ?: valid(cache) ?: default.
 * No I/O, fully testable. This is a **contract/test-only** abstraction; the
 * shipped iOS path delegates the same precedence to
 * [AppStartupConfig.resolveEndpointValue] from native Swift (AppDelegate.swift).
 * [fetchResult] encodes whether a bounded fetch happened and what it returned;
 * [cachedRaw] is the SDK's persisted last-known-good value.
 */
object RuntimeConfigResolver {

    fun resolve(
        defaultUrl: String,
        cachedRaw: String?,
        fetchResult: FetchResult,
    ): EndpointResolution {
        val fetched = when (fetchResult) {
            is FetchResult.Success -> EndpointPolicy.validate(fetchResult.rawValue)
            else -> null
        }
        if (fetched != null) {
            return EndpointResolution(fetched, EndpointSource.FETCH, FetchOutcome.APPLIED)
        }

        val cached = EndpointPolicy.validate(cachedRaw)
        if (cached != null) {
            return EndpointResolution(cached, EndpointSource.CACHE, fetchOutcomeFor(fetchResult))
        }

        return EndpointResolution(defaultUrl, EndpointSource.DEFAULT, fetchOutcomeFor(fetchResult))
    }

    private fun fetchOutcomeFor(fetchResult: FetchResult): FetchOutcome = when (fetchResult) {
        is FetchResult.Success -> FetchOutcome.EMPTY_OR_INVALID // fetch ok but value invalid/empty
        is FetchResult.Unavailable -> FetchOutcome.UNAVAILABLE
        is FetchResult.Timeout -> FetchOutcome.TIMEOUT
        is FetchResult.Error -> FetchOutcome.ERROR
    }
}

data class EndpointResolution(
    val url: String,
    val source: EndpointSource,
    val outcome: FetchOutcome,
)
