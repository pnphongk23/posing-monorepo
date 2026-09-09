package com.aipose.platform

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class LegalAuthorityTest {
    @Test
    fun `canonical terms url matches Google Sites authority`() {
        assertEquals("https://sites.google.com/view/snappose/terms-of-service", LegalAuthority.canonicalUrl(LegalDocument.TERMS))
        assertEquals("https://sites.google.com/view/snappose/terms-of-service", LegalAuthority.TERMS_URL)
    }

    @Test
    fun `canonical privacy url matches Google Sites authority`() {
        assertEquals("https://sites.google.com/view/snappose/privacy-policy", LegalAuthority.canonicalUrl(LegalDocument.PRIVACY))
        assertEquals("https://sites.google.com/view/snappose/privacy-policy", LegalAuthority.PRIVACY_URL)
    }

    @Test
    fun `external action result maps native boolean to platform result`() {
        assertEquals(ExternalActionResult.Opened, externalActionResult(true))
        val failed = externalActionResult(false)
        assertTrue(failed is ExternalActionResult.Failed)
        assertTrue(failed.retryable)
    }
}
