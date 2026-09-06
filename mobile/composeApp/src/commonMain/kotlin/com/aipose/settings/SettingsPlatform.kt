package com.aipose.settings

/** iOS-first settings ports; Android remains an explicit deferred target. */
expect fun platformSettingsPermissionReader(): SettingsPermissionReader

expect fun platformSettingsActions(): SettingsPlatformActions
