package com.aipose.ui.screens.poses

import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.unit.dp
import com.aipose.data.remote.CommunityPose
import com.aipose.navigation.MatchedImageTransitionState
import com.aipose.navigation.destinationChromeVisible
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Pose hero enter/readiness contract: the Loading (preview-first) -> Success hero
 * keeps the SAME canonical image model, the SAME stable transition key and the SAME
 * measured bounds (the persistent hero wrapper is never recreated), and Pose uses the
 * same unified destination-readiness rule as Gallery (no blank/spinner/stroke frame
 * behind/after the flyer).
 */
class PoseDetailHeroContractTest {

    private val pose = CommunityPose(
        poseId = "p1",
        name = "Pose",
        thumbnailUrl = "https://cdn.example/t.png",
        skeletonUrl = "https://cdn.example/s.png",
    )

    @Test
    fun poseHeroModelIsStableAcrossLoadingToSuccess() {
        val preview = communityPosePreview(pose = pose, aspectRatio = 1f, cornerRadius = 12.dp)
        val success = PoseDetailUiState.Success(
            name = "Pose",
            skeletonPath = "https://cdn.example/s.png",
            thumbnailPath = "https://cdn.example/t.png",
            difficulty = null,
            author = null,
            isMine = false,
            communityPose = pose,
        )

        // Loading uses the preview's canonical model (preview-first) ...
        assertEquals("https://cdn.example/t.png", poseHeroModel(PoseDetailUiState.Loading, preview))
        assertEquals(preview.imageModel, poseHeroModel(PoseDetailUiState.Loading, preview))
        // ... and Success uses the same canonical asset, so the hero is never replaced.
        assertEquals(preview.imageModel, poseHeroModel(success, preview))
        assertEquals(poseHeroModel(PoseDetailUiState.Loading, preview), poseHeroModel(success, preview))
    }

    @Test
    fun poseTransitionKeyIsStable() {
        val preview = communityPosePreview(pose = pose, aspectRatio = 1f, cornerRadius = 12.dp)
        assertEquals("pose:p1", preview.transitionKey)
        assertEquals("pose:p1", "pose:${pose.poseId}")
    }

    @Test
    fun poseAndGalleryReadinessUseTheSameUnifiedRule() {
        // No flight (IDLE): both are revealed only once media is painted.
        MatchedImageTransitionState.clear()
        assertFalse(destinationChromeVisible("pose:p1", mediaReady = false))
        assertTrue(destinationChromeVisible("pose:p1", mediaReady = true))
        // Same behavior for a photo key (parity).
        assertFalse(destinationChromeVisible("photo:p1", mediaReady = false))
        assertTrue(destinationChromeVisible("photo:p1", mediaReady = true))
        MatchedImageTransitionState.clear()
    }

    @Test
    fun poseReadinessHiddenMidFlightEvenIfMediaReady() {
        MatchedImageTransitionState.capture(
            "pose:p1", Rect(0f, 0f, 50f, 50f), imageModel = "https://cdn.example/t.png", cornerRadius = 12.dp
        )
        // While the flyer covers this destination, chrome stays hidden even if loaded.
        assertFalse(destinationChromeVisible("pose:p1", mediaReady = true))
        MatchedImageTransitionState.clear()
        assertTrue(destinationChromeVisible("pose:p1", mediaReady = true))
        MatchedImageTransitionState.clear()
    }
}
