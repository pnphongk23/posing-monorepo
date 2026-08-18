import { describe, expect, it } from "vitest";

import { setupTestDatabase } from "../db/testDb";
import { KeyStore } from "./keyStore";

async function createTestStore(): Promise<KeyStore> {
  const sql = await setupTestDatabase();
  return new KeyStore(sql);
}

describe("KeyStore", () => {
  it("creates and lists keys", async () => {
    const keyStore = await createTestStore();

    const created = await keyStore.createKey({
      name: "Primary",
      apiKey: "AIza-primary"
    });

    const keys = await keyStore.listKeys();
    expect(created.status).toBe("active");
    expect(created.requestsToday).toBe(0);
    expect(keys).toHaveLength(1);
    expect(keys[0]).toEqual(created);
  });

  it("updates key status and deletes key", async () => {
    const keyStore = await createTestStore();
    const created = await keyStore.createKey({
      name: "Secondary",
      apiKey: "AIza-secondary"
    });

    const updated = await keyStore.updateKeyStatus(created.id, "disabled");
    const wasDeleted = await keyStore.deleteKey(created.id);

    expect(updated?.status).toBe("disabled");
    expect(wasDeleted).toBe(true);
    expect(await keyStore.listKeys()).toHaveLength(0);
  });

  it("resets requests_today and only reactivates exhausted keys", async () => {
    const keyStore = await createTestStore();
    const active = await keyStore.createKey({ name: "A", apiKey: "key-a" });
    const exhausted = await keyStore.createKey({ name: "B", apiKey: "key-b" });
    const disabled = await keyStore.createKey({ name: "C", apiKey: "key-c" });

    await keyStore.incrementRequestsToday(active.id);
    await keyStore.incrementRequestsToday(exhausted.id);
    await keyStore.incrementRequestsToday(disabled.id);
    await keyStore.updateKeyStatus(exhausted.id, "exhausted");
    await keyStore.updateKeyStatus(disabled.id, "disabled");

    const affectedRows = await keyStore.resetDailyCounters();
    const keys = await keyStore.listKeys();

    const activeAfterReset = keys.find((item) => item.id === active.id);
    const exhaustedAfterReset = keys.find((item) => item.id === exhausted.id);
    const disabledAfterReset = keys.find((item) => item.id === disabled.id);

    expect(affectedRows).toBe(3);
    expect(activeAfterReset?.requestsToday).toBe(0);
    expect(activeAfterReset?.status).toBe("active");
    expect(exhaustedAfterReset?.requestsToday).toBe(0);
    expect(exhaustedAfterReset?.status).toBe("active");
    expect(disabledAfterReset?.requestsToday).toBe(0);
    expect(disabledAfterReset?.status).toBe("disabled");
  });
});
