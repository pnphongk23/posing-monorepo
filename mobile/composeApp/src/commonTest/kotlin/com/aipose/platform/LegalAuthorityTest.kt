package com.aipose.platform

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class LegalAuthorityTest {
    @Test
    fun `canonical terms url matches FEAT-015 authority`() {
        assertEquals("https://aipose.app/terms", LegalAuthority.canonicalUrl(LegalDocument.TERMS))
        assertEquals("https://aipose.app/terms", LegalAuthority.TERMS_URL)
    }

    @Test
    fun `canonical privacy url matches FEAT-015 authority`() {
        assertEquals("https://aipose.app/privacy", LegalAuthority.canonicalUrl(LegalDocument.PRIVACY))
        assertEquals("https://aipose.app/privacy", LegalAuthority.PRIVACY_URL)
    }

    @Test
    fun `external action result maps native boolean to platform result`() {
        assertEquals(ExternalActionResult.Opened, externalActionResult(true))
        val failed = externalActionResult(false)
        assertTrue(failed is ExternalActionResult.Failed)
        assertTrue(failed.retryable)
    }
}
