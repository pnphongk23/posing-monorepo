import type { Sql } from "./connection";
import type { PoseRecord } from "./communityStore";

interface PoseRow {
  pose_id: string;
  owner_account_id: string;
  name: string;
  original_url: string;
  skeleton_url: string;
  thumbnail_url: string;
  tags: string;
  difficulty: PoseRecord["difficulty"];
  description: string | null;
  body_parts: string;
  status: PoseRecord["status"];
  current_job_id: string | null;
  created_at: Date | string;
  updated_at: Date | string;
  download_count: number;
}

export interface SavedListResult {
  poses: PoseRecord[];
  total: number;
}

function parseJsonArray(value: string): string[] {
  const parsed: unknown = JSON.parse(value);
  return Array.isArray(parsed) && parsed.every((item) => typeof item === "string") ? parsed : [];
}

function toPose(row: PoseRow): PoseRecord {
  return {
    poseId: row.pose_id,
    ownerAccountId: row.owner_account_id,
    name: row.name,
    originalUrl: row.original_url,
    skeletonUrl: row.skeleton_url,
    thumbnailUrl: row.thumbnail_url,
    tags: parseJsonArray(row.tags),
    difficulty: row.difficulty,
    description: row.description,
    bodyParts: parseJsonArray(row.body_parts),
    status: row.status,
    currentJobId: row.current_job_id,
    createdAt: row.created_at instanceof Date ? row.created_at.toISOString() : String(row.created_at),
    updatedAt: row.updated_at instanceof Date ? row.updated_at.toISOString() : String(row.updated_at),
    downloadCount: Number(row.download_count)
  };
}

const usableMediaJoin = `
  JOIN media_assets original
    ON original.pose_id = p.pose_id AND original.role = 'original' AND original.readiness = 'ready'
  JOIN media_assets skeleton
    ON skeleton.pose_id = p.pose_id AND skeleton.role = 'skeleton' AND skeleton.readiness = 'ready'
  JOIN media_assets thumbnail
    ON thumbnail.pose_id = p.pose_id AND thumbnail.role = 'thumbnail' AND thumbnail.readiness = 'ready'
`;

export class SavedStore {
  constructor(private readonly db: Sql) {}

  async save(accountId: string, poseId: string): Promise<PoseRecord | null> {
    await this.db.unsafe(
      `INSERT INTO saved_entries (account_id, pose_id)
       SELECT $1, p.pose_id
       FROM poses p
       ${usableMediaJoin}
       WHERE p.pose_id = $2 AND p.status = 'published'
       ON CONFLICT (account_id, pose_id) DO NOTHING`,
      [accountId, poseId]
    );
    return this.getUsablePublishedPose(poseId);
  }

  async remove(accountId: string, poseId: string): Promise<void> {
    await this.db`
      DELETE FROM saved_entries
      WHERE account_id = ${accountId} AND pose_id = ${poseId}
    `;
  }

  async list(accountId: string, page: number, limit: number): Promise<SavedListResult> {
    const offset = (page - 1) * limit;
    const countRows = (await this.db`
      SELECT COUNT(*) AS count
      FROM saved_entries saved
      JOIN poses p ON p.pose_id = saved.pose_id
      ${this.db.unsafe(usableMediaJoin)}
      WHERE saved.account_id = ${accountId} AND p.status = ${"published"}
    `) as Array<{ count: string | number }>;

    const rows = (await this.db`
      SELECT
        p.*,
        original.locator AS original_url,
        skeleton.locator AS skeleton_url,
        thumbnail.locator AS thumbnail_url
      FROM saved_entries saved
      JOIN poses p ON p.pose_id = saved.pose_id
      ${this.db.unsafe(usableMediaJoin)}
      WHERE saved.account_id = ${accountId} AND p.status = ${"published"}
      ORDER BY saved.saved_at DESC, saved.pose_id ASC
      LIMIT ${limit} OFFSET ${offset}
    `) as PoseRow[];

    return { poses: rows.map(toPose), total: Number(countRows[0]?.count ?? 0) };
  }

  private async getUsablePublishedPose(poseId: string): Promise<PoseRecord | null> {
    const rows = (await this.db.unsafe(
      `SELECT
         p.*,
         original.locator AS original_url,
         skeleton.locator AS skeleton_url,
         thumbnail.locator AS thumbnail_url
       FROM poses p
       ${usableMediaJoin}
       WHERE p.pose_id = $1 AND p.status = 'published'`,
      [poseId]
    )) as PoseRow[];
    return rows[0] ? toPose(rows[0]) : null;
  }
}
