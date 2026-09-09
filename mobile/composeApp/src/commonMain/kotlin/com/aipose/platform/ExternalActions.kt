package com.aipose.platform

enum class LegalDocument { TERMS, PRIVACY }

sealed interface ExternalActionResult {
    data object Opened : ExternalActionResult
    data object NotConfigured : ExternalActionResult
    data class Failed(val retryable: Boolean) : ExternalActionResult
}

/** Canonical legal destinations for the current Google Sites legal pages. */
object LegalAuthority {
    const val TERMS_URL = "https://sites.google.com/view/snappose/terms-of-service"
    const val PRIVACY_URL = "https://sites.google.com/view/snappose/privacy-policy"

    fun canonicalUrl(document: LegalDocument): String = when (document) {
        LegalDocument.TERMS -> TERMS_URL
        LegalDocument.PRIVACY -> PRIVACY_URL
    }
}

/** Maps a native open-URL success flag into the platform action result. */
fun externalActionResult(didOpen: Boolean): ExternalActionResult =
    if (didOpen) {
        ExternalActionResult.Opened
    } else {
        ExternalActionResult.Failed(retryable = true)
    }

/** Host/platform actions using code-owned canonical legal destinations. */
expect suspend fun openLegalDocument(document: LegalDocument): ExternalActionResult

/** Presents the platform share UI for an already-authorized image action. */
expect fun shareImage(imagePath: String, context: Any?)
