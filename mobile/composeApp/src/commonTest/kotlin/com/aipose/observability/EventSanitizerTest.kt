// composeApp/src/commonTest/kotlin/com/aipose/observability/EventSanitizerTest.kt
package com.aipose.observability

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class EventSanitizerTest {

    @Test
    fun `drops disallowed keys`() {
        val out = EventSanitizer.sanitize(
            mapOf("source" to "fetch", "pose_id" to "123", "api_key" to "secret"),
        )
        assertEquals(mapOf("source" to "fetch"), out)
    }

    @Test
    fun `truncates long values`() {
        val long = "a".repeat(500)
        val out = EventSanitizer.sanitize(mapOf("source" to long))
        assertEquals(EventSanitizer.MAX_VALUE_LENGTH, out["source"]?.length)
    }

    @Test
    fun `rejects url-like and space-containing values`() {
        assertFalse(EventSanitizer.isSafeValue("https://secret.dev/path"))
        assertFalse(EventSanitizer.isSafeValue("has space"))
        assertTrue(EventSanitizer.isSafeValue("fetch"))
    }

    @Test
    fun `strips control characters from values`() {
        val out = EventSanitizer.sanitize(mapOf("reason" to "ok\u0000x"))
        assertEquals("okx", out["reason"])
    }

    @Test
    fun `event name is normalized to safe charset`() {
        assertEquals("app_start", EventSanitizer.sanitizeEventName("app_start"))
        assertEquals("endpoint_resolved", EventSanitizer.sanitizeEventName("endpoint_resolved!!"))
    }

    @Test
    fun `no sensitive payloads in allowed keys`() {
        // The allowlist only permits routing/diagnostic metadata, never payloads.
        assertTrue(EventSanitizer.ALLOWED_KEYS.none { it.contains("pose") || it.contains("camera") || it.contains("payment") })
    }
}
