package com.aipose.auth

import com.aipose.data.PoseServiceLocator
import com.aipose.data.auth.SessionCredentials

/** Returns true while a backend-issued session is stored by the single token seam. */
fun hasValidStoredSession(): Boolean =
    PoseServiceLocator.sessionBoundary.tokenStorage.loadCredentials() != null

/**
 * Read-only confirmation that a stored session exists, for places that must not
 * trigger storage side effects or refresh flows (e.g. entry-point gating).
 */
fun peekStoredSession(): SessionCredentials? =
    PoseServiceLocator.sessionBoundary.tokenStorage.loadCredentials()