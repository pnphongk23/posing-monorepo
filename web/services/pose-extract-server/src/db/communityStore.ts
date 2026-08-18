import { randomUUID } from "node:crypto";

import type { Sql } from "./connection";
import { pgTimestamp } from "./pgTypes";

export type PoseStatus = "draft" | "published";
export type PoseDifficulty = "beginner" | "intermediate" | "advanced";

export interface CommunityPoseRecord {
  id: string;
  name: string;
  imagePath: string;
  thumbnailPath: string | null;
  tags: string[];
  difficulty: PoseDifficulty | null;
  description: string | null;
  bodyParts: string[];
  status: PoseStatus;
  uploadedAt: string;
  downloadCount: number;
}

export interface CreatePoseInput {
  name: string;
  imagePath: string;
  thumbnailPath: string | null;
  tags: string[];
  difficulty: PoseDifficulty | null;
  description: string | null;
  bodyParts: string[];
  status: PoseStatus;
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
  poses: CommunityPoseRecord[];
  total: number;
}

interface CommunityPoseRow {
  id: string;
  name: string;
  image_path: string;
  thumbnail_path: string | null;
  tags: string;
  difficulty: PoseDifficulty | null;
  description: string | null;
  body_parts: string;
  status: PoseStatus;
  uploaded_at: Date | string;
  download_count: number;
}

export class CommunityStore {
  constructor(private readonly db: Sql) {}

  async createPose(input: CreatePoseInput): Promise<CommunityPoseRecord> {
    const id = randomUUID();
    const rows = (await this.db`
      INSERT INTO community_poses
        (id, name, image_path, thumbnail_path, tags, difficulty, description, body_parts, status)
      VALUES (
        ${id},
        ${input.name},
        ${input.imagePath},
        ${input.thumbnailPath},
        ${JSON.stringify(input.tags)},
        ${input.difficulty},
        ${input.description},
        ${JSON.stringify(input.bodyParts)},
        ${input.status}
      )
      RETURNING *
    `) as CommunityPoseRow[];

    const created = rows[0];
    if (!created) throw new Error("Failed to create pose");
    return this.toRecord(created);
  }

  async getPoseById(id: string): Promise<CommunityPoseRecord | null> {
    const rows = (await this.db`SELECT * FROM community_poses WHERE id = ${id}`) as CommunityPoseRow[];
    const row = rows[0];
    return row ? this.toRecord(row) : null;
  }

  async listPoses(filter: ListPosesFilter): Promise<ListPosesResult> {
    const offset = (filter.page - 1) * filter.limit;

    const difficultyCondition = filter.difficulty
      ? this.db` AND difficulty = ${filter.difficulty}`
      : this.db``;
    const tagCondition = filter.tag
      ? this.db` AND tags LIKE ${`%"${filter.tag}"%`}`
      : this.db``;
    const nameCondition =
      filter.q !== undefined && filter.q.length > 0
        ? this.db` AND name ILIKE ${`%${escapeLikePattern(filter.q)}%`} ESCAPE '\\'`
        : this.db``;

    const countRows = (await this.db`
      SELECT COUNT(*) AS count
      FROM community_poses
      WHERE status = ${filter.status}${difficultyCondition}${tagCondition}${nameCondition}
    `) as Array<{ count: string | number }>;

    const total = Number(countRows[0]?.count ?? 0);

    const rows = (await this.db`
      SELECT *
      FROM community_poses
      WHERE status = ${filter.status}${difficultyCondition}${tagCondition}${nameCondition}
      ORDER BY uploaded_at DESC, id ASC
      LIMIT ${filter.limit} OFFSET ${offset}
    `) as CommunityPoseRow[];

    return {
      poses: rows.map((row) => this.toRecord(row)),
      total
    };
  }

  async incrementDownload(id: string): Promise<void> {
    await this.db`
      UPDATE community_poses
      SET download_count = download_count + 1
      WHERE id = ${id}
    `;
  }

  private toRecord(row: CommunityPoseRow): CommunityPoseRecord {
    return {
      id: row.id,
      name: row.name,
      imagePath: row.image_path,
      thumbnailPath: row.thumbnail_path,
      tags: JSON.parse(row.tags) as string[],
      difficulty: row.difficulty,
      description: row.description,
      bodyParts: JSON.parse(row.body_parts) as string[],
      status: row.status,
      uploadedAt: pgTimestamp(row.uploaded_at)!,
      downloadCount: row.download_count
    };
  }
}
