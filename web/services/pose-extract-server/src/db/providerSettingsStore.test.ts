import { describe, expect, it } from "vitest";

import { setupTestDatabase } from "./testDb";
import { ProviderSettingsStore } from "./providerSettingsStore";

describe("ProviderSettingsStore", () => {
  it("defaults to gemini_native on fresh database", async () => {
    const sql = await setupTestDatabase();
    const store = new ProviderSettingsStore(sql);

    expect(await store.getActiveProvider()).toBe("gemini_native");
  });

  it("persists higgsfield_cli selection", async () => {
    const sql = await setupTestDatabase();
    const store = new ProviderSettingsStore(sql);

    await store.setProvider("higgsfield_cli");

    expect(await store.getActiveProvider()).toBe("higgsfield_cli");
  });
});
