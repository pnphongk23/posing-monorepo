package com.aipose.ui.screens.poses

import androidx.compose.ui.unit.IntSize
import com.aipose.data.remote.CommunityPose
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Pure, platform-agnostic tests for the Community Coil slice: URL fallback for the
 * Coil model, deterministic bounded request sizing, and stable cache identity.
 * These mirror the behavior wired into CommunityPoseCard (resolveCommunityImageModel
 * -> ImageRequest.size, and the Coil derived data+size cache keying).
 */
class CommunityPoseImageModelTest {

    private fun pose(
        poseId: String = "p1",
        thumbnailUrl: String = "",
        skeletonUrl: String = "",
    ) = CommunityPose(poseId = poseId, thumbnailUrl = thumbnailUrl, skeletonUrl = skeletonUrl)

    // ---- URL fallback -------------------------------------------------------

    @Test
    fun urlFallbackPrefersThumbnailOverSkeleton() {
        val model = resolveCommunityImageModel(
            pose(thumbnailUrl = "https://cdn/thumb.png", skeletonUrl = "https://cdn/skel.png")
        )
        assertEquals("https://cdn/thumb.png", model)
    }

    @Test
    fun urlFallbackUsesSkeletonWhenThumbnailBlank() {
        val model = resolveCommunityImageModel(
            pose(thumbnailUrl = "   ", skeletonUrl = "https://cdn/skel.png")
        )
        assertEquals("https://cdn/skel.png", model)
    }

    @Test
    fun urlFallbackIsNullWhenBothBlank() {
        assertNull(resolveCommunityImageModel(pose(thumbnailUrl = "", skeletonUrl = "")))
        assertNull(resolveCommunityImageModel(pose()))
    }

    // ---- deterministic bounded request sizing -------------------------------

    @Test
    fun targetSizeIsExactlyTheDisplayedCell() {
        assertEquals(IntSize(150, 200), communityImageTargetSize(IntSize(150, 200)))
        assertEquals(IntSize(320, 180), communityImageTargetSize(IntSize(320, 180)))
    }

    @Test
    fun targetSizeNeverDegeneratesBelowOnePixel() {
        assertEquals(IntSize(1, 1), communityImageTargetSize(IntSize(0, 0)))
        assertEquals(IntSize(1, 50), communityImageTargetSize(IntSize(0, 50)))
        assertEquals(IntSize(60, 1), communityImageTargetSize(IntSize(60, -5)))
    }

    // ---- safe grid keys -------------------------------------------------------

    @Test
    fun gridKeyPrefersPoseId() {
        assertEquals("pose-9", communityPoseGridKey(pose(poseId = "pose-9"), index = 3))
    }

    @Test
    fun gridKeyFallsBackToUrlsWhenPoseIdBlank() {
        assertEquals(
            "https://cdn/thumb.png",
            communityPoseGridKey(
                pose(poseId = " ", thumbnailUrl = "https://cdn/thumb.png", skeletonUrl = "https://cdn/skel.png"),
                index = 7,
            )
        )
        assertEquals(
            "https://cdn/skel.png",
            communityPoseGridKey(
                pose(poseId = "", thumbnailUrl = "  ", skeletonUrl = "https://cdn/skel.png"),
                index = 7,
            )
        )
    }

    @Test
    fun gridKeyNeverBlankAndUniquePerIndexWhenAllIdsBlank() {
        val k0 = communityPoseGridKey(pose(poseId = "", thumbnailUrl = "", skeletonUrl = ""), index = 0)
        val k1 = communityPoseGridKey(pose(poseId = "", thumbnailUrl = "", skeletonUrl = ""), index = 1)
        assertFalse(k0.isBlank())
        assertFalse(k1.isBlank())
        assertNotEquals(k0, k1)
        assertTrue(k1.contains("1"))
        assertNotNull(k0)
    }
}