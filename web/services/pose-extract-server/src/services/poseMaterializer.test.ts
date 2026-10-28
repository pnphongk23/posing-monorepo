import { describe, expect, it, vi } from "vitest";

import type { CreatePoseInput, PoseRecord } from "../db/communityStore";
import { logger } from "../utils/logger";
import { buildPoseObjectKey, materializePose, type MediaStorage } from "./poseMaterializer";

function createFakePoseRecord(input: CreatePoseInput): PoseRecord {
  return {
    poseId: input.poseId ?? "mock-pose-id",
    ownerAccountId: input.ownerAccountId,
    name: input.name,
    originalUrl: input.originalUrl,
    skeletonUrl: input.skeletonUrl,
    thumbnailUrl: input.thumbnailUrl,
    tags: input.tags,
    difficulty: input.difficulty,
    description: input.description,
    bodyParts: input.bodyParts,
    status: "local",
    currentJobId: input.currentJobId ?? null,
    createdAt: "2026-09-26T00:00:00.000Z",
    updatedAt: "2026-09-26T00:00:00.000Z",
    downloadCount: 0
  };
}

describe("buildPoseObjectKey", () => {
  it("formats key correctly for community and poses prefixes", () => {
    expect(buildPoseObjectKey("community", "pose-123", "original", "image/jpeg")).toBe(
      "community/pose-123/original.jpeg"
    );
    expect(buildPoseObjectKey("poses", "pose-456", "skeleton", "image/png")).toBe(
      "poses/pose-456/skeleton.png"
    );
    expect(buildPoseObjectKey("poses", "pose-456", "thumbnail", "image/webp")).toBe(
      "poses/pose-456/thumbnail.webp"
    );
  });
});

