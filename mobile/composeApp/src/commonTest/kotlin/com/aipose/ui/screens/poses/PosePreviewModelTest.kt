package com.aipose.ui.screens.poses

import com.aipose.Pose
import com.aipose.data.remote.CommunityPose
import com.aipose.ui.theme.CornerRadius
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * Focused, deterministic tests for preview-first navigation + the detail model:
 * the lightweight [PosePreview] carried on navigation carries stable URL/model +
 * aspect + corner metadata (never a bitmap), and its [PosePreview.imageModel]
 * exactly matches the enrich-time [posePreviewModel] projection so the detail
 * hero is never replaced or flashed when the HTTP fetch completes.
 */
class PosePreviewModelTest {

    private val thumbnailUrl = "https://cdn.example/thumbnail.png"
    private val skeletonUrl = "https://cdn.example/skeleton.png"

    private fun localPose(thumbnailPath: String = thumbnailUrl): Pose = Pose(
        poseId = "pose-local-1",
        ownerAccountId = "acc-1",
        name = "Pose Alpha",
        description = null,
        tags = "[]",
        difficulty = "beginner",
        bodyParts = "full_body",
        status = "local",
        originalPath = "/orig.png",
        skeletonPath = skeletonUrl,
        thumbnailPath = thumbnailPath,
        currentJobId = null,
        createdAt = "2026-08-01",
        updatedAt = "2026-08-01",
    )

    @Test
    fun localPreviewCarriesStableFieldsAndTransitionKey() {
        val preview = localPosePreview(
            pose = localPose(),
            resolvedImage = "/resolved/thumb.png",
            aspectRatio = 1f,
            cornerRadius = CornerRadius.md,
        )
        assertEquals("pose-local-1", preview.poseId)
        assertEquals("Pose Alpha", preview.name)
        assertEquals("/resolved/thumb.png", preview.imageModel)
        assertEquals(1f, preview.aspectRatio)
        assertEquals(CornerRadius.md, preview.cornerRadius)
        assertEquals("pose:pose-local-1", preview.transitionKey)
    }

    @Test
    fun localPreviewWithNoImageKeepsIdentifierButNullModel() {
        val preview = localPosePreview(
            pose = localPose(thumbnailPath = "  "),
            resolvedImage = null,
            aspectRatio = 0.8f,
            cornerRadius = CornerRadius.md,
        )
        assertEquals("pose-local-1", preview.poseId)
        assertEquals("Pose Alpha", preview.name)
        assertNull(preview.imageModel)
        assertEquals("pose:pose-local-1", preview.transitionKey)
    }

    @Test
    fun communityPreviewPrefersThumbnailThenSkeletonUrl() {
        val pose = CommunityPose(
            poseId = "pose-pub-9",
            name = "Rising Sun",
            skeletonUrl = skeletonUrl,
            thumbnailUrl = thumbnailUrl,
        )
        val preview = communityPosePreview(pose, aspectRatio = 1f, cornerRadius = CornerRadius.md)
        assertEquals("pose-pub-9", preview.poseId)
        assertEquals(thumbnailUrl, preview.imageModel)
        assertEquals("pose:pose-pub-9", preview.transitionKey)

        val noThumb = pose.copy(thumbnailUrl = "")
        val previewFallback = communityPosePreview(noThumb, aspectRatio = 1f, cornerRadius = CornerRadius.md)
        assertEquals(skeletonUrl, previewFallback.imageModel)
    }

    // ── No-flash determinism: preview model == enrich-time posePreviewModel ──

    @Test
    fun communityPreviewMatchesDetailProjectionExactly() {
        val pose = CommunityPose(
            poseId = "pose-pub-9",
            name = "Rising Sun",
            skeletonUrl = skeletonUrl,
            thumbnailUrl = thumbnailUrl,
        )
        val preview = communityPosePreview(pose, aspectRatio = 1f, cornerRadius = CornerRadius.md)
        val enriched = PoseDetailUiState.Success(
            name = pose.name,
            skeletonPath = pose.skeletonUrl,
            thumbnailPath = pose.thumbnailUrl,
            difficulty = null,
            author = null,
            isMine = false,
            communityPose = pose,
        )
        // Identical model pre- and post-enrichment => hero never replaced/flashed.
        assertEquals(posePreviewModel(enriched), preview.imageModel)
        assertEquals(thumbnailUrl, posePreviewModel(enriched))
    }

    @Test
    fun communityPreviewFallbackMatchesDetailSkeletonProjection() {
        val pose = CommunityPose(
            poseId = "pose-pub-9",
            name = "Rising Sun",
            skeletonUrl = skeletonUrl,
            thumbnailUrl = "",
        )
        val preview = communityPosePreview(pose, aspectRatio = 1f, cornerRadius = CornerRadius.md)
        val enriched = PoseDetailUiState.Success(
            name = pose.name,
            skeletonPath = pose.skeletonUrl,
            thumbnailPath = "",
            difficulty = null,
            author = null,
            isMine = false,
            communityPose = pose,
        )
        assertEquals(skeletonUrl, preview.imageModel)
        assertEquals(posePreviewModel(enriched), preview.imageModel)
    }

    @Test
    fun localPreviewResolvedModelMatchesDetailProjection() {
        val pose = localPose(thumbnailPath = thumbnailUrl)
        val resolved = com.aipose.data.resolveImagePath(pose.thumbnailPath) ?: pose.thumbnailPath
        val preview = localPosePreview(pose, resolvedImage = resolved, aspectRatio = 1f, cornerRadius = CornerRadius.md)
        val enriched = PoseDetailUiState.Success(
            name = pose.name,
            skeletonPath = pose.skeletonPath,
            thumbnailPath = pose.thumbnailPath,
            difficulty = pose.difficulty,
            author = pose.ownerAccountId,
            isMine = true,
            pose = pose,
        )
        assertEquals(posePreviewModel(enriched), preview.imageModel)
    }
}