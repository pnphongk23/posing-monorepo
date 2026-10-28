import { randomUUID } from "node:crypto";
import path from "node:path";

import { DeleteObjectCommand, GetObjectCommand, HeadObjectCommand, PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import type { GetObjectCommandOutput } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

import { getEnv } from "../config/env";

export interface UploadUrlPayload {
  uploadUrl: string;
  fileKey: string;
}

export type CommunityObjectRole = "original" | "skeleton" | "thumbnail";

const IMMUTABLE_CACHE_CONTROL = "public, max-age=31536000, immutable";

export function buildCommunityObjectKey(
  role: CommunityObjectRole,
  extension: string,
  objectId: string = randomUUID()
): string {
  const normalizedExtension = extension.startsWith(".") ? extension.toLowerCase() : `.${extension.toLowerCase()}`;
  return `community/${objectId}/${role}${normalizedExtension}`;
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
  role?: CommunityObjectRole;
  objectId?: string;
}): Promise<UploadUrlPayload> {
  const env = getEnv();
  const ext = path.extname(input.fileName) || ".bin";
  const fileKey = buildCommunityObjectKey(input.role ?? "original", ext, input.objectId);

  const command = new PutObjectCommand({
    Bucket: env.R2_BUCKET,
    Key: fileKey,
    ContentType: input.mimeType,
    CacheControl: IMMUTABLE_CACHE_CONTROL,
    ContentDisposition: "inline"
  });

  const uploadUrl = await getSignedUrl(getR2Client(), command, { expiresIn: 60 });

  return { uploadUrl, fileKey };
}

export async function uploadObject(input: {
  fileKey: string;
  body: Buffer;
  mimeType: string;
  abortSignal?: AbortSignal;
}): Promise<void> {
  const env = getEnv();

  await getR2Client().send(
    new PutObjectCommand({
      Bucket: env.R2_BUCKET,
      Key: input.fileKey,
      Body: input.body,
      ContentType: input.mimeType,
      CacheControl: IMMUTABLE_CACHE_CONTROL,
      ContentDisposition: "inline"
    }),
    input.abortSignal ? { abortSignal: input.abortSignal } : undefined
  );
}

export async function getObject(fileKey: string): Promise<GetObjectCommandOutput> {
  const env = getEnv();
  return getR2Client().send(
    new GetObjectCommand({
      Bucket: env.R2_BUCKET,
      Key: fileKey
    })
  );
}

export async function deleteObject(fileKey: string): Promise<void> {
  const env = getEnv();
  await getR2Client().send(
    new DeleteObjectCommand({
      Bucket: env.R2_BUCKET,
      Key: fileKey
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
