import { PGlite } from "@electric-sql/pglite";
import { PGLiteSocketServer } from "@electric-sql/pglite-socket";
import { spawn } from "node:child_process";

const port = 43000 + Math.floor(Math.random() * 500);

// Ephemeral in-process Postgres so the boot check does not require a real
// database. The server (dist/index.js) reads DATABASE_URL and applies the schema
// on boot; we verify the schema was actually applied by reading the
// schema_bootstrap sentinel row afterwards.
const pg = new PGlite();
const pgServer = new PGLiteSocketServer({ db: pg, host: "127.0.0.1", port: 0 });
await pgServer.start();
const databaseUrl = `postgres://postgres@${pgServer.getServerConn()}/postgres`;

const child = spawn("node", ["dist/index.js"], {
  cwd: process.cwd(),
  env: {
    ...process.env,
    NODE_ENV: "production",
    PORT: String(port),
    DATABASE_URL: databaseUrl,
    ADMIN_SECRET: process.env.ADMIN_SECRET ?? "spike-admin-secret",
    R2_ACCOUNT_ID: process.env.R2_ACCOUNT_ID ?? "spike-account-id",
    R2_ACCESS_KEY_ID: process.env.R2_ACCESS_KEY_ID ?? "spike-access-key-id",
    R2_SECRET_ACCESS_KEY: process.env.R2_SECRET_ACCESS_KEY ?? "spike-secret-access-key",
    R2_BUCKET: process.env.R2_BUCKET ?? "spike-bucket",
    R2_PUBLIC_URL: process.env.R2_PUBLIC_URL ?? "https://spike.example.com",
    APP_VERSION: "spike-local"
  },
  stdio: "pipe"
});

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitForHealth(maxAttempts = 40) {
  for (let i = 0; i < maxAttempts; i += 1) {
    try {
      const response = await fetch(`http://127.0.0.1:${port}/api/health`);
      if (response.ok) {
        return await response.json();
      }
    } catch (_error) {
      // Server may still be booting; continue polling.
    }
    await sleep(250);
  }
  throw new Error("Server failed to become healthy in time");
}

async function main() {
  const health = await waitForHealth();
  if (health.status !== "ok") {
    throw new Error(`Unexpected health status: ${health.status}`);
  }

  // Confirm applySchema ran on boot by checking the sentinel row. Query the
  // PGlite instance directly — a second socket client would reset the child's
  // connection (PGlite serves one client at a time).
  const sentinel = await pg.query("SELECT id FROM schema_bootstrap WHERE id = 1");

  if (sentinel.rows.length !== 1) {
    throw new Error("Schema was not applied: schema_bootstrap sentinel missing");
  }

  console.log(
    JSON.stringify(
      {
        ok: true,
        version: health.version,
        schemaApplied: true
      },
      null,
      2
    )
  );
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    child.kill("SIGTERM");
    await sleep(200);
    await pgServer.stop();
    await pg.close();
  });
