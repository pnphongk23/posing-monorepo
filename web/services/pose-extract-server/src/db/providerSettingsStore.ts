import type { Sql } from "./connection";
import { isExtractionProviderId, type ExtractionProviderId } from "../services/poseExtractorProvider";

const EXTRACTION_PROVIDER_KEY = "extraction_provider";

export class ProviderSettingsStore {
  constructor(private readonly db: Sql) {}

  async getActiveProvider(): Promise<ExtractionProviderId> {
    const rows = (await this.db`
      SELECT value FROM app_settings WHERE key = ${EXTRACTION_PROVIDER_KEY}
    `) as Array<{ value: string }>;

    const row = rows[0];
    if (!row || !isExtractionProviderId(row.value)) {
      return "gemini_native";
    }

    return row.value;
  }

  async setProvider(provider: ExtractionProviderId): Promise<ExtractionProviderId> {
    await this.db`
      INSERT INTO app_settings (key, value, updated_at)
      VALUES (${EXTRACTION_PROVIDER_KEY}, ${provider}, NOW())
      ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = NOW()
    `;

    return provider;
  }
}
