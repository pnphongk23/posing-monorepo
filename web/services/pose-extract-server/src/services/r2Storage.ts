import { randomUUID } from "node:crypto";
import path from "node:path";

import { PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { HeadObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

import { getEnv } from "../config/env";

export interface UploadUrlPayload {
  uploadUrl: string;
  fileKey: string;
}

export function getR2Client(): S3Client {
  const env = getEnv();
  return new S3Client({
    region: "auto",
    endpoint: `https://${env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
    credentials: {
      accessKeyId: env.R2_ACCESS_KEY_ID,
      secretAccessKey: env.R2_SECRET_ACCESS_KEY
    }
  });
}

export async function createUploadUrl(input: {
  fileName: string;
  mimeType: string;
}): Promise<UploadUrlPayload> {
  const env = getEnv();
  const ext = path.extname(input.fileName) || ".bin";
  const fileKey = `community/${randomUUID()}${ext.toLowerCase()}`;

  const command = new PutObjectCommand({
    Bucket: env.R2_BUCKET,
    Key: fileKey,
    ContentType: input.mimeType
  });

  const uploadUrl = await getSignedUrl(getR2Client(), command, { expiresIn: 60 });

  return { uploadUrl, fileKey };
}

export async function uploadObject(input: {
  fileKey: string;
  body: Buffer;
  mimeType: string;
}): Promise<void> {
  const env = getEnv();

  await getR2Client().send(
    new PutObjectCommand({
      Bucket: env.R2_BUCKET,
      Key: input.fileKey,
      Body: input.body,
      ContentType: input.mimeType
    })
  );
}

export async function objectExists(fileKey: string): Promise<boolean> {
  const env = getEnv();

  try {
    await getR2Client().send(
      new HeadObjectCommand({
        Bucket: env.R2_BUCKET,
        Key: fileKey
      })
    );
    return true;
  } catch {
    return false;
  }
}

export function buildPublicUrl(base: string, fileKey: string): string {
  const normalizedBase = base.replace(/\/+$/, "");
  const normalizedKey = fileKey.replace(/^\/+/, "");
  return `${normalizedBase}/${normalizedKey}`;
}