describe("materializePose", () => {
  it("uploads 3 assets, invokes createPose, and returns the pose record", async () => {
    const uploaded: Record<string, { body: Buffer; mimeType: string }> = {};
    const mediaStorage: MediaStorage = {
      put: vi.fn(async (key: string, body: Buffer, mimeType: string) => {
        uploaded[key] = { body, mimeType };
      }),
      remove: vi.fn(async () => undefined),
      publicUrl: (key: string) => `https://cdn.example.com/${key}`
    };

    let capturedCreateInput: CreatePoseInput | null = null;
    const createPose = vi.fn(async (input: CreatePoseInput) => {
      capturedCreateInput = input;
      return createFakePoseRecord(input);
    });

    const result = await materializePose({
      poseId: "pose-uuid-1",
      ownerAccountId: "owner-uuid-1",
      currentJobId: "job-uuid-1",
      metadata: {
        name: "Warrior Pose",
        tags: ["standing", "yoga"],
        description: "A great pose",
        bodyParts: ["arms", "legs"],
        difficulty: "intermediate"
      },
      source: { b64: Buffer.from("source-bytes").toString("base64"), mime: "image/jpeg" },
      result: { b64: Buffer.from("result-bytes").toString("base64"), mime: "image/png" },
      keyPrefix: "poses",
      mediaStorage,
      createPose
    });

    expect(result.poseId).toBe("pose-uuid-1");
    expect(result.name).toBe("Warrior Pose");
    expect(mediaStorage.put).toHaveBeenCalledTimes(3);
    expect(mediaStorage.remove).not.toHaveBeenCalled();
    expect(createPose).toHaveBeenCalledTimes(1);

    expect(capturedCreateInput).toMatchObject({
      poseId: "pose-uuid-1",
      ownerAccountId: "owner-uuid-1",
      name: "Warrior Pose",
      originalUrl: "https://cdn.example.com/poses/pose-uuid-1/original.jpeg",
      skeletonUrl: "https://cdn.example.com/poses/pose-uuid-1/skeleton.png",
      thumbnailUrl: "https://cdn.example.com/poses/pose-uuid-1/thumbnail.png",
      tags: ["standing", "yoga"],
      description: "A great pose",
      bodyParts: ["arms", "legs"],
      difficulty: "intermediate",
      currentJobId: "job-uuid-1"
    });
  });

  it("applies default metadata values when optional fields omitted", async () => {
    const mediaStorage: MediaStorage = {
      put: vi.fn(async () => undefined),
      remove: vi.fn(async () => undefined),
      publicUrl: (key: string) => `https://cdn.example.com/${key}`
    };

    let capturedInput: CreatePoseInput | null = null;
    const createPose = vi.fn(async (input: CreatePoseInput) => {
      capturedInput = input;
      return createFakePoseRecord(input);
    });

    await materializePose({
      poseId: "pose-uuid-2",
      ownerAccountId: "owner-uuid-2",
      currentJobId: "job-uuid-2",
      metadata: {
        name: "Default Pose"
      },
      source: { b64: "c291cmNl", mime: "image/png" },
      result: { b64: "cmVzdWx0", mime: "image/png" },
      keyPrefix: "community",
      mediaStorage,
      createPose
    });

    expect(capturedInput).toMatchObject({
      name: "Default Pose",
      tags: [],
      difficulty: null,
      description: null,
      bodyParts: []
    });
  });

  it("cleans up uploaded keys and rethrows when an upload fails", async () => {
    const uploadedKeys: string[] = [];
    const mediaStorage: MediaStorage = {
      put: vi.fn(async (key: string) => {
        if (key.includes("thumbnail")) {
          throw new Error("R2 upload timeout");
        }
        uploadedKeys.push(key);
      }),
      remove: vi.fn(async (_key: string) => undefined),
      publicUrl: (key: string) => `https://cdn.example.com/${key}`
    };

    const createPose = vi.fn(async (input: CreatePoseInput) => createFakePoseRecord(input));

    await expect(
      materializePose({
        poseId: "pose-uuid-3",
        ownerAccountId: "owner-uuid-3",
        currentJobId: "job-uuid-3",
        metadata: { name: "Failing Upload Pose" },
        source: { b64: "c291cmNl", mime: "image/png" },
        result: { b64: "cmVzdWx0", mime: "image/png" },
        keyPrefix: "poses",
        mediaStorage,
        createPose
      })
    ).rejects.toThrow("R2 upload timeout");

    expect(createPose).not.toHaveBeenCalled();
    expect(mediaStorage.remove).toHaveBeenCalled();
  });

  it("cleans up all 3 uploaded keys and rethrows when createPose fails", async () => {
    const removedKeys: string[] = [];
    const mediaStorage: MediaStorage = {
      put: vi.fn(async () => undefined),
      remove: vi.fn(async (key: string) => {
        removedKeys.push(key);
      }),
      publicUrl: (key: string) => `https://cdn.example.com/${key}`
    };

    const dbError = new Error("Database transaction failed");
    const createPose = vi.fn(async () => {
      throw dbError;
    });

    await expect(
      materializePose({
        poseId: "pose-uuid-4",
        ownerAccountId: "owner-uuid-4",
        currentJobId: "job-uuid-4",
        metadata: { name: "DB Fail Pose" },
        source: { b64: "c291cmNl", mime: "image/png" },
        result: { b64: "cmVzdWx0", mime: "image/png" },
        keyPrefix: "poses",
        mediaStorage,
        createPose
      })
    ).rejects.toThrow("Database transaction failed");

    expect(removedKeys).toHaveLength(3);
    expect(removedKeys).toContain("poses/pose-uuid-4/original.png");
    expect(removedKeys).toContain("poses/pose-uuid-4/skeleton.png");
    expect(removedKeys).toContain("poses/pose-uuid-4/thumbnail.png");
  });

  it("still rethrows the original error even if mediaStorage.remove fails during cleanup", async () => {
    const mediaStorage: MediaStorage = {
      put: vi.fn(async () => undefined),
      remove: vi.fn(async () => {
        throw new Error("R2 delete failed");
      }),
      publicUrl: (key: string) => `https://cdn.example.com/${key}`
    };

    const originalError = new Error("Original DB failure");
    const createPose = vi.fn(async () => {
      throw originalError;
    });

    await expect(
      materializePose({
        poseId: "pose-uuid-5",
        ownerAccountId: "owner-uuid-5",
        currentJobId: "job-uuid-5",
        metadata: { name: "Cleanup Fail Pose" },
        source: { b64: "c291cmNl", mime: "image/png" },
        result: { b64: "cmVzdWx0", mime: "image/png" },
        keyPrefix: "poses",
        mediaStorage,
        createPose
      })
    ).rejects.toThrow("Original DB failure");
  });

  it("waits for every upload to settle before cleanup, so a late sibling key is not orphaned", async () => {
    const removedKeys: string[] = [];
    const resolvers: Array<() => void> = [];

    const mediaStorage: MediaStorage = {
      put: vi.fn(async (key: string) => {
        if (key.includes("thumbnail")) {
          throw new Error("R2 upload timeout");
        }
        await new Promise<void>((resolve) => {
          resolvers.push(resolve);
        });
      }),
      remove: vi.fn(async (key: string) => {
        removedKeys.push(key);
      }),
      publicUrl: (key: string) => `https://cdn.example.com/${key}`
    };

    const promise = materializePose({
      poseId: "pose-race",
      ownerAccountId: "owner-race",
      currentJobId: "job-race",
      metadata: { name: "Race Pose" },
      source: { b64: "c291cmNl", mime: "image/png" },
      result: { b64: "cmVzdWx0", mime: "image/png" },
      keyPrefix: "poses",
      mediaStorage,
      createPose: vi.fn(async (input: CreatePoseInput) => createFakePoseRecord(input))
    });

    // The rejecting upload settles immediately; the two others stay in flight.
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(resolvers).toHaveLength(2);

    resolvers[0]?.();
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(removedKeys).toHaveLength(0);

    resolvers[1]?.();
    await expect(promise).rejects.toThrow("R2 upload timeout");

    expect(removedKeys.sort()).toEqual(["poses/pose-race/original.png", "poses/pose-race/skeleton.png"]);
  });

  it("reports exactly the keys whose cleanup failed", async () => {
    const mediaStorage: MediaStorage = {
      put: vi.fn(async () => undefined),
      remove: vi.fn(async (key: string) => {
        if (key.includes("skeleton")) throw new Error("R2 delete failed");
      }),
      publicUrl: (key: string) => `https://cdn.example.com/${key}`
    };

    const onCleanupFailed = vi.fn(async () => undefined);

    await expect(
      materializePose({
        poseId: "pose-cleanup-report",
        ownerAccountId: "owner-cleanup-report",
        currentJobId: "job-cleanup-report",
        metadata: { name: "Cleanup Report" },
        source: { b64: "c291cmNl", mime: "image/png" },
        result: { b64: "cmVzdWx0", mime: "image/png" },
        keyPrefix: "poses",
        mediaStorage,
        onCleanupFailed,
        createPose: vi.fn(async () => {
          throw new Error("job already gone");
        })
      })
    ).rejects.toThrow("job already gone");

    expect(onCleanupFailed).toHaveBeenCalledTimes(1);
    expect(onCleanupFailed).toHaveBeenCalledWith(["poses/pose-cleanup-report/skeleton.png"]);
  });

  it("logs the owner, job, and failure count instead of any object key", async () => {
    const mediaStorage: MediaStorage = {
      put: vi.fn(async () => undefined),
      remove: vi.fn(async (key: string) => {
        if (key.includes("skeleton")) throw new Error("R2 delete failed");
      }),
      publicUrl: (key: string) => `https://cdn.example.com/${key}`
    };
    const logged: unknown[][] = [];
    const errorSpy = vi.spyOn(logger, "error").mockImplementation((...args: unknown[]) => {
      logged.push(args);
      return undefined as never;
    });

    try {
      await expect(
        materializePose({
          poseId: "pose-quiet",
          ownerAccountId: "owner-quiet",
          currentJobId: "job-quiet",
          metadata: { name: "Quiet" },
          source: { b64: "c291cmNl", mime: "image/png" },
          result: { b64: "cmVzdWx0", mime: "image/png" },
          keyPrefix: "poses",
          mediaStorage,
          createPose: vi.fn(async () => {
            throw new Error("job already gone");
          })
        })
      ).rejects.toThrow("job already gone");

      const serialized = JSON.stringify(logged);
      expect(serialized).not.toMatch(/poses\//);
      expect(serialized).not.toMatch(/\.png/);
      expect(serialized).toContain("owner-quiet");
      expect(serialized).toContain("job-quiet");
    } finally {
      errorSpy.mockRestore();
    }
  });

  it("does not call onCleanupFailed when every removal succeeds", async () => {
    const mediaStorage: MediaStorage = {
      put: vi.fn(async () => undefined),
      remove: vi.fn(async () => undefined),
      publicUrl: (key: string) => `https://cdn.example.com/${key}`
    };
    const onCleanupFailed = vi.fn(async () => undefined);

    await expect(
      materializePose({
        poseId: "pose-cleanup-ok",
        ownerAccountId: "owner-cleanup-ok",
        currentJobId: "job-cleanup-ok",
        metadata: { name: "Cleanup Ok" },
        source: { b64: "c291cmNl", mime: "image/png" },
        result: { b64: "cmVzdWx0", mime: "image/png" },
        keyPrefix: "poses",
        mediaStorage,
        onCleanupFailed,
        createPose: vi.fn(async () => {
          throw new Error("create failed");
        })
      })
    ).rejects.toThrow("create failed");

    expect(onCleanupFailed).not.toHaveBeenCalled();
  });

  it("leaves uploaded objects alone when the caller owns the cleanup", async () => {
    const removed: string[] = [];
    const mediaStorage: MediaStorage = {
      put: vi.fn(async () => undefined),
      remove: vi.fn(async (key: string) => {
        removed.push(key);
      }),
      publicUrl: (key: string) => `https://cdn.example.com/${key}`
    };

    await expect(
      materializePose({
        poseId: "pose-owned-cleanup",
        ownerAccountId: "owner-owned-cleanup",
        currentJobId: "job-owned-cleanup",
        metadata: { name: "Owned Cleanup" },
        source: { b64: "c291cmNl", mime: "image/png" },
        result: { b64: "cmVzdWx0", mime: "image/png" },
        keyPrefix: "poses",
        mediaStorage,
        removeUploadedOnFailure: false,
        createPose: vi.fn(async () => {
          throw new Error("finalize rolled back");
        })
      })
    ).rejects.toThrow("finalize rolled back");

    expect(removed).toEqual([]);
  });
});