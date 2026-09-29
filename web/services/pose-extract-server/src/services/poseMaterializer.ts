import type { CreatePoseInput, PoseDifficulty, PoseRecord } from "../db/communityStore";
import { logger } from "../utils/logger";

export interface MaterializePoseMetadata {
  name: string;
  tags?: string[];
  description?: string | null;
  bodyParts?: string[];
  difficulty?: PoseDifficulty | null;
}

export interface MediaStorage {
  put: (key: string, body: Buffer, mimeType: string) => Promise<void>;
  remove: (key: string) => Promise<void>;
  publicUrl: (key: string) => string;
}

export interface MaterializePoseOptions {
  poseId: string;
  ownerAccountId: string;
  currentJobId: string;
  metadata: MaterializePoseMetadata;
  source: { b64: string; mime: string };
  result: { b64: string; mime: string };
  keyPrefix: "community" | "poses";
  mediaStorage: MediaStorage;
  createPose: (input: CreatePoseInput) => Promise<PoseRecord>;
}

export function buildPoseObjectKey(
  keyPrefix: "community" | "poses",
  poseId: string,
  role: "original" | "skeleton" | "thumbnail",
  mimeType: string
): string {
  const subtype = mimeType.split("/")[1] || "bin";
  const ext = subtype.startsWith(".") ? subtype.toLowerCase() : `.${subtype.toLowerCase()}`;
  return `${keyPrefix}/${poseId}/${role}${ext}`;
}

/**
 * Materializes a Pose by uploading its 3 media assets (original, skeleton, thumbnail)
 * and invoking createPose. If any upload or createPose fails, all uploaded keys are
 * cleaned up via Promise.allSettled before the original error is rethrown.
 */
export async function materializePose(options: MaterializePoseOptions): Promise<PoseRecord> {
  const {
    poseId,
    ownerAccountId,
    currentJobId,
    metadata,
    source,
    result,
    keyPrefix,
    mediaStorage,
    createPose
  } = options;

  const assets = [
    { role: "original" as const, b64: source.b64, mime: source.mime },
    { role: "skeleton" as const, b64: result.b64, mime: result.mime },
    { role: "thumbnail" as const, b64: result.b64, mime: result.mime }
  ];

  const uploadedKeys: string[] = [];

  try {
    const locators = Object.fromEntries(
      await Promise.all(
        assets.map(async (asset) => {
          const fileKey = buildPoseObjectKey(keyPrefix, poseId, asset.role, asset.mime);
          const body = Buffer.from(asset.b64, "base64");
          await mediaStorage.put(fileKey, body, asset.mime);
          uploadedKeys.push(fileKey);
          return [asset.role, mediaStorage.publicUrl(fileKey)] as const;
        })
      )
    ) as Record<"original" | "skeleton" | "thumbnail", string>;

    const pose = await createPose({
      poseId,
      ownerAccountId,
      name: metadata.name,
      originalUrl: locators.original,
      skeletonUrl: locators.skeleton,
      thumbnailUrl: locators.thumbnail,
      tags: metadata.tags ?? [],
      difficulty: metadata.difficulty ?? null,
      description: metadata.description ?? null,
      bodyParts: metadata.bodyParts ?? [],
      currentJobId
    });

    return pose;
  } catch (error) {
    if (uploadedKeys.length > 0) {
      const results = await Promise.allSettled(uploadedKeys.map((key) => mediaStorage.remove(key)));
      for (let i = 0; i < results.length; i += 1) {
        const res = results[i];
        if (res?.status === "rejected") {
          logger.error({ fileKey: uploadedKeys[i], error: res.reason }, "failed to remove uploaded key during cleanup");
        }
      }
    }
    throw error;
  }
}
