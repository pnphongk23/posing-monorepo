package com.aipose.data.auth

import kotlinx.serialization.Serializable

/** Stores the backend-issued session token without exposing platform storage details. */
@Serializable
data class SessionCredentials(
    val accessToken: String,
    val refreshToken: String,
)

interface SecureTokenStorage {
    fun saveCredentials(credentials: SessionCredentials)
    fun loadCredentials(): SessionCredentials?
    fun clearCredentials()
}

expect fun platformSecureTokenStorage(): SecureTokenStorage
