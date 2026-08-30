// composeApp/src/commonTest/kotlin/com/aipose/config/EndpointPolicyTest.kt
package com.aipose.config

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class EndpointPolicyTest {

    @Test
    fun `accepts plain https url`() {
        assertEquals(
            "https://specked-unhelpful-dispatch.ngrok-free.dev",
            EndpointPolicy.validate("https://specked-unhelpful-dispatch.ngrok-free.dev"),
        )
    }

    @Test
    fun `accepts http url and preserves path`() {
        assertEquals(
            "http://10.0.0.1:8080/api",
            EndpointPolicy.validate("http://10.0.0.1:8080/api"),
        )
    }

    @Test
    fun `trims surrounding whitespace`() {
        assertEquals(
            "https://x.dev",
            EndpointPolicy.validate("  https://x.dev  "),
        )
    }

    @Test
    fun `rejects null blank and whitespace only`() {
        assertNull(EndpointPolicy.validate(null))
        assertNull(EndpointPolicy.validate(""))
        assertNull(EndpointPolicy.validate("   "))
    }

    @Test
    fun `rejects internal whitespace`() {
        assertNull(EndpointPolicy.validate("https://bad dev/path"))
    }

    @Test
    fun `rejects non http schemes`() {
        assertNull(EndpointPolicy.validate("ftp://example.com"))
        assertNull(EndpointPolicy.validate("javascript:alert(1)"))
    }

    @Test
    fun `rejects missing scheme`() {
        assertNull(EndpointPolicy.validate("example.com/path"))
    }

    @Test
    fun `rejects embedded credentials`() {
        assertNull(EndpointPolicy.validate("https://user:pass@example.com"))
    }

    @Test
    fun `rejects empty host`() {
        assertNull(EndpointPolicy.validate("https:///path"))
    }

    @Test
    fun `rejects control characters`() {
        assertNull(EndpointPolicy.validate("https://x.dev\u0000"))
    }
}
