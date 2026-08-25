package com.aipose.navigation

import platform.UIKit.UIAccessibilityIsReduceMotionEnabled

/**
 * iOS implementation reading the system Reduce Motion accessibility preference.
 * Backed by the UIKit C helper without adding any theme/accessibility dependency.
 */
actual fun reducedMotionFromPlatform(): Boolean =
    UIAccessibilityIsReduceMotionEnabled()