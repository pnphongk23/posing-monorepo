import { randomUUID } from "node:crypto";

import type { Fragment } from "postgres";

import type { Sql } from "./connection";
import { pgTimestamp } from "./pgTypes";

export type PoseStatus = "local" | "published";
export type PoseDifficulty = "beginner" | "intermediate" | "advanced";

/** Canonical persisted Pose. Public CommunityPose responses are projections of this record. */
export interface PoseRecord {
  poseId: string;
  ownerAccountId: string;
  name: string;
  originalUrl: string;
  skeletonUrl: string;
  thumbnailUrl: string;
  tags: string[];
  difficulty: PoseDifficulty | null;
  description: string | null;
  bodyParts: string[];
  status: PoseStatus;
  currentJobId: string | null;
  createdAt: string;
  updatedAt: string;
  downloadCount: number;
}

export interface CreatePoseInput {
  poseId?: string;
  ownerAccountId: string;
  name: string;
  originalUrl: string;
  skeletonUrl: string;
  thumbnailUrl: string;
  tags: string[];
  difficulty: PoseDifficulty | null;
  description: string | null;
  bodyParts: string[];
  currentJobId?: string | null;
}

/**
 * Partial fields for updating pose metadata. Undefined fields are left unchanged;
 * explicit `null` clears nullable columns (difficulty, description).
 */
export interface UpdatePoseInput {
  name?: string;
  tags?: string[];
  difficulty?: PoseDifficulty | null;
  description?: string | null;
  bodyParts?: string[];
  status?: PoseStatus;
}

export interface ListPosesFilter {
  status: PoseStatus;
  difficulty?: PoseDifficulty;
  tag?: string;
  /** Case-insensitive substring match on name; omit or blank for no title filter. */
  q?: string;
  page: number;
  limit: number;
}

/** Escape SQL LIKE metacharacters so user input is matched literally. */
export function escapeLikePattern(value: string): string {
  return value.replace(/\\/g, "\\\\").replace(/%/g, "\\%").replace(/_/g, "\\_");
}

export interface ListPosesResult {
  poses: PoseRecord[];
  total: number;
}

interface PoseRow {
  pose_id: string;
  owner_account_id: string;
  name: string;
  original_url: string;
  skeleton_url: string;
  thumbnail_url: string;
  tags: string;
  difficulty: PoseDifficulty | null;
  description: string | null;
  body_parts: string;
  status: PoseStatus;
  current_job_id: string | null;
  created_at: Date | string;
  updated_at: Date | string;
  download_count: number;
}

export class PoseStore {
  constructor(private readonly db: Sql) {}

  /** Creates a local Pose atomically with all three required media roles. */
  async createPose(input: CreatePoseInput): Promise<PoseRecord> {
    const poseId = input.poseId ?? randomUUID();
    const media = [
      { mediaId: randomUUID(), role: "original", locator: input.originalUrl },
      { mediaId: randomUUID(), role: "skeleton", locator: input.skeletonUrl },
      { mediaId: randomUUID(), role: "thumbnail", locator: input.thumbnailUrl }
    ] as const;

    return this.db.begin(async (transaction) => {
      const rows = (await transaction`
        INSERT INTO poses (
          pose_id,
          owner_account_id,
          name,
          tags,
          difficulty,
          description,
          body_parts,
          status,
          current_job_id
        )
        VALUES (
          ${poseId},
          ${input.ownerAccountId},
          ${input.name},
          ${JSON.stringify(input.tags)},
          ${input.difficulty},
          ${input.description},
          ${JSON.stringify(input.bodyParts)},
          ${"local"},
          ${input.currentJobId ?? null}
        )
        RETURNING *
      `) as Array<Omit<PoseRow, "original_url" | "skeleton_url" | "thumbnail_url">>;

      for (const asset of media) {
        await transaction`
          INSERT INTO media_assets (media_id, pose_id, role, locator, readiness)
          VALUES (${asset.mediaId}, ${poseId}, ${asset.role}, ${asset.locator}, ${"ready"})
        `;
      }

      const created = rows[0];
      if (!created) throw new Error("Failed to create pose");
      return this.toRecord({
        ...created,
        original_url: input.originalUrl,
        skeleton_url: input.skeletonUrl,
        thumbnail_url: input.thumbnailUrl
      });
    });
  }

  async getPoseById(poseId: string): Promise<PoseRecord | null> {
    const rows = (await this.db`
      SELECT
        p.*,
        original.locator AS original_url,
        skeleton.locator AS skeleton_url,
        thumbnail.locator AS thumbnail_url
      FROM poses p
      JOIN media_assets original ON original.pose_id = p.pose_id AND original.role = 'original'
      JOIN media_assets skeleton ON skeleton.pose_id = p.pose_id AND skeleton.role = 'skeleton'
      JOIN media_assets thumbnail ON thumbnail.pose_id = p.pose_id AND thumbnail.role = 'thumbnail'
      WHERE p.pose_id = ${poseId}
    `) as PoseRow[];
    const row = rows[0];
    return row ? this.toRecord(row) : null;
  }

