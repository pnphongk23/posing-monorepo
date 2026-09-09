package com.aipose.platform

import kotlinx.cinterop.ExperimentalForeignApi
import platform.Foundation.NSURL
import platform.UIKit.UIActivityViewController
import platform.UIKit.UIApplication
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine

@OptIn(ExperimentalForeignApi::class)
actual suspend fun openLegalDocument(document: LegalDocument): ExternalActionResult {
    val url = NSURL.URLWithString(LegalAuthority.canonicalUrl(document))
        ?: return ExternalActionResult.Failed(retryable = false)
    return suspendCoroutine { continuation ->
        UIApplication.sharedApplication.openURL(
            url = url,
            options = emptyMap<Any?, Any?>(),
            completionHandler = { didOpen ->
                continuation.resume(externalActionResult(didOpen))
            },
        )
    }
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
