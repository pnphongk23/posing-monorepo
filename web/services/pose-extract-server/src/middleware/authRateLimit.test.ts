import type { NextFunction, Request, Response } from "express";
import { describe, expect, it } from "vitest";

import { createAuthRateLimitMiddleware, emailRateLimitKey } from "./authRateLimit";

interface MiddlewareResult {
  statusCode: number | null;
  nextCalled: boolean;
  errorCode: string | null;
}

function runMiddleware(
  middleware: (req: Request, res: Response, next: NextFunction) => void,
  req: Partial<Request> & { body?: unknown }
): MiddlewareResult {
  let statusCode: number | null = null;
  let errorCode: string | null = null;
  let nextCalled = false;

  const res = {
    status(code: number) {
      statusCode = code;
      return this;
    },
    json(payload: { error?: { code?: string } }) {
      errorCode = payload.error?.code ?? null;
      return this;
    }
  } as unknown as Response;

  const next = () => {
    nextCalled = true;
  };

  middleware(req as Request, res, next);
  return { statusCode, nextCalled, errorCode };
}

function signInReq(ip: string, email: string): Partial<Request> & { body?: unknown } {
  return { ip, body: { email, password: "pw" } };
}

describe("createAuthRateLimitMiddleware", () => {
  it("allows up to 10 requests per ip+email within the window", () => {
    const middleware = createAuthRateLimitMiddleware({ maxPerEmail: 10, maxPerIp: 100 });

    for (let i = 0; i < 10; i += 1) {
      expect(runMiddleware(middleware, signInReq("10.0.0.1", "user@example.test")).nextCalled).toBe(true);
    }
    const eleventh = runMiddleware(middleware, signInReq("10.0.0.1", "user@example.test"));
    expect(eleventh.nextCalled).toBe(false);
    expect(eleventh.statusCode).toBe(429);
    expect(eleventh.errorCode).toBe("RATE_LIMITED");
  });

  it("applies the per-IP 30 bucket across different emails", () => {
    const middleware = createAuthRateLimitMiddleware({ maxPerEmail: 10, maxPerIp: 30 });

    for (let i = 0; i < 30; i += 1) {
      const result = runMiddleware(middleware, signInReq("10.0.0.2", `user-${i}@example.test`));
      expect(result.nextCalled).toBe(true);
    }
    const blockedByIp = runMiddleware(middleware, signInReq("10.0.0.2", "fresh@example.test"));
    expect(blockedByIp.nextCalled).toBe(false);
    expect(blockedByIp.errorCode).toBe("RATE_LIMITED");

    const otherIp = runMiddleware(middleware, signInReq("10.0.0.3", "user-0@example.test"));
    expect(otherIp.nextCalled).toBe(true);
  });

  it("shares the per-email bucket globally across different ips", () => {
    const middleware = createAuthRateLimitMiddleware({ maxPerEmail: 1, maxPerIp: 100 });

    expect(runMiddleware(middleware, signInReq("10.0.0.4", "same@example.test")).nextCalled).toBe(true);
    const blockedSameEmailOtherIp = runMiddleware(middleware, signInReq("10.0.0.5", "same@example.test"));
    expect(blockedSameEmailOtherIp.statusCode).toBe(429);
    expect(blockedSameEmailOtherIp.errorCode).toBe("RATE_LIMITED");

    const freshEmailSameIp = runMiddleware(middleware, signInReq("10.0.0.5", "other@example.test"));
    expect(freshEmailSameIp.nextCalled).toBe(true);
  });

  it("resets counters after the window expires (injected nowProvider)", () => {
    let now = 1_000;
    const middleware = createAuthRateLimitMiddleware({
      windowMs: 500,
      maxPerEmail: 1,
      maxPerIp: 100,
      nowProvider: () => now
    });

    expect(runMiddleware(middleware, signInReq("10.0.0.6", "user@example.test")).nextCalled).toBe(true);
    expect(runMiddleware(middleware, signInReq("10.0.0.6", "user@example.test")).statusCode).toBe(429);

    now = 1_600;
    expect(runMiddleware(middleware, signInReq("10.0.0.6", "user@example.test")).nextCalled).toBe(true);
  });

  it("sweeps expired counters via onSweep and accepts an injected keyProvider", () => {
    let now = 1_000;
    const sweepSizes: number[] = [];
    const middleware = createAuthRateLimitMiddleware({
      windowMs: 100,
      maxPerEmail: 1,
      maxPerIp: 1,
      cleanupEveryRequests: 1,
      nowProvider: () => now,
      keyProvider: (req) => ({ ip: String((req as Request & { testIp?: string }).testIp ?? "unknown"), email: "fixed@example.test" }),
      onSweep: (active) => sweepSizes.push(active)
    });

    const reqA = { testIp: "ip-a", body: {} } as unknown as Request;
    const reqB = { testIp: "ip-b", body: {} } as unknown as Request;
    runMiddleware(middleware, reqA);
    runMiddleware(middleware, reqB);
    expect(sweepSizes.at(-1)).toBe(2);

    now = 1_200;
    const reqC = { testIp: "ip-c", body: {} } as unknown as Request;
    runMiddleware(middleware, reqC);
    expect(sweepSizes.at(-1)).toBe(0);
  });

  it("produces a stable sha256-based email key", () => {
    expect(emailRateLimitKey("user@example.test")).toBe(emailRateLimitKey("user@example.test"));
    expect(emailRateLimitKey("user@example.test")).toHaveLength(64);
    expect(emailRateLimitKey("user@example.test")).not.toBe(emailRateLimitKey("other@example.test"));
  });
});
