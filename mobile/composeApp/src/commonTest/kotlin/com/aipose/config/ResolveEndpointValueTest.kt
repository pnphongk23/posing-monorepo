// composeApp/src/commonTest/kotlin/com/aipose/config/ResolveEndpointValueTest.kt
package com.aipose.config

import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Covers the exact fetch/cache/default precedence delegated to by the native
 * Swift bridge in AppDelegate.swift. An invalid or unavailable fetch must never
 * overwrite a valid pre-fetch cache.
 */
class ResolveEndpointValueTest {

    private val default = "https://specked-unhelpful-dispatch.ngrok-free.dev"

    @Test
    fun `valid fetched value wins`() {
        val url = AppStartupConfig.resolveEndpointValue(
            defaultUrl = default,
            cachedRaw = "https://cache.dev",
            fetchedRaw = "https://fetch.dev",
        )
        assertEquals("https://fetch.dev", url)
    }

    @Test
    fun `invalid fetched falls back to valid cache`() {
        val url = AppStartupConfig.resolveEndpointValue(
            defaultUrl = default,
            cachedRaw = "https://cache.dev",
            fetchedRaw = "ftp://bad",
        )
        assertEquals("https://cache.dev", url)
    }

    @Test
    fun `empty fetched preserves valid cache`() {
        // An empty/invalid fetch must NOT overwrite a valid cache.
        val url = AppStartupConfig.resolveEndpointValue(
            defaultUrl = default,
            cachedRaw = "https://cache.dev",
            fetchedRaw = "",
        )
        assertEquals("https://cache.dev", url)
    }

    @Test
    fun `blank fetched preserves valid cache`() {
        val url = AppStartupConfig.resolveEndpointValue(
            defaultUrl = default,
            cachedRaw = "https://cache.dev",
            fetchedRaw = "   ",
        )
        assertEquals("https://cache.dev", url)
    }

    @Test
    fun `nil fetched uses valid cache`() {
        val url = AppStartupConfig.resolveEndpointValue(
            defaultUrl = default,
            cachedRaw = "https://cache.dev",
            fetchedRaw = null,
        )
        assertEquals("https://cache.dev", url)
    }

    @Test
    fun `invalid fetched and invalid cache falls back to default`() {
        val url = AppStartupConfig.resolveEndpointValue(
            defaultUrl = default,
            cachedRaw = "   ",
            fetchedRaw = "ftp://bad",
        )
        assertEquals(default, url)
    }

    @Test
    fun `nil fetched and nil cache uses default`() {
        val url = AppStartupConfig.resolveEndpointValue(
            defaultUrl = default,
            cachedRaw = null,
            fetchedRaw = null,
        )
        assertEquals(default, url)
    }
}
