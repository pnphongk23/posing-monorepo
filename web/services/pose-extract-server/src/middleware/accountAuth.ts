import { createVerify, createPublicKey } from "node:crypto";
import type { NextFunction, Request, Response } from "express";

import type { AccountRecord, AccountStore } from "../db/accountStore";

export interface AccountAuthOptions {
  supabaseUrl: string;
  keyId: string;
  accountStore: AccountStore;
  fetchJwks?: typeof fetch;
  now?: () => number;
}

interface JwtClaims {
  iss?: unknown;
  aud?: unknown;
  exp?: unknown;
  sub?: unknown;
  email?: unknown;
  user_metadata?: unknown;
  name?: unknown;
}

interface Jwk {
  kty: string;
  n?: string;
  e?: string;
  x?: string;
  y?: string;
  alg?: string;
  kid?: string;
  crv?: string;
  use?: string;
}

function unauthorized(res: Response): void {
  res.status(401).json({ error: { code: "UNAUTHORIZED", message: "Unauthorized" } });
}

function decodePart(value: string): unknown {
  return JSON.parse(Buffer.from(value, "base64url").toString("utf8"));
}

function displayNameFromClaims(claims: JwtClaims, sub: string): string {
  const metadata = claims.user_metadata;
  if (metadata && typeof metadata === "object") {
    const candidate = (metadata as Record<string, unknown>).full_name ?? (metadata as Record<string, unknown>).name;
    if (typeof candidate === "string" && candidate.trim()) return candidate.trim();
  }
  if (typeof claims.name === "string" && claims.name.trim()) return claims.name.trim();
  if (typeof claims.email === "string" && claims.email.trim()) return claims.email.trim();
  return sub;
}

async function verifyJwt(token: string, options: AccountAuthOptions): Promise<JwtClaims> {
  const parts = token.split(".");
  if (parts.length !== 3) throw new Error("malformed token");
  const header = decodePart(parts[0]) as { alg?: unknown; kid?: unknown };
  const claims = decodePart(parts[1]) as JwtClaims;
  const algorithm = header.alg;
  const tokenKid = header.kid;
  if (typeof algorithm !== "string" || !["ES256", "RS256"].includes(algorithm)) throw new Error("unsupported algorithm");
  if (typeof tokenKid !== "string" || tokenKid.toLowerCase() !== options.keyId.toLowerCase()) throw new Error("wrong key id");
  const issuer = `${options.supabaseUrl.replace(/\/$/, "")}/auth/v1`;
  if (claims.iss !== issuer || (claims.aud !== "authenticated" && !(Array.isArray(claims.aud) && claims.aud.includes("authenticated")))) throw new Error("wrong claims");
  if (typeof claims.exp !== "number" || !Number.isFinite(claims.exp) || claims.exp <= (options.now?.() ?? Date.now() / 1000)) throw new Error("expired token");
  if (typeof claims.sub !== "string" || !claims.sub.trim()) throw new Error("missing subject");

  const response = await (options.fetchJwks ?? fetch)(`${options.supabaseUrl.replace(/\/$/, "")}/auth/v1/.well-known/jwks.json`);
  if (!response.ok) throw new Error("jwks unavailable");
  const payload = (await response.json()) as { keys?: Jwk[] };
  const jwk = payload.keys?.find((key) => key.kid?.toLowerCase() === tokenKid.toLowerCase());
  if (!jwk || jwk.alg !== algorithm || jwk.use === "enc" || (algorithm === "ES256" && (jwk.kty !== "EC" || jwk.crv !== "P-256")) || (algorithm === "RS256" && jwk.kty !== "RSA")) throw new Error("key mismatch");
  const publicKey = createPublicKey({ key: jwk, format: "jwk" });
  const verifier = createVerify("sha256");
  verifier.update(`${parts[0]}.${parts[1]}`);
  verifier.end();
  const valid = verifier.verify({ key: publicKey, dsaEncoding: algorithm === "ES256" ? "ieee-p1363" : "der" }, Buffer.from(parts[2], "base64url"));
  if (!valid) throw new Error("invalid signature");
  return claims;
}

declare global {
  namespace Express { interface Request { account?: AccountRecord } }
}

export function createAccountAuthMiddleware(options: AccountAuthOptions) {
  return async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    const match = req.header("authorization")?.match(/^\s*Bearer\s+([^\s]+)\s*$/i);
    if (!match) return unauthorized(res);
    try {
      const claims = await verifyJwt(match[1], options);
      req.account = await options.accountStore.upsert({ id: claims.sub as string, displayName: displayNameFromClaims(claims, claims.sub as string) });
      next();
    } catch {
      unauthorized(res);
    }
  };
}

export { verifyJwt };
