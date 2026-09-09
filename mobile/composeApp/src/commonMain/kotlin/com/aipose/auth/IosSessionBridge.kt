package com.aipose.auth

import com.aipose.data.PoseServiceLocator
import com.aipose.data.auth.SessionCredentials

/** Narrow native bridge: Swift persists backend-issued credentials through the shared boundary. */
fun persistSessionCredentials(accessToken: String, refreshToken: String) {
    PoseServiceLocator.sessionBoundary.saveCredentials(
        SessionCredentials(accessToken, refreshToken),
    )
}
