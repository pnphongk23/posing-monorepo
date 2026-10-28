import fs from "node:fs";
import path from "node:path";

import { describe, expect, it } from "vitest";

const SRC_ROOT = path.resolve(process.cwd(), "src");

/** Production sources only: test files hold deliberate placeholders and fixtures hold samples. */
function productionSources(directory: string = SRC_ROOT): string[] {
  const files: string[] = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const full = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      if (entry.name === "__fixtures__") {
        continue;
      }
      files.push(...productionSources(full));
      continue;
    }
    if (entry.isFile() && entry.name.endsWith(".ts") && !entry.name.endsWith(".test.ts")) {
      files.push(full);
    }
  }
  return files;
}

describe("subscription credentials stay out of source", () => {
  it("never commits a configured credential value under src/", () => {
    const configured = Object.entries(process.env).filter(
      ([name, value]) => name.startsWith("REVENUECAT_") && typeof value === "string" && value.length >= 8
    );
    const sources = productionSources().map((file) => ({ file, contents: fs.readFileSync(file, "utf-8") }));

    expect(sources.length).toBeGreaterThan(0);
    for (const [name, value] of configured) {
      const leaks = sources.filter((source) => source.contents.includes(value as string)).map((source) => source.file);
      expect(leaks, `${name} value was found in source`).toEqual([]);
    }
  });

  it("never commits a platform secret key literal under src/", () => {
    const secretKeyPattern = /\bsk_[A-Za-z0-9]{16,}/;
    const leaks = productionSources().filter((file) => secretKeyPattern.test(fs.readFileSync(file, "utf-8")));

    expect(leaks).toEqual([]);
  });

  it("reads every credential from the environment by name", () => {
    const envSource = fs.readFileSync(path.join(SRC_ROOT, "config/env.ts"), "utf-8");

    for (const name of ["REVENUECAT_WEBHOOK_AUTH", "REVENUECAT_SECRET_API_KEY", "REVENUECAT_ENTITLEMENT_ID"]) {
      expect(envSource).toContain(name);
    }
  });
});
