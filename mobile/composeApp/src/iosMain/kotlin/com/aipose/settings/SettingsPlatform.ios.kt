package com.aipose.settings

import kotlinx.cinterop.ExperimentalForeignApi
import platform.AVFoundation.AVCaptureDevice
import platform.AVFoundation.AVAuthorizationStatusAuthorized
import platform.AVFoundation.AVAuthorizationStatusDenied
import platform.AVFoundation.AVAuthorizationStatusNotDetermined
import platform.AVFoundation.AVAuthorizationStatusRestricted
import platform.AVFoundation.AVMediaTypeVideo
import platform.AVFoundation.authorizationStatusForMediaType
import platform.Foundation.NSBundle
import platform.Foundation.NSURL
import platform.UIKit.UIApplication
import platform.UIKit.UIApplicationOpenSettingsURLString
import com.aipose.platform.LegalDocument

private const val SUPPORT_URL = "https://forms.gle/sample-aipose-feedback"

private fun openResult(didOpen: Boolean): SettingsDestinationResult =
    if (didOpen) {
        SettingsDestinationResult.Opened
    } else {
        SettingsDestinationResult.Failed(
            message = "The destination could not be opened.",
            retryable = true,
        )
    }

@OptIn(ExperimentalForeignApi::class)
actual fun platformSettingsPermissionReader(): SettingsPermissionReader =
    object : SettingsPermissionReader {
        override suspend fun read(permissionId: String): SettingsPermissionState {
            if (permissionId != "camera") {
                return SettingsPermissionState.Unavailable("Unknown permission")
            }
            return when (AVCaptureDevice.authorizationStatusForMediaType(AVMediaTypeVideo).toLong()) {
                AVAuthorizationStatusAuthorized -> SettingsPermissionState.Ready(PermissionStatus.Granted)
                AVAuthorizationStatusDenied -> SettingsPermissionState.Ready(PermissionStatus.Denied)
                AVAuthorizationStatusRestricted -> SettingsPermissionState.Ready(PermissionStatus.Restricted)
                AVAuthorizationStatusNotDetermined -> SettingsPermissionState.Unavailable("Permission not determined")
                else -> SettingsPermissionState.Failed(retryable = true)
            }
        }
    }

@OptIn(ExperimentalForeignApi::class)
actual fun platformSettingsActions(): SettingsPlatformActions =
    object : SettingsPlatformActions {
        override suspend fun openPlatformSettings(): SettingsDestinationResult {
            val url = NSURL.URLWithString(UIApplicationOpenSettingsURLString)
                ?: return SettingsDestinationResult.NotConfigured
            return openResult(UIApplication.sharedApplication.openURL(url))
        }

        override suspend fun openLegalDocument(document: LegalDocument): SettingsDestinationResult {
            val key = when (document) {
                LegalDocument.TERMS -> "LegalTermsURL"
                LegalDocument.PRIVACY -> "LegalPrivacyURL"
            }
            val rawUrl = NSBundle.mainBundle.objectForInfoDictionaryKey(key) as? String
            if (
                rawUrl.isNullOrBlank() ||
                rawUrl.startsWith("$(") ||
                rawUrl.contains("PLACEHOLDER", ignoreCase = true) ||
                rawUrl.contains("aipose.example.com", ignoreCase = true)
            ) {
                return SettingsDestinationResult.NotConfigured
            }
            val url = NSURL.URLWithString(rawUrl) ?: return SettingsDestinationResult.Failed(
                message = "The legal document URL is invalid.",
                retryable = false,
            )
            return openResult(UIApplication.sharedApplication.openURL(url))
        }

        override suspend fun openSupport(): SettingsDestinationResult {
            val url = NSURL.URLWithString(SUPPORT_URL) ?: return SettingsDestinationResult.NotConfigured
            return openResult(UIApplication.sharedApplication.openURL(url))
        }
    }
