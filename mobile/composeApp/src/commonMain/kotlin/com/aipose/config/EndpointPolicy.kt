// composeApp/src/commonMain/kotlin/com/aipose/config/EndpointPolicy.kt
package com.aipose.config

/**
 * FEAT-010 / DEC-006: validation rules for the Remote Config `api_baseurl`
 * value. A value is usable only when it is a non-blank absolute http(s) URL
 * with a plausible host. Blank, whitespace-only, malformed, or disallowed
 * values are rejected (the caller falls back to cache/default).
 */
object EndpointPolicy {

    /** Exact Remote Config key mandated by DEC-006. */
    const val REMOTE_CONFIG_KEY = "api_baseurl"

    /**
     * Returns the normalized (trimmed) endpoint when [raw] is acceptable,
     * otherwise null. Never throws.
     */
    fun validate(raw: String?): String? {
        if (raw == null) return null
        val value = raw.trim()
        if (value.isEmpty()) return null
        // Any internal whitespace/control character means it is not a plain URL.
        if (value.any { it.isWhitespace() || it.isISOControl() }) return null
        val schemeEnd = value.indexOf("://")
        if (schemeEnd <= 0) return null
        val scheme = value.take(schemeEnd).lowercase()
        if (scheme != "http" && scheme != "https") return null
        val authority = value.substring(schemeEnd + 3).substringBefore('/')
            .substringBefore('?').substringBefore('#')
        if (authority.isEmpty()) return null
        // Reject embedded userinfo; Remote Config must not carry credentials.
        if (authority.contains('@')) return null
        val host = authority.substringBefore(':')
        if (host.isEmpty()) return null
        val hostAllowed = host.all { it.isLetterOrDigit() || it == '.' || it == '-' || it == '[' || it == ']' }
        if (!hostAllowed) return null
        val port = authority.substringAfter(':', missingDelimiterValue = "")
        if (port.isNotEmpty() && port.any { !it.isDigit() }) return null
        return value
    }
}
