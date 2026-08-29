import fs from "node:fs";
import path from "node:path";

import postgres from "postgres";

export type Sql = postgres.Sql;

function resolveSchemaPath(): string {
  const schemaPath = path.resolve(__dirname, "schema.sql");
  if (fs.existsSync(schemaPath)) {
    return schemaPath;
  }

  throw new Error(`Schema file not found at expected path: ${schemaPath}`);
}

export function createDatabase(databaseUrl: string): Sql {
  // prepare:false disables the extended-query protocol prepared statements.
  // Required for the Supabase transaction-mode pooler (port 6543): a pooled
  // session reset rejects prepared statements with PostgresError 26000.
  return postgres(databaseUrl, { prepare: false });
}

export async function applySchema(sql: Sql): Promise<void> {
  const schemaSql = fs.readFileSync(resolveSchemaPath(), "utf-8");

  const statements = schemaSql
    .split(";")
    .map((statement) => statement.trim())
    .filter((statement) => statement.length > 0);

  for (const statement of statements) {
    await sql.unsafe(statement);
  }
}

export async function closeDatabase(sql: Sql): Promise<void> {
  await sql.end();
}
