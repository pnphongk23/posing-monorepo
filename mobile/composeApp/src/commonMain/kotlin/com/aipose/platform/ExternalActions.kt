package com.aipose.platform

enum class LegalDocument { TERMS, PRIVACY }

/** Host/platform actions; destinations are injected by the native host. */
expect fun openLegalDocument(document: LegalDocument)

/** Presents the platform share UI for an already-authorized image action. */
expect fun shareImage(imagePath: String, context: Any?)
