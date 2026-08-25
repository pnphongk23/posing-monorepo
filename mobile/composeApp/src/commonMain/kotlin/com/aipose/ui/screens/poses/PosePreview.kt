package com.aipose.ui.screens.poses

import androidx.compose.ui.unit.Dp
import com.aipose.Pose
import com.aipose.data.remote.CommunityPose

/**
 * Lightweight, immutable preview carried on pose navigation so the destination
 * detail hero composes immediately and deterministically from the tapped card —
 * before, and independent of, the detail HTTP round-trip.
 *
 * The screen keeps the exact same [PosePreview.imageModel] the card rendered and
 * that the enriched detail reveals (see [posePreviewModel]), so the hero is
 * never replaced or flashed when the fetch completes — HTTP only enriches below it.
 *
 * Deliberately holds stable identifiers + crop metadata only (a remote URL /
 * resolved model, aspect ratio, corner radius) and NEVER a decoded bitmap.
 *
 * @param poseId        stable pose key; also drives the shared transition key `pose:<poseId>`.
 * @param name          display name, also used as the hero contentDescription.
 * @param imageModel    stable remote URL or resolved local model for the hero/thumbnail (null if none).
 * @param aspectRatio   width/height ratio of the source-card crop used to size the destination hero.
 * @param cornerRadius  corner radius metadata so the destination hero matches the card chrome.
 */
data class PosePreview(
    val poseId: String,
    val name: String,
    val imageModel: String?,
    val aspectRatio: Float,
    val cornerRadius: Dp,
) {
    /** Stable shared-transition key, kept aligned with `pose:<poseId>`. */
    val transitionKey: String get() = "pose:$poseId"
}

/**
 * Deterministic preview for a local library [Pose]. The image model is the same
 * resolved thumbnail the [PoseCard] renders (and that the detail re-resolves),
 * so the hero is identical pre- and post-enrichment (no flash).
 */
fun localPosePreview(
    pose: Pose,
    resolvedImage: String?,
    aspectRatio: Float,
    cornerRadius: Dp,
): PosePreview = PosePreview(
    poseId = pose.poseId,
    name = pose.name,
    imageModel = resolvedImage,
    aspectRatio = aspectRatio,
    cornerRadius = cornerRadius,
)

/**
 * Deterministic preview for a published [CommunityPose]. Uses the stable remote
 * thumbnail URL (falling back to the skeleton URL), never a local cache path or
 * a decoded bitmap — so it is stable across the detail fetch and matches the
 * enrich-time [posePreviewModel] projection (hero is never replaced/flashed).
 */
fun communityPosePreview(
    pose: CommunityPose,
    aspectRatio: Float,
    cornerRadius: Dp,
): PosePreview = PosePreview(
    poseId = pose.poseId,
    name = pose.name,
    imageModel = pose.thumbnailUrl.takeIf { it.isNotBlank() }
        ?: pose.skeletonUrl.takeIf { it.isNotBlank() },
    aspectRatio = aspectRatio,
    cornerRadius = cornerRadius,
)