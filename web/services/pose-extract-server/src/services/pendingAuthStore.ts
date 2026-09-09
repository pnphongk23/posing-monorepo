import { randomBytes } from "node:crypto";

export interface PendingGoogleAuth {
  transactionId: string;
  codeVerifier: string;
  redirectUri: string;
  expiresAt: number;
}

export interface SessionHandoff {
  accessToken: string;
  refreshToken: string;
  account: { id: string; displayName: string; createdAt: string };
  expiresAt: number;
}

export class PendingAuthStore {
  private readonly pending = new Map<string, PendingGoogleAuth>();
  private readonly sessions = new Map<string, SessionHandoff>();

  constructor(private readonly ttlMs = 5 * 60_000, private readonly now = () => Date.now()) {}

  create(redirectUri: string): PendingGoogleAuth {
    this.purge();
    const record = {
      transactionId: randomBytes(32).toString("base64url"),
      codeVerifier: randomBytes(32).toString("base64url"),
      redirectUri,
      expiresAt: this.now() + this.ttlMs
    };
    this.pending.set(record.transactionId, record);
    return record;
  }

  consumeTransaction(transactionId: string): PendingGoogleAuth | null {
    this.purge();
    const record = this.pending.get(transactionId);
    if (!record) return null;
    this.pending.delete(transactionId);
    return record;
  }

  createSession(handoff: Omit<SessionHandoff, "expiresAt">): string {
    this.purge();
    const code = randomBytes(32).toString("base64url");
    this.sessions.set(code, { ...handoff, expiresAt: this.now() + this.ttlMs });
    return code;
  }

  consumeSession(code: string): SessionHandoff | null {
    this.purge();
    const record = this.sessions.get(code);
    if (!record) return null;
    this.sessions.delete(code);
    return record;
  }

  private purge(): void {
    const now = this.now();
    for (const [key, value] of this.pending) if (value.expiresAt <= now) this.pending.delete(key);
    for (const [key, value] of this.sessions) if (value.expiresAt <= now) this.sessions.delete(key);
  }
}
