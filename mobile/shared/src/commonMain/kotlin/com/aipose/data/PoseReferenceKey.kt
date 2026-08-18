package com.aipose.data

import kotlinx.serialization.Serializable

@Serializable
sealed class PoseReferenceKey {
    @Serializable
    data class Personal(val id: Long) : PoseReferenceKey()
    @Serializable
    data class Community(val id: String) : PoseReferenceKey()
}
