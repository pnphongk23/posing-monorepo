package com.aipose.platform

import kotlinx.cinterop.ExperimentalForeignApi
import platform.Foundation.NSURL
import platform.UIKit.UIActivityViewController
import platform.UIKit.UIApplication

@OptIn(ExperimentalForeignApi::class)
actual suspend fun openLegalDocument(document: LegalDocument): ExternalActionResult {
    val url = NSURL.URLWithString(LegalAuthority.canonicalUrl(document))
        ?: return ExternalActionResult.Failed(retryable = false)
    return externalActionResult(UIApplication.sharedApplication.openURL(url))
}

@OptIn(ExperimentalForeignApi::class)
actual fun shareImage(imagePath: String, context: Any?) {
    val controller = UIActivityViewController(
        activityItems = listOf(NSURL.fileURLWithPath(imagePath)),
        applicationActivities = null,
    )
    UIApplication.sharedApplication.keyWindow?.rootViewController
        ?.presentViewController(controller, animated = true, completion = null)
}
