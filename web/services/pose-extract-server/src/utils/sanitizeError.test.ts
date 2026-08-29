import { describe, expect, it } from "vitest";

import { sanitizeError, sanitizeErrorMessage } from "./sanitizeError";

describe("sanitizeError", () => {
  it("extracts stable fields and redacts connection strings from Error messages", () => {
    class FakePostgresError extends Error {
      code = "26000";
      constructor(message: string) {
        super(message);
        this.name = "PostgresError";
      }
    }

    const info = sanitizeError(
      new FakePostgresError("session reset: postgres://user:secret@db.host:6543/postgres")
    );

    expect(info.name).toBe("PostgresError");
    expect(info.code).toBe("26000");
    expect(info.message).not.toContain("secret");
    expect(info.message).not.toContain("postgres://user:secret@");
    expect(info.message).toContain("***:***@");
  });

  it("handles raw Error values without leaking secrets", () => {
    const info = sanitizeError("postgres://admin:pass@host:6543/x");
    expect(info.name).toBe("UnknownError");
    expect(info.code).toBeNull();
    expect(info.message).not.toContain("pass");
  });

  it("bounds the message length (e.g. Higgsfield CLI stderr/stdout)", () => {
    const longCliOutput = `CLI exited 1\n${"x".repeat(500)}`;
    const info = sanitizeError(new Error(longCliOutput));
    expect(info.name).toBe("Error");
    expect(info.code).toBeNull();
    expect(info.message.length).toBeLessThanOrEqual(200);
  });

  it("returns safe defaults for non-Error objects", () => {
    const info = sanitizeError({ foo: "bar" });
    expect(info.name).toBe("UnknownError");
    expect(info.code).toBeNull();
    expect(info.message).toBe("Unknown error");
  });

  it("does not include the raw error object in the result", () => {
    const err = new Error("boom");
    const info = sanitizeError(err);
    expect(info).not.toHaveProperty("stack");
    expect(info).not.toHaveProperty("query");
    expect(info).not.toHaveProperty("parameters");
  });
});

describe("sanitizeErrorMessage", () => {
  it("redacts connection strings and truncates", () => {
    const out = sanitizeErrorMessage("connect postgres://u:p@h:6543/db " + "z".repeat(400));
    expect(out).not.toContain("postgres://u:p@");
    expect(out).toContain("***:***@");
    expect(out.length).toBe(200);
  });
});
