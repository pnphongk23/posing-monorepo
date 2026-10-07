import type { PoseRecord } from "../db/communityStore";

/**
 * Public read projection shared by the community and saved lists. It excludes owner and job
 * metadata, and never exposes the field name `originalUrl`.
 *
 * `thumbnailUrl` is the card/hero image: clients show the source photo there, while `skeletonUrl`
 * stays the extracted line art used as the camera guide. The stored thumbnail asset (a copy of the
 * extraction) is intentionally not what this field serves.
 */
export function toPublicPose(pose: PoseRecord) {
  return {
    poseId: pose.poseId,
    name: pose.name,
    skeletonUrl: pose.skeletonUrl,
    thumbnailUrl: pose.originalUrl,
    tags: pose.tags,
    difficulty: pose.difficulty,
    description: pose.description,
    bodyParts: pose.bodyParts,
    status: "published" as const,
    uploadedAt: pose.createdAt,
    downloadCount: pose.downloadCount
  };
}
