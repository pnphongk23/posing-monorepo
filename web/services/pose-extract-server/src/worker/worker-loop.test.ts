import { describe, expect, it, vi } from "vitest";

import type { ExtractionJobStore } from "../db/extractionJobStore";
import type { ProviderSettingsStore } from "../db/providerSettingsStore";
import type { ExtractionProviderId, PoseExtractorProvider } from "../services/poseExtractorProvider";
import {
  describeError,
  INITIAL_BACKOFF_MS,
  MAX_BACKOFF_MS,
  nextBackoff,
  runWorkerLoop
} from "./worker-loop";

const dummyProvider: PoseExtractorProvider = {
  id: "gemini_native",
  extractPoseImage: async () => {
    throw new Error("unused in loop tests");
  }
};

const baseDeps = {
  jobStore: {} as unknown as ExtractionJobStore,
  providerSettingsStore: {} as unknown as ProviderSettingsStore,
  createProvider: (() => dummyProvider) as (providerId: ExtractionProviderId) => PoseExtractorProvider,
  staleLockSeconds: 120,
  pollIntervalMs: 0
};

// Scripted processNextJob: each step either resolves with a boolean or throws.
interface Step {
  result?: boolean;
  throws?: Error;
}
function scriptedJob(script: Step[]) {
  let index = 0;
  const fn = vi.fn(async () => {
    const step = script[index] ?? { result: true };
    index += 1;
    if (step.throws) {
      throw step.throws;
    }
    return step.result ?? true;
  });
  return { fn, getCalls: () => fn.mock.calls.length };
}

function recordingSleep() {
  const durations: number[] = [];
  const fn = vi.fn(async (ms: number) => {
    durations.push(ms);
  });
  return { fn, durations };
}

describe("runWorkerLoop", () => {
  it("contains a failing poll iteration and retries without crashing", async () => {
    const job = scriptedJob([{ throws: new Error("boom 26000") }, { result: true }]);
    const { fn: sleepFn, durations } = recordingSleep();

    await expect(
      runWorkerLoop({
        ...baseDeps,
        processNextJob: job.fn,
        sleep: sleepFn,
        isShuttingDown: () => job.getCalls() >= 2
      })
    ).resolves.toBeUndefined();

    // First iteration threw (caught + retried); second succeeded -> 2 calls, 1 backoff sleep.
    expect(job.getCalls()).toBe(2);
    expect(durations).toEqual([INITIAL_BACKOFF_MS]);
  });

  it("backs off doubling from 1s and caps at 30s", async () => {
    const job = scriptedJob(Array.from({ length: 7 }, () => ({ throws: new Error("transient") })));
    const { fn: sleepFn, durations } = recordingSleep();

    await runWorkerLoop({
      ...baseDeps,
      processNextJob: job.fn,
      sleep: sleepFn,
      isShuttingDown: () => job.getCalls() >= 7
    });

    expect(durations).toEqual([1000, 2000, 4000, 8000, 16_000, 30_000, 30_000]);
  });

  it("resets backoff after a successful iteration", async () => {
    const job = scriptedJob([{ throws: new Error("e1") }, { result: true }, { throws: new Error("e2") }]);
    const { fn: sleepFn, durations } = recordingSleep();

    await runWorkerLoop({
      ...baseDeps,
      processNextJob: job.fn,
      sleep: sleepFn,
      isShuttingDown: () => job.getCalls() >= 3
    });

    // After the success, the next failure must sleep the INITIAL backoff, not the doubled one.
    expect(durations).toEqual([INITIAL_BACKOFF_MS, INITIAL_BACKOFF_MS]);
  });

  it("stops promptly when shutdown is requested (graceful-exit predicate)", async () => {
    const processNextJob = vi.fn(async () => true);
    const { fn: sleepFn } = recordingSleep();
    let calls = 0;

    await runWorkerLoop({
      ...baseDeps,
      processNextJob: vi.fn(async () => {
        calls += 1;
        return true;
      }),
      sleep: sleepFn,
      isShuttingDown: () => calls >= 2
    });

    expect(processNextJob).not.toHaveBeenCalled();
    expect(calls).toBe(2);
  });
});

describe("nextBackoff", () => {
  it("doubles and caps at MAX_BACKOFF_MS", () => {
    expect(nextBackoff(1000)).toBe(2000);
    expect(nextBackoff(16_000)).toBe(30_000);
    expect(nextBackoff(MAX_BACKOFF_MS)).toBe(MAX_BACKOFF_MS);
  });
});

describe("describeError", () => {
  it("extracts stable fields and redacts connection strings", () => {
    class FakePostgresError extends Error {
      code = "26000";
      constructor(message: string) {
        super(message);
        this.name = "PostgresError";
      }
    }

    const info = describeError(
      new FakePostgresError("session reset: postgres://user:secret@db.host:6543/postgres")
    );

    expect(info.name).toBe("PostgresError");
    expect(info.code).toBe("26000");
    expect(info.message).not.toContain("secret");
    expect(info.message).not.toContain("postgres://user:secret@");
    expect(info.message).toContain("***:***@");
  });

  it("handles non-Error values without leaking secrets", () => {
    const info = describeError("postgres://admin:pass@host:6543/x");
    expect(info.name).toBe("UnknownError");
    expect(info.code).toBeNull();
    expect(info.message).not.toContain("pass");
  });
});
