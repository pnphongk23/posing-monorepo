package com.aipose.data.remote

class PoseApiException(val code: String, message: String) : Exception(message)

/**
 * Single 401 policy: the backend may surface any of these code variants for a
 * missing/invalid/expired/cross-account session (envelope code or bare status).
 * All Saved + detail entry points must treat these consistently as sign-in-required
 * and must never degrade to an inline generic error as the only response.
 */
val UNAUTHORIZED_CODES: Set<String> = setOf("UNAUTHORIZED", "401", "AUTH_FAILED")

fun isUnauthorizedCode(code: String?): Boolean = code != null && code in UNAUTHORIZED_CODES

fun PoseApiException.isUnauthorized(): Boolean = isUnauthorizedCode(code)
