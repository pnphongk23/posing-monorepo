package com.aipose.purchases

import platform.Foundation.NSBundle
import platform.Foundation.NSProcessInfo
import kotlin.native.Platform

@OptIn(kotlin.experimental.ExperimentalNativeApi::class)
internal actual object AppEnvironment {
    actual val descriptor: AppEnvironmentDescriptor
        get() {
            val info = NSBundle.mainBundle.infoDictionary
            val environment = when (info?.get("AIPoseEnvironment") as? String) {
                AppEnvironmentName.DEV.name -> AppEnvironmentName.DEV
                else -> AppEnvironmentName.PROD
            }
            return AppEnvironmentDescriptor(
                name = environment,
                buildConfiguration = info?.get("AIPoseBuildConfiguration") as? String ?: "Unknown",
                isDebug = Platform.isDebugBinary,
            )
        }
}

@OptIn(kotlin.experimental.ExperimentalNativeApi::class)
internal actual val premiumTestBypassEnabled: Boolean =
    isPremiumBypassAllowed(
        environment = AppEnvironment.descriptor,
        runtimeFlag = NSProcessInfo.processInfo.environment["AIPOSE_BYPASS_PREMIUM"] as? String,
    )