  async getPoseByCurrentJobId(jobId: string): Promise<PoseRecord | null> {
    const rows = (await this.db`
      SELECT
        p.*,
        original.locator AS original_url,
        skeleton.locator AS skeleton_url,
        thumbnail.locator AS thumbnail_url
      FROM poses p
      JOIN media_assets original ON original.pose_id = p.pose_id AND original.role = 'original'
      JOIN media_assets skeleton ON skeleton.pose_id = p.pose_id AND skeleton.role = 'skeleton'
      JOIN media_assets thumbnail ON thumbnail.pose_id = p.pose_id AND thumbnail.role = 'thumbnail'
      WHERE p.current_job_id = ${jobId}
    `) as PoseRow[];
    const row = rows[0];
    return row ? this.toRecord(row) : null;
  }

  async listPoses(filter: ListPosesFilter): Promise<ListPosesResult> {
    const offset = (filter.page - 1) * filter.limit;

    const difficultyCondition = filter.difficulty
      ? this.db` AND p.difficulty = ${filter.difficulty}`
      : this.db``;
    const tagCondition = filter.tag
      ? this.db` AND p.tags LIKE ${`%"${filter.tag}"%`}`
      : this.db``;
    const nameCondition =
      filter.q !== undefined && filter.q.length > 0
        ? this.db` AND p.name ILIKE ${`%${escapeLikePattern(filter.q)}%`} ESCAPE '\\'`
        : this.db``;

    const countRows = (await this.db`
      SELECT COUNT(*) AS count
      FROM poses p
      WHERE p.status = ${filter.status}${difficultyCondition}${tagCondition}${nameCondition}
    `) as Array<{ count: string | number }>;

    const total = Number(countRows[0]?.count ?? 0);

    const rows = (await this.db`
      SELECT
        p.*,
        original.locator AS original_url,
        skeleton.locator AS skeleton_url,
        thumbnail.locator AS thumbnail_url
      FROM poses p
      JOIN media_assets original ON original.pose_id = p.pose_id AND original.role = 'original'
      JOIN media_assets skeleton ON skeleton.pose_id = p.pose_id AND skeleton.role = 'skeleton'
      JOIN media_assets thumbnail ON thumbnail.pose_id = p.pose_id AND thumbnail.role = 'thumbnail'
      WHERE p.status = ${filter.status}${difficultyCondition}${tagCondition}${nameCondition}
      ORDER BY p.created_at DESC, p.pose_id ASC
      LIMIT ${filter.limit} OFFSET ${offset}
    `) as PoseRow[];

    return {
      poses: rows.map((row) => this.toRecord(row)),
      total
    };
  }

  async incrementDownload(poseId: string): Promise<void> {
    await this.db`
      UPDATE poses
      SET download_count = download_count + 1, updated_at = NOW()
      WHERE pose_id = ${poseId}
    `;
  }

  async updatePose(poseId: string, input: UpdatePoseInput): Promise<PoseRecord | null> {
    const assignments: Fragment[] = [];

    if (input.name !== undefined) assignments.push(this.db`name = ${input.name}`);
    if (input.tags !== undefined) assignments.push(this.db`tags = ${JSON.stringify(input.tags)}`);
    if (input.difficulty !== undefined) assignments.push(this.db`difficulty = ${input.difficulty}`);
    if (input.description !== undefined) assignments.push(this.db`description = ${input.description}`);
    if (input.bodyParts !== undefined) assignments.push(this.db`body_parts = ${JSON.stringify(input.bodyParts)}`);
    if (input.status !== undefined) assignments.push(this.db`status = ${input.status}`);

    if (assignments.length === 0) {
      return this.getPoseById(poseId);
    }

    assignments.push(this.db`updated_at = NOW()`);
    let setClause = assignments[0]!;
    for (let i = 1; i < assignments.length; i += 1) {
      setClause = this.db`${setClause}, ${assignments[i]}`;
    }

    await this.db`
      UPDATE poses
      SET ${setClause}
      WHERE pose_id = ${poseId}
    `;
    return this.getPoseById(poseId);
  }

  async deletePose(poseId: string): Promise<boolean> {
    const result = await this.db`
      DELETE FROM poses WHERE pose_id = ${poseId}
    `;
    return result.count > 0;
  }

  private toRecord(row: PoseRow): PoseRecord {
    if (!row.original_url || !row.skeleton_url || !row.thumbnail_url) {
      throw new Error(`Pose ${row.pose_id} is missing a required media role`);
    }
    return {
      poseId: row.pose_id,
      ownerAccountId: row.owner_account_id,
      name: row.name,
      originalUrl: row.original_url,
      skeletonUrl: row.skeleton_url,
      thumbnailUrl: row.thumbnail_url,
      tags: JSON.parse(row.tags) as string[],
      difficulty: row.difficulty,
      description: row.description,
      bodyParts: JSON.parse(row.body_parts) as string[],
      status: row.status,
      currentJobId: row.current_job_id,
      createdAt: pgTimestamp(row.created_at)!,
      updatedAt: pgTimestamp(row.updated_at)!,
      downloadCount: row.download_count
    };
  }
}
