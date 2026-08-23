import postgres from "postgres";

import { getEnv } from "../src/config/env";
import { buildCommunityObjectKey, buildPublicUrl, deleteObject, uploadObject } from "../src/services/r2Storage";

const samples = [
  { poseId: "a43838f4-312d-4ea7-9a05-6f7c191fd691", jobId: "9249ca9b-8a95-40fa-80b9-858476216ad0" },
  { poseId: "e41fed67-90cf-40b6-9ddc-c1727afa054d", jobId: "3cd4445f-c8d9-4d0a-b133-eed555700e4d" }
] as const;

type Asset = { role: "original" | "skeleton" | "thumbnail"; body: Buffer; mimeType: string; key: string };

async function main(): Promise<void> {
  const env = getEnv();
  const sql = postgres(env.DATABASE_URL);
  try {
    for (const sample of samples) {
      const rows = await sql`
        SELECT j.source_image_base64, j.source_mime_type, j.result_image_base64, j.result_mime_type,
               p.pose_id
        FROM extraction_jobs j JOIN poses p ON p.current_job_id = j.id
        WHERE p.pose_id = ${sample.poseId} AND j.id = ${sample.jobId}
          AND j.status = 'succeeded'
      ` as Array<Record<string, string>>;
      const row = rows[0];
      if (!row) throw new Error(`Sample ${sample.poseId} was not found or is not succeeded`);

      const assets: Asset[] = ([
        ["original", row.source_image_base64, row.source_mime_type],
        ["skeleton", row.result_image_base64, row.result_mime_type],
        ["thumbnail", row.result_image_base64, row.result_mime_type]
      ] as const).map(([role, base64, mimeType]) => ({
        role,
        body: Buffer.from(base64, "base64"),
        mimeType,
        key: buildCommunityObjectKey(role, mimeType.split("/")[1] ?? "bin", sample.poseId)
      }));

      const uploaded: string[] = [];
      try {
        for (const asset of assets) {
          await uploadObject({ fileKey: asset.key, body: asset.body, mimeType: asset.mimeType });
          uploaded.push(asset.key);
        }
        await sql.begin(async (tx) => {
          for (const asset of assets) {
            await tx`
              UPDATE media_assets SET locator = ${buildPublicUrl(env.R2_PUBLIC_URL, asset.key)}, readiness = 'ready'
              WHERE pose_id = ${sample.poseId} AND role = ${asset.role}
            `;
          }
        });
        console.log(`backfilled ${sample.poseId}`);
      } catch (error) {
        await Promise.allSettled(uploaded.map((key) => deleteObject(key)));
        throw error;
      }
    }
  } finally {
    await sql.end();
  }
}

main().catch(() => {
  process.exitCode = 1;
});
