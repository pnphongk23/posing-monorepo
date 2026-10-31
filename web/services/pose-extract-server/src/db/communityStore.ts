import { randomUUID } from "node:crypto";

import type { Fragment } from "postgres";

import { PoseMediaNotReadyError } from "../services/errors";
import type { Sql, SqlOrTx } from "./connection";
import { ObjectDeletionOutbox } from "./objectDeletionOutbox";
import { pgTimestamp } from "./pgTypes";

const REQUIRED_MEDIA_ROLES = ["original", "skeleton", "thumbnail"] as const;
type RequiredMediaRole = (typeof REQUIRED_MEDIA_ROLES)[number];

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

/**
 * Queues object keys on the caller's transaction through the shared outbox helper, so the
 * tickets commit or roll back together with the rows that referenced them. The helper only
 * issues tagged-template statements, which a transaction executor supports verbatim.
 */
async function queueObjectDeletions(transaction: SqlOrTx, locators: readonly string[]): Promise<void> {
  await new ObjectDeletionOutbox(transaction as unknown as Sql).enqueue(locators);
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

export interface PoseStoreOptions {
  /** Maps a stored media locator to the object key the deletion outbox drains. */
  resolveObjectKey?: (locator: string) => string;
}

export class PoseStore {
  private readonly resolveObjectKey: (locator: string) => string;

  constructor(private readonly db: Sql, options: PoseStoreOptions = {}) {
    this.resolveObjectKey = options.resolveObjectKey ?? ((locator: string) => locator);
  }

  /** Creates a local Pose atomically with all three required media roles. */
  async createPose(input: CreatePoseInput, tx?: SqlOrTx): Promise<PoseRecord> {
    const poseId = input.poseId ?? randomUUID();
    const media = [
      { mediaId: randomUUID(), role: "original", locator: input.originalUrl },
      { mediaId: randomUUID(), role: "skeleton", locator: input.skeletonUrl },
      { mediaId: randomUUID(), role: "thumbnail", locator: input.thumbnailUrl }
    ] as const;

    const execute = async (transaction: SqlOrTx) => {
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
    };

    if (tx) {
      return execute(tx);
    }
    return this.db.begin(execute);
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

  /**
   * Updates Pose metadata. Publishing is guarded inside the same statement, so a
   * Pose can never be flipped to `published` while any of its media roles is
   * missing or not yet materialized (readiness <> 'ready').
   */
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

    const publishing = input.status === "published";
    const result = publishing
      ? await this.db`
          UPDATE poses
          SET ${setClause}
          WHERE pose_id = ${poseId}
            AND EXISTS (
              SELECT 1
              FROM media_assets media
              WHERE media.pose_id = poses.pose_id
                AND media.readiness = 'ready'
                AND media.locator <> ''
                AND media.role IN ('original', 'skeleton', 'thumbnail')
              GROUP BY media.pose_id
              HAVING COUNT(DISTINCT media.role) = 3
            )
        `
      : await this.db`
          UPDATE poses
          SET ${setClause}
          WHERE pose_id = ${poseId}
        `;

    if (result.count === 0 && publishing) {
      const missing = await this.describeUnreadyMedia(poseId);
      if (missing !== null) {
        throw new PoseMediaNotReadyError(
          `Pose cannot be published because its media is not ready (${missing}). ` +
            "Publishing requires ready original, skeleton and thumbnail media."
        );
      }
    }

    return this.getPoseById(poseId);
  }

  /**
   * Returns a human readable summary of the media roles blocking publication, or
   * null when the Pose itself does not exist (so the caller can answer 404).
   */
  private async describeUnreadyMedia(poseId: string): Promise<string | null> {
    const poseRows = (await this.db`SELECT 1 FROM poses WHERE pose_id = ${poseId}`) as Array<{ "?column?": number }>;
    if (poseRows.length === 0) return null;

    const mediaRows = (await this.db`
      SELECT role, readiness, locator
      FROM media_assets
      WHERE pose_id = ${poseId}
    `) as Array<{ role: RequiredMediaRole; readiness: string; locator: string }>;

    const byRole = new Map(mediaRows.map((row) => [row.role, row]));
    const missing: string[] = [];
    const unready: string[] = [];

    for (const role of REQUIRED_MEDIA_ROLES) {
      const media = byRole.get(role);
      if (!media || media.locator === "") {
        missing.push(role);
      } else if (media.readiness !== "ready") {
        unready.push(`${role} is ${media.readiness}`);
      }
    }

    const details = [
      missing.length > 0 ? `missing: ${missing.join(", ")}` : null,
      unready.length > 0 ? `not ready: ${unready.join(", ")}` : null
    ].filter((detail): detail is string => detail !== null);

    return details.length > 0 ? details.join("; ") : "media state changed, retry";
  }

  /**
   * Deletes a Pose and, in the same transaction, hands the object keys of every media role of
   * that Pose to the deletion outbox. `media_assets` cascades with the Pose row, so the
   * locators are read under the Pose lock first; they are resolved to storage keys and
   * deduplicated before enqueueing, so the sweep deletes the objects rather than their public
   * URLs. A missing Pose stays a no-op and queues nothing.
   */
  async deletePose(poseId: string): Promise<boolean> {
    return this.db.begin(async (transaction) => {
      const poseRows = (await transaction`
        SELECT pose_id FROM poses WHERE pose_id = ${poseId} FOR UPDATE
      `) as Array<{ pose_id: string }>;
      if (poseRows.length === 0) return false;

      const mediaRows = (await transaction`
        SELECT locator FROM media_assets WHERE pose_id = ${poseId} ORDER BY role
      `) as Array<{ locator: string }>;

      const objectKeys = [...new Set(mediaRows.map((row) => this.resolveObjectKey(row.locator)))];
      await queueObjectDeletions(transaction, objectKeys);

      const result = await transaction`
        DELETE FROM poses WHERE pose_id = ${poseId}
      `;
      return result.count > 0;
    });
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
