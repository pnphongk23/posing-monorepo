package com.aipose.platform

import kotlinx.cinterop.ExperimentalForeignApi
import platform.Foundation.NSBundle
import platform.Foundation.NSURL
import platform.UIKit.UIActivityViewController
import platform.UIKit.UIApplication

@OptIn(ExperimentalForeignApi::class)
actual fun openLegalDocument(document: LegalDocument) {
    val key = when (document) {
        LegalDocument.TERMS -> "LegalTermsURL"
        LegalDocument.PRIVACY -> "LegalPrivacyURL"
      }
      val rawUrl = NSBundle.mainBundle.objectForInfoDictionaryKey(key) as? String ?: return
      if (rawUrl.isBlank() || rawUrl.contains("aipose.example.com", ignoreCase = true) || rawUrl.contains("PLACEHOLDER", ignoreCase = true) || rawUrl.startsWith("$(")) return
      val url = NSURL.URLWithString(rawUrl) ?: return
    UIApplication.sharedApplication.openURL(url)
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
