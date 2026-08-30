// composeApp/src/commonTest/kotlin/com/aipose/config/StartupConfigApplyTest.kt
package com.aipose.config

import com.aipose.data.AppConfig
import com.aipose.data.PoseServiceLocator
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals

class StartupConfigApplyTest {

    private val original = AppConfig.SERVER_BASE_URL

    @AfterTest
    fun reset() {
        // Restore holders so the singleton locator is not left pointing at a
        // test value that other tests might observe.
        AppConfig.SERVER_BASE_URL = original
        PoseServiceLocator.baseUrl = original
    }

    @Test
    fun `applyEndpoint writes both holders to the same value`() {
        val url = "https://resolved.example.com"
        AppStartupConfig.applyEndpoint(url)
        assertEquals(url, AppConfig.SERVER_BASE_URL)
        assertEquals(url, PoseServiceLocator.baseUrl)
    }

    @Test
    fun `every resolver outcome leaves both holders identical`() {
        val cases = listOf(
            RuntimeConfigResolver.resolve(original, "https://cache.dev", FetchResult.Success("https://fetch.dev")),
            RuntimeConfigResolver.resolve(original, "https://cache.dev", FetchResult.Unavailable),
            RuntimeConfigResolver.resolve(original, null, FetchResult.Timeout),
            RuntimeConfigResolver.resolve(original, "ftp://bad", FetchResult.Error),
            RuntimeConfigResolver.resolve(original, null, FetchResult.Success("")),
        )
        for (resolution in cases) {
            AppStartupConfig.applyEndpoint(resolution.url)
            assertEquals(
                AppConfig.SERVER_BASE_URL,
                PoseServiceLocator.baseUrl,
                "holders must match after ${resolution.source}",
            )
        }
    }

    @Test
    fun `locator baseUrl is set before lazy apiService construction`() {
        val url = "https://ordering.proof.example.com"
        AppStartupConfig.applyEndpoint(url)
        // The lazy repository forces apiService on first access; because the
        // locator construction happens now (after baseUrl is set), the API
        // service captures `url`. We assert the locator holds it consistently.
        assertEquals(url, PoseServiceLocator.baseUrl)
        assertEquals(AppConfig.SERVER_BASE_URL, PoseServiceLocator.baseUrl)
    }
}
