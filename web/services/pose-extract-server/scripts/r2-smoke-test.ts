import { randomBytes } from "node:crypto";
import { DeleteObjectCommand, GetObjectCommand, HeadObjectCommand, PutObjectCommand } from "@aws-sdk/client-s3";

import { getEnv } from "../src/config/env";
import { getR2Client } from "../src/services/r2Storage";

const env = getEnv();
const key = `mvp-smoke/${new Date().toISOString()}-${randomBytes(6).toString("hex")}`;
const body = Buffer.from("community-r2-smoke-test-32-bytes!!");
const mimeType = "application/octet-stream";
const cacheControl = "no-cache";
const client = getR2Client();

async function main(): Promise<void> {
  let deleted = false;
  let operation = "PUT";
  try {
    await client.send(new PutObjectCommand({
      Bucket: env.R2_BUCKET,
      Key: key,
      Body: body,
      ContentType: mimeType,
      CacheControl: cacheControl
    }));

    operation = "HEAD";
    const head = await client.send(new HeadObjectCommand({ Bucket: env.R2_BUCKET, Key: key }));
    if (head.ContentLength !== body.length || head.ContentType !== mimeType) {
      throw new Error(`HEAD metadata mismatch: length=${head.ContentLength} type=${head.ContentType}`);
    }

    operation = "GET";
    const get = await client.send(new GetObjectCommand({ Bucket: env.R2_BUCKET, Key: key }));
    const received = Buffer.from(await get.Body!.transformToByteArray());
    if (!received.equals(body)) throw new Error("GET body mismatch");

    operation = "DELETE";
    await client.send(new DeleteObjectCommand({ Bucket: env.R2_BUCKET, Key: key }));
    deleted = true;
    try {
      await client.send(new HeadObjectCommand({ Bucket: env.R2_BUCKET, Key: key }));
      throw new Error("HEAD unexpectedly succeeded after DELETE");
    } catch (error) {
      if (error instanceof Error && error.message === "HEAD unexpectedly succeeded after DELETE") throw error;
    }

    console.log(`PASS key=${key} bytes=${body.length} contentType=${mimeType} deleted=true`);
  } catch (error) {
    if (!deleted) {
      try { await client.send(new DeleteObjectCommand({ Bucket: env.R2_BUCKET, Key: key })); } catch { /* best effort cleanup */ }
    }
    const detail = error as {
      name?: string;
      message?: string;
      Code?: string;
      $metadata?: { httpStatusCode?: number; requestId?: string };
    };
    console.error(
      `FAIL key=${key} deleted=${deleted} operation=${operation} name=${detail.name ?? "unknown"} ` +
      `code=${detail.Code ?? "unknown"} status=${detail.$metadata?.httpStatusCode ?? "unknown"} ` +
      `requestId=${detail.$metadata?.requestId ?? "unknown"} reason=${detail.message ?? "unknown"}`
    );
    process.exitCode = 1;
  }
}

void main();
