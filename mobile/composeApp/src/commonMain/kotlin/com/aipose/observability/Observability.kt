// composeApp/src/commonMain/kotlin/com/aipose/observability/Observability.kt
package com.aipose.observability

/**
 * FEAT-010 sanitization contract for Analytics events and Crashlytics
 * breadcrumbs (FR-004). Only small, stable, non-sensitive metadata is allowed:
 * no pose/camera/payment payloads, URLs with paths, tokens, or secrets.
 */
object EventSanitizer {
    /** Allowed parameter keys. Anything else is dropped. */
    val ALLOWED_KEYS = setOf("source", "outcome", "reason", "duration_ms")

    const val MAX_VALUE_LENGTH = 100

    /** Stable, safe event name subset used across the app. */
    object EventName {
        const val APP_START = "app_start"
        const val ENDPOINT_RESOLVED = "endpoint_resolved"
        const val CONFIG_STATUS = "config_status"

        val ALL = setOf(APP_START, ENDPOINT_RESOLVED, CONFIG_STATUS)
    }

    fun sanitizeEventName(name: String): String =
        name.take(40).filter { it.isLetterOrDigit() || it == '_' }.ifEmpty { "unknown" }

    fun sanitize(params: Map<String, String>): Map<String, String> =
        params
            .filterKeys { it in ALLOWED_KEYS }
            .mapValues { (_, value) ->
                value.take(MAX_VALUE_LENGTH).filter { !it.isISOControl() }
            }

    /** Drop obviously sensitive values (URLs with path, long token-like strings). */
    fun isSafeValue(value: String): Boolean {
        if (value.length > MAX_VALUE_LENGTH) return false
        if (value.any { it.isISOControl() }) return false
        // Reject anything that looks like a full URL or bearer token.
        if (value.contains("://")) return false
        if (value.contains(" ")) return false
        return true
    }
}

/** Event-name constants used by the gate and lifecycle hooks. */
object AnalyticsEvents {
    const val APP_START = EventSanitizer.EventName.APP_START
    const val ENDPOINT_RESOLVED = EventSanitizer.EventName.ENDPOINT_RESOLVED
    const val CONFIG_STATUS = EventSanitizer.EventName.CONFIG_STATUS
}

/**
 * Common-facing observability contract (DEC-007). **Pure contract/test-only**:
 * production iOS Analytics/Crashlytics calls live in the native Swift bridge
 * (`AppDelegate.swift`); this interface documents the sanitized boundary and is
 * implemented by [NoopObservability] in tests / when Firebase is unavailable.
 */
interface Observability {
    val isAvailable: Boolean
    fun logEvent(name: String, params: Map<String, String> = emptyMap())
    fun breadcrumb(key: String, value: String)
    fun recordNonFatal(message: String)
}

/** No-op observability used when Firebase is unavailable or in tests. */
object NoopObservability : Observability {
    override val isAvailable: Boolean get() = false
    override fun logEvent(name: String, params: Map<String, String>) = Unit
    override fun breadcrumb(key: String, value: String) = Unit
    override fun recordNonFatal(message: String) = Unit
}

// Platform factories are provided by the native Swift bridge (DEC-007), which
// compiles with Xcode and wires Firebase. Kotlin 2.0.0 cannot generate cinterop
// for the Xcode 26.1 SDK modulemap, so no `expect fun createObservability()`
// exists here; the Swift bridge reports availability and calls Kotlin's
// sanitized helpers (EventSanitizer) where useful.
