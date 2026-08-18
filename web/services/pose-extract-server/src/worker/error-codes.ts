export const WORKER_ERROR_CODES = {
  providerError: "PROVIDER_ERROR",
  providerQuotaExceeded: "PROVIDER_QUOTA_EXCEEDED",
  providerCredentialsExhausted: "PROVIDER_CREDENTIALS_EXHAUSTED",
  providerAuthRequired: "PROVIDER_AUTH_REQUIRED",
  providerTimeout: "PROVIDER_TIMEOUT",
  providerCliFailed: "PROVIDER_CLI_FAILED",
  /** @deprecated Legacy Playwright browser worker path — not used by default extract worker */
  browserFlowFailed: "BROWSER_FLOW_FAILED",
  browserTimeout: "BROWSER_TIMEOUT",
  browserUploadFailed: "BROWSER_UPLOAD_FAILED",
  browserDownloadFailed: "BROWSER_DOWNLOAD_FAILED",
  browserAuthRequired: "BROWSER_AUTH_REQUIRED"
} as const;
