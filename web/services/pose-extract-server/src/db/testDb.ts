import { PGlite } from "@electric-sql/pglite";
import { PGLiteSocketServer } from "@electric-sql/pglite-socket";
import { afterEach } from "vitest";

import { applySchema, closeDatabase, createDatabase, type Sql } from "./connection";

const cleanups: Array<() => Promise<void>> = [];

afterEach(async () => {
  while (cleanups.length > 0) {
    const cleanup = cleanups.pop();
    if (cleanup) {
      await cleanup();
    }
  }
});

export async function setupTestDatabase(): Promise<Sql> {
  const pg = new PGlite();
  const server = new PGLiteSocketServer({ db: pg, host: "127.0.0.1", port: 0 });
  await server.start();

  const sql = createDatabase(`postgres://postgres@${server.getServerConn()}/postgres`);
  await applySchema(sql);

  cleanups.push(async () => {
    await closeDatabase(sql);
    await server.stop();
    await pg.close();
  });

  return sql;
}
