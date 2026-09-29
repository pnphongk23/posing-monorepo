import { timingSafeEqual } from "node:crypto";
import type { NextFunction, Request, RequestHandler, Response } from "express";

export interface AccountOrAdminAuthOptions {
  adminSecret?: string;
  accountAuth?: RequestHandler;
}

declare global {
  namespace Express {
    interface Request {
      isAdmin?: boolean;
    }
  }
}

function unauthorized(res: Response): void {
  res.status(401).json({
    error: {
      code: "UNAUTHORIZED",
      message: "Unauthorized"
    }
  });
}

function safeCompare(a: string, b: string): boolean {
  const bufA = Buffer.from(a);
  const bufB = Buffer.from(b);
  if (bufA.length !== bufB.length) {
    return false;
  }
  return timingSafeEqual(bufA, bufB);
}

export function createAccountOrAdminAuth(options: AccountOrAdminAuthOptions): RequestHandler {
  return (req: Request, res: Response, next: NextFunction): void => {
    const authHeader = req.header("authorization");
    const match = authHeader?.match(/^\s*Bearer\s+(.+)\s*$/i);
    if (match && options.adminSecret) {
      const token = match[1].trim();
      if (token && safeCompare(token, options.adminSecret)) {
        req.isAdmin = true;
        next();
        return;
      }
    }

    if (options.accountAuth) {
      options.accountAuth(req, res, next);
      return;
    }

    unauthorized(res);
  };
}
