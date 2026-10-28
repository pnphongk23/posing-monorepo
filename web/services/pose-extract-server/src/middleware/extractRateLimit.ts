import type { NextFunction, Request, Response } from "express";

import { RateLimitedError } from "../services/errors";

interface ExtractRateLimitOptions {
  windowMs?: number;
  maxRequests?: number;
  cleanupEveryRequests?: number;
  nowProvider?: () => number;
  keyProvider?: (req: Request) => string;
  onSweep?: (activeCounters: number) => void;
  message?: string;
}

interface CounterEntry {
  count: number;
  startedAtMs: number;
}

const DEFAULT_WINDOW_MS = 60_000;
const DEFAULT_MAX_REQUESTS = 10;
const DEFAULT_CLEANUP_EVERY_REQUESTS = 100;

export function createExtractRateLimitMiddleware(options: ExtractRateLimitOptions = {}) {
  const windowMs = options.windowMs ?? DEFAULT_WINDOW_MS;
  const maxRequests = options.maxRequests ?? DEFAULT_MAX_REQUESTS;
  const cleanupEveryRequests = Math.max(options.cleanupEveryRequests ?? DEFAULT_CLEANUP_EVERY_REQUESTS, 1);
  const nowProvider = options.nowProvider ?? Date.now;
  const keyProvider = options.keyProvider ?? ((req: Request) => req.ip || "unknown");
  const onSweep = options.onSweep;
  const message = options.message ?? "Too many extract requests";
  const counters = new Map<string, CounterEntry>();
  let seenRequests = 0;

  const sweepExpiredCounters = (now: number): void => {
    for (const [key, counter] of counters.entries()) {
      if (now - counter.startedAtMs >= windowMs) {
        counters.delete(key);
      }
    }
    onSweep?.(counters.size);
  };

  return (req: Request, _res: Response, next: NextFunction): void => {
    const now = nowProvider();
    seenRequests += 1;
    if (seenRequests % cleanupEveryRequests === 0) {
      sweepExpiredCounters(now);
    }

    const key = keyProvider(req);
    const current = counters.get(key);

    if (!current || now - current.startedAtMs >= windowMs) {
      counters.set(key, { count: 1, startedAtMs: now });
      next();
      return;
    }

    current.count += 1;
    if (current.count > maxRequests) {
      next(new RateLimitedError(message));
      return;
    }

    next();
  };
}
