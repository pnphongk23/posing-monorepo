import { PGlite } from "@electric-sql/pglite";
import { PGLiteSocketServer } from "@electric-sql/pglite-socket";
import { afterEach, describe, expect, it } from "vitest";

import { applySchema, closeDatabase, createDatabase, type Sql } from "./connection";

const cleanupFns: Array<() => Promise<void>> = [];

async function setupDatabase(): Promise<Sql> {
  const pg = new PGlite();
  const server = new PGLiteSocketServer({ db: pg, host: "127.0.0.1", port: 0 });
  await server.start();

  const sql = createDatabase(`postgres://postgres@${server.getServerConn()}/postgres`);
  await applySchema(sql);

  cleanupFns.push(async () => {
    await closeDatabase(sql);
    await server.stop();
    await pg.close();
  });

  return sql;
}

afterEach(async () => {
  while (cleanupFns.length > 0) {
    const fn = cleanupFns.pop();
    if (fn) {
      await fn();
    }
  }
});

describe("createDatabase / applySchema (Postgres via PGlite)", () => {
  it("applies schema and creates all tables", async () => {
    const sql = await setupDatabase();

    const tables = await sql`
      SELECT table_name
      FROM information_schema.tables
      WHERE table_schema = 'public'
      ORDER BY table_name
    `;
    const tableNames = tables.map((row) => row.table_name);

    expect(tableNames).toContain("schema_bootstrap");
    expect(tableNames).toContain("api_keys");
    expect(tableNames).toContain("request_logs");
    expect(tableNames).toContain("community_poses");
    expect(tableNames).toContain("extraction_jobs");
    expect(tableNames).toContain("app_settings");
  });

  it("seeds the schema_bootstrap sentinel row", async () => {
    const sql = await setupDatabase();

    const sentinel = await sql`SELECT id FROM schema_bootstrap WHERE id = 1`;

    expect(sentinel).toHaveLength(1);
    expect(sentinel[0].id).toBe(1);
  });

  it("community_poses has correct defaults and constraints", async () => {
    const sql = await setupDatabase();

    // Insert with minimal fields — defaults should apply.
    await sql`
      INSERT INTO community_poses (id, name, image_path)
      VALUES ('test-1', 'Test Pose', 'community/test.png')
    `;

    const rows = await sql`
      SELECT status, download_count, tags, body_parts
      FROM community_poses
      WHERE id = 'test-1'
    `;

    expect(rows).toHaveLength(1);
    expect(rows[0].status).toBe("draft");
    expect(rows[0].download_count).toBe(0);
    expect(rows[0].tags).toBe("[]");
    expect(rows[0].body_parts).toBe("[]");

    // Invalid status should fail the CHECK constraint.
    await expect(
      sql`
        INSERT INTO community_poses (id, name, image_path, status)
        VALUES ('test-2', 'Bad', 'path', 'invalid')
      `
    ).rejects.toThrow();
  });

  it("request_logs.success is a BOOLEAN column", async () => {
    const sql = await setupDatabase();

    await sql`INSERT INTO request_logs (success) VALUES (true)`;
    await sql`INSERT INTO request_logs (success) VALUES (false)`;

    const rows = await sql`SELECT success FROM request_logs ORDER BY id`;

    expect(rows.map((row) => row.success)).toEqual([true, false]);
  });

  it("configures the shared postgres client with prepare:false", async () => {
    const sql = await setupDatabase();

    // The single shared factory must disable prepared statements so it works
    // behind the Supabase transaction-mode pooler (port 6543), which resets
    // sessions and rejects prepared statements with PostgresError 26000.
    expect(sql.options.prepare).toBe(false);
  });
});
