import { DeleteObjectCommand, GetObjectCommand, HeadObjectCommand, PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("@aws-sdk/s3-request-presigner", () => ({
  getSignedUrl: vi.fn()
}));

vi.mock("@aws-sdk/client-s3", () => {
  const send = vi.fn();
  return {
    S3Client: vi.fn(function S3Client() {
      return { send };
    }),
    HeadObjectCommand: function HeadObjectCommand(input: unknown) {
      return { input };
    },
    PutObjectCommand: function PutObjectCommand(input: unknown) {
      return { input };
    },
    GetObjectCommand: function GetObjectCommand(input: unknown) {
      return { input };
    },
    DeleteObjectCommand: function DeleteObjectCommand(input: unknown) {
      return { input };
    }
  };
});

vi.mock("../config/env", () => ({
  getEnv: vi.fn().mockReturnValue({
    R2_ACCOUNT_ID: "test-account",
    R2_ACCESS_KEY_ID: "test-key-id",
    R2_SECRET_ACCESS_KEY: "test-secret",
    R2_BUCKET: "test-bucket",
    R2_PUBLIC_URL: "https://cdn.example.com"
  })
}));

import {
  buildCommunityObjectKey,
  buildPublicUrl,
  createUploadUrl,
  deleteObject,
  getObject,
  getR2Client,
  objectExists,
  uploadObject
} from "./r2Storage";

const s3Module = await vi.importMock<typeof import("@aws-sdk/client-s3")>("@aws-sdk/client-s3");
const stubClient = new s3Module.S3Client({} as never);
const stubSend = vi.mocked(stubClient.send);

describe("r2Storage", () => {
  beforeEach(() => {
    vi.mocked(getSignedUrl).mockReset();
    stubSend.mockReset();
  });

  describe("buildPublicUrl", () => {
    it("joins base and fileKey with a single slash", () => {
      expect(buildPublicUrl("https://cdn.example.com", "community/a.png")).toBe(
        "https://cdn.example.com/community/a.png"
      );
    });

    it("trims trailing slash from base and leading slash from fileKey", () => {
      expect(buildPublicUrl("https://cdn.example.com/", "/community/a.png")).toBe(
        "https://cdn.example.com/community/a.png"
      );
    });
  });

  describe("getR2Client", () => {
    it("configures the R2 endpoint and credentials", () => {
      getR2Client();
      expect(s3Module.S3Client).toHaveBeenCalledWith({
        region: "auto",
        endpoint: "https://test-account.r2.cloudflarestorage.com",
        credentials: { accessKeyId: "test-key-id", secretAccessKey: "test-secret" }
      });
    });
  });

  describe("buildCommunityObjectKey", () => {
    it("creates deterministic canonical role keys", () => {
      expect(buildCommunityObjectKey("skeleton", ".PNG", "pose-123")).toBe(
        "community/pose-123/skeleton.png"
      );
    });
  });

  describe("createUploadUrl", () => {
    it("returns uploadUrl and fileKey from presigned PUT", async () => {
      vi.mocked(getSignedUrl).mockResolvedValue("https://upload.example.com/signed");

      const payload = await createUploadUrl({ fileName: "test.png", mimeType: "image/png" });

      expect(payload.uploadUrl).toBe("https://upload.example.com/signed");
      expect(payload.fileKey).toMatch(/^community\/.+\/original\.png$/);
    });
  });

  describe("uploadObject", () => {
    it("uploads bytes to R2 via PutObjectCommand", async () => {
      stubSend.mockResolvedValue({});

      const body = Buffer.from("image-bytes");
      await uploadObject({
        fileKey: "community/123.png",
        body,
        mimeType: "image/png"
      });

      expect(stubSend).toHaveBeenCalledTimes(1);
      const command = stubSend.mock.calls[0]?.[0] as { input: Record<string, unknown> };
      expect(command.input).toMatchObject({
        Bucket: "test-bucket",
        Key: "community/123.png",
        Body: body,
        ContentType: "image/png",
        CacheControl: "public, max-age=31536000, immutable",
        ContentDisposition: "inline"
      });
    });

    it("propagates errors from the S3 client", async () => {
      stubSend.mockRejectedValue(new Error("upload failed"));

      await expect(
        uploadObject({
          fileKey: "community/123.png",
          body: Buffer.from("image-bytes"),
          mimeType: "image/png"
        })
      ).rejects.toThrow("upload failed");
    });
  });

  describe("getObject", () => {
    it("reads the exact object key", async () => {
      const output = { Body: "body" };
      stubSend.mockResolvedValue(output);

      await expect(getObject("community/pose/skeleton.png")).resolves.toBe(output);
      const command = stubSend.mock.calls[0]?.[0] as { input: Record<string, unknown> };
      expect(command.input).toEqual({ Bucket: "test-bucket", Key: "community/pose/skeleton.png" });
    });
  });

  describe("deleteObject", () => {
    it("deletes the exact object key", async () => {
      stubSend.mockResolvedValue({});

      await deleteObject("community/pose/skeleton.png");
      const command = stubSend.mock.calls[0]?.[0] as { input: Record<string, unknown> };
      expect(command.input).toEqual({ Bucket: "test-bucket", Key: "community/pose/skeleton.png" });
    });
  });

  describe("objectExists", () => {
    it("returns true when HeadObject succeeds", async () => {
      stubSend.mockResolvedValue({});

      await expect(objectExists("community/a.png")).resolves.toBe(true);
    });

    it("returns false when HeadObject throws", async () => {
      stubSend.mockRejectedValue(new Error("NotFound"));

      await expect(objectExists("community/missing.png")).resolves.toBe(false);
    });
  });
});
