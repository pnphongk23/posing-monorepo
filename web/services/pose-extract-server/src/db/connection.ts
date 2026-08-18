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
  return postgres(databaseUrl);
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
