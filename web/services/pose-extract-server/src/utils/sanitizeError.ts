export interface SanitizedError {
  name: string;
  code: string | null;
  message: string;
}

// Redact connection-string-like substrings (scheme://user:pass@host), e.g.
// postgres://user:pass@host:6543/db or https://key@host. Higgsfield CLI errors
// may embed stderr/stdout; we never want credentials or user data in logs.
const CONNECTION_STRING_RE = /[a-zA-Z][a-zA-Z0-9+.-]*:\/\/[^:@\s/]+:[^@\s/]+@/g;
const MAX_MESSAGE_LENGTH = 200;

export function sanitizeErrorMessage(message: string): string {
  return message.replace(CONNECTION_STRING_RE, "***:***@").slice(0, MAX_MESSAGE_LENGTH);
}

// Convert any thrown value into stable, log-safe fields. Never includes the raw
// Error object, its query/parameters, stack, or CLI output beyond a redacted,
// length-bounded message.
export function sanitizeError(error: unknown): SanitizedError {
  const err = error instanceof Error ? error : null;
  const rawMessage = err?.message ?? (typeof error === "string" ? error : "Unknown error");
  const codeValue = (err as { code?: unknown } | null)?.code;

  return {
    name: err?.name ?? "UnknownError",
    code: typeof codeValue === "string" ? codeValue : null,
    message: sanitizeErrorMessage(rawMessage)
  };
}
