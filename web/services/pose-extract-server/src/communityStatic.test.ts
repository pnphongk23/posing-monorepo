import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import request from "supertest";
import { afterEach, describe, expect, it } from "vitest";

import { createApp } from "./app";

const ORIGINAL_NODE_ENV = process.env.NODE_ENV;

afterEach(() => {
  if (ORIGINAL_NODE_ENV === undefined) {
    delete process.env.NODE_ENV;
  } else {
    process.env.NODE_ENV = ORIGINAL_NODE_ENV;
  }
});

describe("community static file serving", () => {
  it("serves /community files when a directory is set in non-production", async () => {
    process.env.NODE_ENV = "development";
    const uploadDir = fs.mkdtempSync(path.join(os.tmpdir(), "community-static-"));
    fs.writeFileSync(path.join(uploadDir, "pose.png"), "png-bytes");

    const app = createApp({ version: "1.0.0-test", communityUploadDir: uploadDir });

    const res = await request(app).get("/community/pose.png");
    expect(res.status).toBe(200);
    expect(res.body).toBeInstanceOf(Buffer);
    expect((res.body as Buffer).toString("utf8")).toBe("png-bytes");

    fs.rmSync(uploadDir, { recursive: true, force: true });
  });

  it("does not mount /community static middleware in production", async () => {
    process.env.NODE_ENV = "production";
    const uploadDir = fs.mkdtempSync(path.join(os.tmpdir(), "community-static-"));
    fs.writeFileSync(path.join(uploadDir, "pose.png"), "png-bytes");

    const app = createApp({ version: "1.0.0-test", communityUploadDir: uploadDir });

    const res = await request(app).get("/community/pose.png");
    expect(res.status).toBe(404);
    expect(res.body.error.code).toBe("NOT_FOUND");

    fs.rmSync(uploadDir, { recursive: true, force: true });
  });
});
