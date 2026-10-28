/**
 * Browser-level HTTP Basic Auth gate for the admin UI.
 *
 * The admin proxy (`src/proxy.js`) calls `checkAdminBasicAuth` before any page
 * or API route runs, so tools, crawlers and unauthenticated browsers cannot
 * reach `/admin/*` or `/api/*` even though the Next server attaches the
 * upstream admin secret itself.
 *
 * Fail-closed rules:
 * - `ADMIN_UI_BASIC_USER` and `ADMIN_UI_BASIC_PASSWORD` must both be non-empty,
 *   otherwise every request is rejected.
 * - `ADMIN_UI_BASIC_AUTH_DISABLED=1` is honoured only when
 *   `NODE_ENV !== 'production'`, so local dev and tests stay usable while a
 *   production build can never opt out.
 */

export const BASIC_AUTH_REALM = 'posing admin';

const AUTH_SCHEME = 'Basic';
const DISABLED_ENV = 'ADMIN_UI_BASIC_AUTH_DISABLED';
const USER_ENV = 'ADMIN_UI_BASIC_USER';
const PASSWORD_ENV = 'ADMIN_UI_BASIC_PASSWORD';

const UNAUTHORIZED_BODY = 'Unauthorized';

function readEnvString(env, key) {
  const value = env ? env[key] : undefined;
  return typeof value === 'string' ? value : '';
}

/**
 * Resolve the gate configuration. `disabled` is only ever true outside
 * production, and only when the explicit opt-out flag is set.
 */
export function resolveAdminBasicAuthConfig(env = process.env) {
  const user = readEnvString(env, USER_ENV);
  const password = readEnvString(env, PASSWORD_ENV);
  const isProduction = readEnvString(env, 'NODE_ENV') === 'production';
  const disabledRequested = readEnvString(env, DISABLED_ENV) === '1';

  return {
    user,
    password,
    isProduction,
    configured: user.length > 0 && password.length > 0,
    disabled: disabledRequested && !isProduction,
  };
}

function toBytes(value) {
  return new TextEncoder().encode(value);
}

/**
 * Byte-wise comparison with no early return on the first mismatch:
 * the loop always runs over `max(a.length, b.length)` bytes and accumulates
 * differences with XOR. Length is folded into the accumulator instead of
 * returning early. (Length itself is still observable, as with any
 * fixed-length credential check; that is unavoidable for a 401/200 gate.)
 */
export function constantTimeEquals(expected, actual) {
  if (typeof expected !== 'string' || typeof actual !== 'string') {
    return false;
  }

  const expectedBytes = toBytes(expected);
  const actualBytes = toBytes(actual);
  const length = Math.max(expectedBytes.length, actualBytes.length, 1);

  let diff = expectedBytes.length ^ actualBytes.length;
  for (let index = 0; index < length; index += 1) {
    diff |= (expectedBytes[index] ?? 0) ^ (actualBytes[index] ?? 0);
  }

  return diff === 0;
}

/**
 * Parse `Authorization: Basic <base64 user:pass>`.
 * Returns `null` for missing, malformed or non-Basic headers.
 */
export function parseBasicAuthorizationHeader(header) {
  if (typeof header !== 'string') {
    return null;
  }

  const trimmed = header.trim();
  const prefix = `${AUTH_SCHEME} `;
  if (trimmed.length <= prefix.length) {
    return null;
  }
  if (trimmed.slice(0, prefix.length).toLowerCase() !== prefix.toLowerCase()) {
    return null;
  }

  const encoded = trimmed.slice(prefix.length).trim();
  if (encoded.length === 0 || /\s/.test(encoded)) {
    return null;
  }

  let decoded;
  try {
    decoded = atob(encoded);
  } catch {
    return null;
  }

  const separatorIndex = decoded.indexOf(':');
  if (separatorIndex <= 0) {
    return null;
  }

  return {
    user: decoded.slice(0, separatorIndex),
    password: decoded.slice(separatorIndex + 1),
  };
}

function unauthorized() {
  return {
    status: 401,
    headers: {
      'WWW-Authenticate': `Basic realm="${BASIC_AUTH_REALM}"`,
      'Cache-Control': 'no-store',
    },
    body: UNAUTHORIZED_BODY,
  };
}

/**
 * Gate decision used by the proxy. Returns `null` when the request may
 * continue, otherwise the 401 response description.
 */
export function checkAdminBasicAuth(header, env = process.env) {
  const config = resolveAdminBasicAuthConfig(env);

  if (config.disabled) {
    return null;
  }

  if (!config.configured) {
    return unauthorized();
  }

  const credentials = parseBasicAuthorizationHeader(header);
  if (!credentials) {
    return unauthorized();
  }

  const userMatches = constantTimeEquals(config.user, credentials.user);
  const passwordMatches = constantTimeEquals(config.password, credentials.password);

  if (userMatches && passwordMatches) {
    return null;
  }

  return unauthorized();
}
