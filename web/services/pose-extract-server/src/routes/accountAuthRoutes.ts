import { createHash } from "node:crypto";
import { Router } from "express";

import type { AccountStore } from "../db/accountStore";
import { verifyJwt } from "../middleware/accountAuth";
import { PendingAuthStore } from "../services/pendingAuthStore";

const GOOGLE_PROVIDER = "google";
const PENDING_VALIDATION = { error: { code: "AUTH_PENDING_VALIDATION", message: "OAuth exchange is pending runtime validation" } };

export interface AccountAuthRoutesOptions {
  supabaseUrl: string;
  anonKey?: string;
  backendPublicUrl?: string;
  keyId?: string;
  accountStore?: AccountStore;
  pendingAuthStore?: PendingAuthStore;
  fetchImpl?: typeof fetch;
  fetchJwks?: typeof fetch;
}

function unavailable(res: { status: (code: number) => { json: (body: unknown) => void } }): void {
  res.status(503).json(PENDING_VALIDATION);
}

function callbackUri(publicUrl: string): string {
  return `${publicUrl.replace(/\/$/, "")}/api/auth/google/callback`;
}

function accountDisplayName(claims: { name?: unknown; email?: unknown; user_metadata?: unknown }, sub: string): string {
  const metadata = claims.user_metadata;
  if (metadata && typeof metadata === "object") {
    const value = (metadata as Record<string, unknown>).full_name ?? (metadata as Record<string, unknown>).name;
    if (typeof value === "string" && value.trim()) return value.trim();
  }
  if (typeof claims.name === "string" && claims.name.trim()) return claims.name.trim();
  if (typeof claims.email === "string" && claims.email.trim()) return claims.email.trim();
  return sub;
}

export function createAccountAuthRoutes(options: AccountAuthRoutesOptions): Router {
  const router = Router();
  const supabaseUrl = options.supabaseUrl.replace(/\/$/, "");
  const fetchImpl = options.fetchImpl ?? fetch;
  const authReady = Boolean(options.anonKey && options.backendPublicUrl && options.accountStore && options.pendingAuthStore && options.keyId);

  router.get("/google/start", (req, res) => {
    if (!authReady) return unavailable(res);
    const redirectUri = callbackUri(options.backendPublicUrl!);
    const pending = options.pendingAuthStore!.create(redirectUri);
    const challenge = createHash("sha256").update(pending.codeVerifier).digest("base64url");
    const url = new URL(`${supabaseUrl}/auth/v1/authorize`);
    url.searchParams.set("provider", GOOGLE_PROVIDER);
    url.searchParams.set("redirect_to", redirectUri);
    url.searchParams.set("state", pending.state);
    url.searchParams.set("code_challenge", challenge);
    url.searchParams.set("code_challenge_method", "S256");
    void req;
    res.redirect(url.toString());
  });

  router.get("/google/callback", async (req, res) => {
    if (!authReady) return unavailable(res);
    const state = typeof req.query.state === "string" ? req.query.state : "";
    const code = typeof req.query.code === "string" ? req.query.code : "";
    const pending = state ? options.pendingAuthStore!.consumeState(state) : null;
    if (!pending || !code) {
      res.status(401).json({ error: { code: "UNAUTHORIZED", message: "Unauthorized" } });
      return;
    }
    try {
      const response = await fetchImpl(`${supabaseUrl}/auth/v1/token?grant_type=authorization_code`, {
        method: "POST",
        headers: { apikey: options.anonKey!, "content-type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({ code, code_verifier: pending.codeVerifier, redirect_uri: pending.redirectUri }).toString()
      });
      if (!response.ok) throw new Error("OAuth exchange failed");
      const tokens = await response.json() as { access_token?: string; refresh_token?: string };
      if (!tokens.access_token || !tokens.refresh_token) throw new Error("OAuth response incomplete");
      const claims = await verifyJwt(tokens.access_token, {
        supabaseUrl,
        keyId: options.keyId!,
        accountStore: options.accountStore!,
        fetchJwks: options.fetchJwks
      });
      const account = await options.accountStore!.upsert({ id: claims.sub as string, displayName: accountDisplayName(claims, claims.sub as string) });
      const handoffCode = options.pendingAuthStore!.createSession({ accessToken: tokens.access_token, refreshToken: tokens.refresh_token, account });
      res.redirect(`aipose://auth/callback?code=${encodeURIComponent(handoffCode)}`);
    } catch {
      res.status(503).json(PENDING_VALIDATION);
    }
  });

  router.post("/session", (req, res) => {
    if (!options.pendingAuthStore) return unavailable(res);
    const code = typeof req.body?.code === "string" ? req.body.code : "";
    const session = code ? options.pendingAuthStore.consumeSession(code) : null;
    if (!session) {
      res.status(401).json({ error: { code: "UNAUTHORIZED", message: "Unauthorized" } });
      return;
    }
    res.json({ accessToken: session.accessToken, refreshToken: session.refreshToken, account: session.account });
  });

  router.post("/refresh", async (req, res) => {
    if (!options.anonKey || !options.accountStore || !options.keyId) return unavailable(res);
    const refreshToken = typeof req.body?.refreshToken === "string" ? req.body.refreshToken : "";
    if (!refreshToken) {
      res.status(401).json({ error: { code: "UNAUTHORIZED", message: "Unauthorized" } });
      return;
    }
    try {
      const response = await fetchImpl(`${supabaseUrl}/auth/v1/token?grant_type=refresh_token`, {
        method: "POST",
        headers: { apikey: options.anonKey, "content-type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({ refresh_token: refreshToken }).toString()
      });
      if (!response.ok) throw new Error("Refresh failed");
      const tokens = await response.json() as { access_token?: string; refresh_token?: string };
      if (!tokens.access_token || !tokens.refresh_token) throw new Error("Refresh response incomplete");
      const claims = await verifyJwt(tokens.access_token, { supabaseUrl, keyId: options.keyId, accountStore: options.accountStore, fetchJwks: options.fetchJwks });
      const account = await options.accountStore.upsert({ id: claims.sub as string, displayName: accountDisplayName(claims, claims.sub as string) });
      res.json({ accessToken: tokens.access_token, refreshToken: tokens.refresh_token, account });
    } catch {
      res.status(401).json({ error: { code: "UNAUTHORIZED", message: "Unauthorized" } });
    }
  });
  return router;
}
