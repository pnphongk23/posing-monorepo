import type { Sql } from "./connection";

export interface AccountRecord {
  id: string;
  displayName: string;
  createdAt: string;
}

interface AccountRow {
  id: string;
  display_name: string;
  created_at: Date | string;
}

function toAccount(row: AccountRow): AccountRecord {
  return {
    id: row.id,
    displayName: row.display_name,
    createdAt: row.created_at instanceof Date ? row.created_at.toISOString() : String(row.created_at)
  };
}

export class AccountStore {
  constructor(private readonly db: Sql) {}

  async upsert(input: { id: string; displayName: string }): Promise<AccountRecord> {
    const rows = (await this.db`
      INSERT INTO accounts (id, display_name)
      VALUES (${input.id}, ${input.displayName})
      ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name
      RETURNING id, display_name, created_at
    `) as AccountRow[];
    if (!rows[0]) throw new Error("Failed to upsert account");
    return toAccount(rows[0]);
  }

  async getById(id: string): Promise<AccountRecord | null> {
    const rows = (await this.db`
      SELECT id, display_name, created_at FROM accounts WHERE id = ${id}
    `) as AccountRow[];
    return rows[0] ? toAccount(rows[0]) : null;
  }
}
