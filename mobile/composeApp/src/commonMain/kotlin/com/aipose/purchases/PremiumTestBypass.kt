package com.aipose.purchases

internal expect val premiumTestBypassEnabled: Boolean

internal enum class AppEnvironmentName {
    DEV,
    PROD,
}

internal data class AppEnvironmentDescriptor(
    val name: AppEnvironmentName,
    val buildConfiguration: String,
    val isDebug: Boolean,
)

internal expect object AppEnvironment {
    val descriptor: AppEnvironmentDescriptor
}

internal fun isPremiumBypassAllowed(
    environment: AppEnvironmentDescriptor,
    runtimeFlag: String?,
): Boolean = environment.name == AppEnvironmentName.DEV && environment.isDebug && runtimeFlag == "1"
