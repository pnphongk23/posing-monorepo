// composeApp/src/commonTest/kotlin/com/aipose/config/RuntimeConfigResolverTest.kt
package com.aipose.config

import kotlin.test.Test
import kotlin.test.assertEquals

class RuntimeConfigResolverTest {

    private val default = "https://specked-unhelpful-dispatch.ngrok-free.dev"

    @Test
    fun `valid fetch wins over cache and default`() {
        val r = RuntimeConfigResolver.resolve(default, "https://cache.dev", FetchResult.Success("https://fetch.dev"))
        assertEquals("https://fetch.dev", r.url)
        assertEquals(EndpointSource.FETCH, r.source)
        assertEquals(FetchOutcome.APPLIED, r.outcome)
    }

    @Test
    fun `invalid fetch falls back to valid cache`() {
        val r = RuntimeConfigResolver.resolve(default, "https://cache.dev", FetchResult.Success("not a url"))
        assertEquals("https://cache.dev", r.url)
        assertEquals(EndpointSource.CACHE, r.source)
        assertEquals(FetchOutcome.EMPTY_OR_INVALID, r.outcome)
    }

    @Test
    fun `invalid fetch and invalid cache falls back to default`() {
        val r = RuntimeConfigResolver.resolve(default, "   ", FetchResult.Success("ftp://x"))
        assertEquals(default, r.url)
        assertEquals(EndpointSource.DEFAULT, r.source)
        assertEquals(FetchOutcome.EMPTY_OR_INVALID, r.outcome)
    }

    @Test
    fun `unavailable fetch uses cache`() {
        val r = RuntimeConfigResolver.resolve(default, "https://cache.dev", FetchResult.Unavailable)
        assertEquals("https://cache.dev", r.url)
        assertEquals(EndpointSource.CACHE, r.source)
        assertEquals(FetchOutcome.UNAVAILABLE, r.outcome)
    }

    @Test
    fun `unavailable fetch with no cache uses default`() {
        val r = RuntimeConfigResolver.resolve(default, null, FetchResult.Unavailable)
        assertEquals(default, r.url)
        assertEquals(EndpointSource.DEFAULT, r.source)
        assertEquals(FetchOutcome.UNAVAILABLE, r.outcome)
    }

    @Test
    fun `timeout uses cache`() {
        val r = RuntimeConfigResolver.resolve(default, "https://cache.dev", FetchResult.Timeout)
        assertEquals("https://cache.dev", r.url)
        assertEquals(EndpointSource.CACHE, r.source)
        assertEquals(FetchOutcome.TIMEOUT, r.outcome)
    }

    @Test
    fun `error uses default when cache invalid`() {
        val r = RuntimeConfigResolver.resolve(default, "ftp://bad", FetchResult.Error)
        assertEquals(default, r.url)
        assertEquals(EndpointSource.DEFAULT, r.source)
        assertEquals(FetchOutcome.ERROR, r.outcome)
    }

    @Test
    fun `empty fetch value falls back to default`() {
        val r = RuntimeConfigResolver.resolve(default, null, FetchResult.Success(""))
        assertEquals(default, r.url)
        assertEquals(EndpointSource.DEFAULT, r.source)
        assertEquals(FetchOutcome.EMPTY_OR_INVALID, r.outcome)
    }
}
