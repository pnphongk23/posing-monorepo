import { createHash } from "node:crypto";
import { Router } from "express";
import type { NextFunction, Request, Response } from "express";
import { z } from "zod";

import type { AccountStore } from "../db/accountStore";
import { verifyJwt } from "../middleware/accountAuth";
import { createAuthRateLimitMiddleware } from "../middleware/authRateLimit";
import { PendingAuthStore } from "../services/pendingAuthStore";

const GOOGLE_PROVIDER = "google";
const PENDING_VALIDATION = { error: { code: "AUTH_PENDING_VALIDATION", message: "OAuth exchange is pending runtime validation" } };
const INVALID_CREDENTIALS = { error: { code: "INVALID_CREDENTIALS", message: "Incorrect email or password" } };
const EMAIL_NOT_CONFIRMED = { error: { code: "EMAIL_NOT_CONFIRMED", message: "Confirm your email address" } };
const RATE_LIMITED = { error: { code: "RATE_LIMITED", message: "Too many sign-in attempts" } };
const SIGNIN_UNAVAILABLE = { error: { code: "AUTH_PENDING_VALIDATION", message: "Sign-in is temporarily unavailable" } };
const UNAUTHORIZED = { error: { code: "UNAUTHORIZED", message: "Unauthorized" } };

const signInSchema = z.object({
  email: z.string().trim().email(),
  password: z.string().min(1)
});

const appleSignInSchema = z.object({
  identityToken: z.string().min(1),
  nonce: z.string().min(8).max(512),
  fullName: z.string().trim().optional()
});

export interface AccountAuthRoutesOptions {
  supabaseUrl: string;
  anonKey?: string;
  backendPublicUrl?: string;
  keyId?: string;
  accountStore?: AccountStore;
  pendingAuthStore?: PendingAuthStore;
  fetchImpl?: typeof fetch;
  fetchJwks?: typeof fetch;
  authRateLimitWindowMs?: number;
  authRateLimitMaxPerEmail?: number;
  authRateLimitMaxPerIp?: number;
}

interface SupabaseTokenResponse {
  access_token?: unknown;
  refresh_token?: unknown;
  error?: unknown;
  error_description?: unknown;
  error_code?: unknown;
  msg?: unknown;
  code?: unknown;
}

function unavailable(res: { status: (code: number) => { json: (body: unknown) => void } }): void {
  res.status(503).json(PENDING_VALIDATION);
}

