package com.aipose.data.auth

import android.content.Context
import android.content.SharedPreferences

// Android parity is out of scope for FEAT-013 v1 — dev-only.
private lateinit var applicationContext: Context

fun initializeAndroidTokenStorage(context: Context) {
    applicationContext = context.applicationContext
}

actual fun platformSecureTokenStorage(): SecureTokenStorage = SharedPreferencesTokenStorage {
    applicationContext.getSharedPreferences("ai_pose_session", Context.MODE_PRIVATE)
}

private class SharedPreferencesTokenStorage(
    private val preferences: () -> SharedPreferences,
) : SecureTokenStorage {
    override fun saveCredentials(credentials: SessionCredentials) {
        preferences().edit()
            .putString("access_token", credentials.accessToken)
            .putString("refresh_token", credentials.refreshToken)
            .apply()
    }

    override fun loadCredentials(): SessionCredentials? {
        val accessToken = preferences().getString("access_token", null)
        val refreshToken = preferences().getString("refresh_token", null)
        return if (accessToken != null && refreshToken != null) {
            SessionCredentials(accessToken, refreshToken)
        } else {
            null
        }
    }

    override fun clearCredentials() {
        preferences().edit()
            .remove("access_token")
            .remove("refresh_token")
            .apply()
    }
}
