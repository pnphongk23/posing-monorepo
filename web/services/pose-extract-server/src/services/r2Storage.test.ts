import { HeadObjectCommand, PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("@aws-sdk/s3-request-presigner", () => ({
  getSignedUrl: vi.fn()
}));

vi.mock("@aws-sdk/client-s3", () => {
  const send = vi.fn();
  return {
    S3Client: function S3Client() {
      return { send };
    },
    HeadObjectCommand: function HeadObjectCommand(input: unknown) {
      return { input };
    },
    PutObjectCommand: function PutObjectCommand(input: unknown) {
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

import { buildPublicUrl, createUploadUrl, objectExists, uploadObject } from "./r2Storage";

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

  describe("createUploadUrl", () => {
    it("returns uploadUrl and fileKey from presigned PUT", async () => {
      vi.mocked(getSignedUrl).mockResolvedValue("https://upload.example.com/signed");

      const payload = await createUploadUrl({ fileName: "test.png", mimeType: "image/png" });

      expect(payload.uploadUrl).toBe("https://upload.example.com/signed");
      expect(payload.fileKey).toMatch(/^community\/.+\.png$/);
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
        ContentType: "image/png"
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
