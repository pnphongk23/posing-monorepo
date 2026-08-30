package com.aipose.data

/**
 * FEAT-010 / DEC-006: the endpoint is runtime state now. The compiled value
 * remains the source default and the final fallback; the startup gate
 * (com.aipose.config.AppStartupConfig) overwrites both this holder and
 * PoseServiceLocator.baseUrl with one resolved Remote Config value before any
 * API-backed state is constructed.
 */
object AppConfig {
    var SERVER_BASE_URL = "https://pose-extract-server-production.up.railway.app"
}
