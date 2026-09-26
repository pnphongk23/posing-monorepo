import { createHash } from "node:crypto";
import type { NextFunction, Request, Response } from "express";

interface AuthRateLimitOptions {
  windowMs?: number;
  maxPerEmail?: number;
  maxPerIp?: number;
  cleanupEveryRequests?: number;
  nowProvider?: () => number;
  keyProvider?: (req: Request) => { ip: string; email: string };
  onSweep?: (activeCounters: number) => void;
}

interface CounterEntry {
  count: number;
  startedAtMs: number;
}

const DEFAULT_WINDOW_MS = 900_000;
const DEFAULT_MAX_PER_EMAIL = 10;
const DEFAULT_MAX_PER_IP = 30;
const DEFAULT_CLEANUP_EVERY_REQUESTS = 100;

export function emailRateLimitKey(email: string): string {
  return createHash("sha256").update(email).digest("hex");
}

function tooManyRequests(res: Response): void {
  res.status(429).json({
    error: {
      code: "RATE_LIMITED",
      message: "Too many sign-in attempts"
    }
  });
}

export function createAuthRateLimitMiddleware(options: AuthRateLimitOptions = {}) {
  // The per-email bucket is GLOBAL (keyed by sha256(email) alone, no ip component):
  // with `trust proxy` an attacker can rotate X-Forwarded-For to mint fresh per-ip
  // counters, so distributed brute force against one account must be capped by the
  // email bucket alone. The per-ip bucket still caps a single abusive host.
  const windowMs = options.windowMs ?? DEFAULT_WINDOW_MS;
  const maxPerEmail = options.maxPerEmail ?? DEFAULT_MAX_PER_EMAIL;
  const maxPerIp = options.maxPerIp ?? DEFAULT_MAX_PER_IP;
  const cleanupEveryRequests = Math.max(options.cleanupEveryRequests ?? DEFAULT_CLEANUP_EVERY_REQUESTS, 1);
  const nowProvider = options.nowProvider ?? Date.now;
  const keyProvider = options.keyProvider ?? ((req: Request) => ({
    ip: req.ip || "unknown",
    email: typeof req.body?.email === "string" ? req.body.email.toLowerCase() : ""
  }));
  const onSweep = options.onSweep;

  const emailCounters = new Map<string, CounterEntry>();
  const ipCounters = new Map<string, CounterEntry>();
  let seenRequests = 0;

  const sweepExpiredCounters = (now: number): void => {
    for (const [key, counter] of emailCounters.entries()) {
      if (now - counter.startedAtMs >= windowMs) {
        emailCounters.delete(key);
      }
    }
    for (const [key, counter] of ipCounters.entries()) {
      if (now - counter.startedAtMs >= windowMs) {
        ipCounters.delete(key);
      }
    }
    onSweep?.(emailCounters.size + ipCounters.size);
  };

  return (req: Request, res: Response, next: NextFunction): void => {
    const now = nowProvider();
    seenRequests += 1;
    if (seenRequests % cleanupEveryRequests === 0) {
      sweepExpiredCounters(now);
    }

    const { ip, email } = keyProvider(req);
    const emailKey = emailRateLimitKey(email);
    const ipKey = ip;

    let emailCounter = emailCounters.get(emailKey);
    if (!emailCounter || now - emailCounter.startedAtMs >= windowMs) {
      emailCounter = { count: 0, startedAtMs: now };
      emailCounters.set(emailKey, emailCounter);
    }
    let ipCounter = ipCounters.get(ipKey);
    if (!ipCounter || now - ipCounter.startedAtMs >= windowMs) {
      ipCounter = { count: 0, startedAtMs: now };
      ipCounters.set(ipKey, ipCounter);
    }

    if (ipCounter.count + 1 > maxPerIp || emailCounter.count + 1 > maxPerEmail) {
      tooManyRequests(res);
      return;
    }

    emailCounter.count += 1;
    ipCounter.count += 1;
    next();
  };
}
