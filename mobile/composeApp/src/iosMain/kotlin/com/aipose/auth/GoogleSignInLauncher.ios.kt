package com.aipose.auth

import kotlinx.cinterop.BetaInteropApi
import platform.Foundation.NSNotificationCenter
import platform.Foundation.NSOperationQueue
import platform.Foundation.NSDictionary
import platform.darwin.NSObjectProtocol
import kotlin.native.concurrent.ThreadLocal

/**
 * Notification names for the Kotlin-to-Swift Google sign-in bridge.
 * Mirrors the existing app bridges (`com.aipose.revenuecat.request` /
 * `AIPoseCameraBridgeCommand`): Kotlin posts a request, the Swift host
 * (OAuthHandoff lane) performs ASWebAuthenticationSession and posts back a
 * response with a real success/failure payload. No launcher-local fake success.
 * The Swift observer is the separately-owned iosApp lane; until it observes,
 * the launcher stays pending (never reports success).
 */
object GoogleSignInBridgeNotifications {
    const val REQUEST = "com.aipose.google.signin.request"
    const val RESPONSE = "com.aipose.google.signin.response"
    const val KEY_RESULT = "result"       // "success" | "failure"
    const val KEY_MESSAGE = "message"     // failure detail
    const val KEY_BASE_URL = "baseUrl"    // request payload
}

/**
 * iOS actual: posts the Google sign-in request on the main queue and awaits a
 * response notification. Deliberately resolves ONLY on a real response — if the
 * host never observes, onResult is never invoked and the prompt stays in its
 * pending state (no fake success). Wire this by observing [GoogleSignInBridgeNotifications.RESPONSE]
 * on the Swift side and calling `OAuthHandoff.start` on [GoogleSignInBridgeNotifications.REQUEST].
 */
@OptIn(BetaInteropApi::class)
actual fun platformGoogleSignInLauncher(): GoogleSignInLauncher = IosGoogleSignInLauncher

@ThreadLocal
object IosGoogleSignInLauncher : GoogleSignInLauncher {
    private var pending: ((GoogleSignInResult) -> Unit)? = null

    override fun start(onResult: (GoogleSignInResult) -> Unit) {
        if (pending != null) {
            onResult(GoogleSignInResult.Failure("A sign-in request is already in progress."))
            return
        }
        pending = onResult
        var registered: NSObjectProtocol? = null
        registered = NSNotificationCenter.defaultCenter.addObserverForName(
            name = GoogleSignInBridgeNotifications.RESPONSE,
            `object` = null,
            queue = NSOperationQueue.mainQueue,
        ) { notification ->
            val info = notification?.userInfo as? NSDictionary
            val result = info?.objectForKey(GoogleSignInBridgeNotifications.KEY_RESULT) as? String
            val callback = pending
            pending = null
            registered?.let { NSNotificationCenter.defaultCenter.removeObserver(it) }
            callback?.invoke(
                when (result) {
                    "success" -> GoogleSignInResult.Success
                    else -> GoogleSignInResult.Failure(
                        info?.objectForKey(GoogleSignInBridgeNotifications.KEY_MESSAGE) as? String
                            ?: "Sign-in could not be completed."
                    )
                }
            )
        }
        NSNotificationCenter.defaultCenter.postNotificationName(
            aName = GoogleSignInBridgeNotifications.REQUEST,
            `object` = null,
            userInfo = mapOf(GoogleSignInBridgeNotifications.KEY_BASE_URL to com.aipose.data.PoseServiceLocator.baseUrl),
        )
    }
}