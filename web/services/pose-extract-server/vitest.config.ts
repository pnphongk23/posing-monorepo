import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "node",
    include: ["src/**/*.test.ts"],
    testTimeout: 60000,
    maxConcurrency: 4,
    coverage: {
      enabled: false
    }
  }
});
