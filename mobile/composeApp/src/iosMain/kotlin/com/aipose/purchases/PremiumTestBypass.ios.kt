package com.aipose.purchases

import platform.Foundation.NSProcessInfo
import kotlin.native.Platform

@OptIn(kotlin.experimental.ExperimentalNativeApi::class)
internal actual val premiumTestBypassEnabled: Boolean =
    Platform.isDebugBinary && NSProcessInfo.processInfo.environment["AIPOSE_BYPASS_PREMIUM"] == "1"