function emailNotConfirmed(payload: SupabaseTokenResponse): boolean {
  const candidates = [payload.error_code, payload.code, payload.error, payload.error_description, payload.msg]
    .filter((value): value is string | number => typeof value === "string" || typeof value === "number")
    .map((value) => String(value).toLowerCase());
  return candidates.some((value) => value.includes("email_not_confirmed") || value.includes("email not confirmed"));
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
  const emailRateLimit = createAuthRateLimitMiddleware({
    windowMs: options.authRateLimitWindowMs,
    maxPerEmail: options.authRateLimitMaxPerEmail,
    maxPerIp: options.authRateLimitMaxPerIp
  });
  const appleRateLimit = createAuthRateLimitMiddleware({
    windowMs: options.authRateLimitWindowMs,
    maxPerEmail: options.authRateLimitMaxPerEmail,
    maxPerIp: options.authRateLimitMaxPerIp,
    keyProvider: (req) => ({ ip: req.ip || "unknown", email: `apple:${req.ip || "unknown"}` })
  });

  router.get("/google/start", (req, res) => {
    if (!authReady) return unavailable(res);
    const redirectUri = callbackUri(options.backendPublicUrl!);
    const pending = options.pendingAuthStore!.create(redirectUri);
    const challenge = createHash("sha256").update(pending.codeVerifier).digest("base64url");
    const url = new URL(`${supabaseUrl}/auth/v1/authorize`);
    url.searchParams.set("provider", GOOGLE_PROVIDER);
    const redirectTo = new URL(redirectUri);
    redirectTo.searchParams.set("oauth_tx", pending.transactionId);
    url.searchParams.set("redirect_to", redirectTo.toString());
    url.searchParams.set("code_challenge", challenge);
    url.searchParams.set("code_challenge_method", "S256");
    void req;
    res.redirect(url.toString());
  });

  router.get("/google/callback", async (req, res) => {
    if (!authReady) return unavailable(res);
    const transactionId = typeof req.query.oauth_tx === "string" ? req.query.oauth_tx : "";
    const code = typeof req.query.code === "string" ? req.query.code : "";
    if (!transactionId || !code) {
      res.status(401).json({ error: { code: "UNAUTHORIZED", message: "Unauthorized" } });
      return;
    }
    const pending = options.pendingAuthStore!.consumeTransaction(transactionId);
    if (!pending) {
      res.status(401).json({ error: { code: "UNAUTHORIZED", message: "Unauthorized" } });
      return;
    }
    try {
      const response = await fetchImpl(`${supabaseUrl}/auth/v1/token?grant_type=pkce`, {
        method: "POST",
        headers: { apikey: options.anonKey!, "content-type": "application/json" },
        body: JSON.stringify({ auth_code: code, code_verifier: pending.codeVerifier })
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

  const emailSignInAvailability = (_req: Request, res: Response, next: NextFunction): void => {
    if (!options.anonKey || !options.accountStore || !options.keyId) {
      res.status(503).json(PENDING_VALIDATION);
      return;
    }
    next();
  };

  router.post("/email/signin", emailSignInAvailability, emailRateLimit, async (req, res) => {
    const anonKey = options.anonKey!;
    const accountStore = options.accountStore!;
    const keyId = options.keyId!;
    const parsed = signInSchema.safeParse(req.body ?? {});
    if (!parsed.success) {
      const messages = parsed.error.issues.map((issue) => `${issue.path.join(".")}: ${issue.message}`).join(", ");
      res.status(400).json({ error: { code: "BAD_REQUEST", message: messages } });
      return;
    }
    const { email, password } = parsed.data;

    let response: Awaited<ReturnType<typeof fetchImpl>>;
    try {
      response = await fetchImpl(`${supabaseUrl}/auth/v1/token?grant_type=password`, {
        method: "POST",
        headers: { apikey: anonKey, "content-type": "application/json" },
        body: JSON.stringify({ email, password })
      });
    } catch {
      res.status(503).json(SIGNIN_UNAVAILABLE);
      return;
    }
    try {
      // Checked BEFORE parsing: an edge/CDN rate limit (Cloudflare in front of Supabase) answers
      // 429 with an HTML block page, so `response.json()` would throw and the outer catch would
      // report a rate-limited reviewer as a wrong password — the exact failure this branch exists
      // to prevent. Never let a parse failure decide between 429 and 401.
      if (response.status === 429) {
        res.status(429).json(RATE_LIMITED);
        return;
      }
      const payload = await response.json() as SupabaseTokenResponse;
      if (!response.ok) {
        if (emailNotConfirmed(payload)) {
          res.status(403).json(EMAIL_NOT_CONFIRMED);
          return;
        }
        res.status(401).json(INVALID_CREDENTIALS);
        return;
      }
      if (typeof payload.access_token !== "string" || typeof payload.refresh_token !== "string") {
        res.status(401).json(INVALID_CREDENTIALS);
        return;
      }
      const claims = await verifyJwt(payload.access_token, {
        supabaseUrl,
        keyId,
        accountStore,
        fetchJwks: options.fetchJwks
      });
      const account = await accountStore.upsert({ id: claims.sub as string, displayName: accountDisplayName(claims, claims.sub as string) });
      res.json({ accessToken: payload.access_token, refreshToken: payload.refresh_token, account });
    } catch {
      res.status(401).json(INVALID_CREDENTIALS);
    }
  });

  router.post("/apple/signin", emailSignInAvailability, appleRateLimit, async (req, res) => {
    const anonKey = options.anonKey!;
    const accountStore = options.accountStore!;
    const keyId = options.keyId!;
    const parsed = appleSignInSchema.safeParse(req.body ?? {});
    if (!parsed.success) {
      const messages = parsed.error.issues.map((issue) => `${issue.path.join(".")}: ${issue.message}`).join(", ");
      res.status(400).json({ error: { code: "BAD_REQUEST", message: messages } });
      return;
    }

    try {
      const response = await fetchImpl(`${supabaseUrl}/auth/v1/token?grant_type=id_token`, {
        method: "POST",
        headers: { apikey: anonKey, "content-type": "application/json" },
        body: JSON.stringify({ provider: "apple", id_token: parsed.data.identityToken, nonce: parsed.data.nonce })
      });
      if (!response.ok) {
        res.status(401).json(UNAUTHORIZED);
        return;
      }
      const payload = await response.json() as SupabaseTokenResponse;
      if (typeof payload.access_token !== "string" || !payload.access_token || typeof payload.refresh_token !== "string" || !payload.refresh_token) {
        res.status(401).json(UNAUTHORIZED);
        return;
      }
      const claims = await verifyJwt(payload.access_token, {
        supabaseUrl,
        keyId,
        accountStore,
        fetchJwks: options.fetchJwks
      });
      const account = await accountStore.upsert({
        id: claims.sub as string,
        displayName: parsed.data.fullName || accountDisplayName(claims, claims.sub as string)
      });
      res.json({ accessToken: payload.access_token, refreshToken: payload.refresh_token, account });
    } catch {
      res.status(401).json(UNAUTHORIZED);
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
        headers: { apikey: options.anonKey, "content-type": "application/json" },
        body: JSON.stringify({ refresh_token: refreshToken })
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
