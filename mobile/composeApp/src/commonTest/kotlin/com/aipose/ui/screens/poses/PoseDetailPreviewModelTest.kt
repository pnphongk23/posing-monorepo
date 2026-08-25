package com.aipose.ui.screens.poses

import kotlin.test.Test
import kotlin.test.assertEquals

class PoseDetailPreviewModelTest {
    @Test
    fun communityUsesThumbnailBeforeSkeleton() {
        val state = PoseDetailUiState.Success(
            name = "Pose",
            skeletonPath = "https://cdn.example/skeleton.png",
            thumbnailPath = "https://cdn.example/thumbnail.png",
            difficulty = null,
            author = null,
            isMine = false,
        )
        assertEquals("https://cdn.example/thumbnail.png", posePreviewModel(state))
    }

    @Test
    fun communityFallsBackToSkeletonWhenThumbnailMissing() {
        val state = PoseDetailUiState.Success(
            name = "Pose",
            skeletonPath = "https://cdn.example/skeleton.png",
            thumbnailPath = null,
            difficulty = null,
            author = null,
            isMine = false,
        )
        assertEquals("https://cdn.example/skeleton.png", posePreviewModel(state))
    }
}
