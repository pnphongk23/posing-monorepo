import test from 'node:test';
import assert from 'node:assert/strict';

import {
  BASIC_AUTH_REALM,
  checkAdminBasicAuth,
  constantTimeEquals,
  parseBasicAuthorizationHeader,
  resolveAdminBasicAuthConfig,
} from './adminBasicAuth.js';

// Throwaway credentials invented for this test file - never real values.
const USER = 'qa-admin-user';
const PASSWORD = 'qa-throwaway-pass-9f3e';
const PRODUCTION_ENV = {
  NODE_ENV: 'production',
  ADMIN_UI_BASIC_USER: USER,
  ADMIN_UI_BASIC_PASSWORD: PASSWORD,
};

function basicHeader(user, password) {
  return `Basic ${Buffer.from(`${user}:${password}`, 'utf8').toString('base64')}`;
}

const VALID_HEADER = basicHeader(USER, PASSWORD);

function assertUnauthorized(denied) {
  assert.ok(denied, 'expected the gate to reject the request');
  assert.equal(denied.status, 401);
  assert.equal(denied.headers['WWW-Authenticate'], `Basic realm="${BASIC_AUTH_REALM}"`);
}

test('rejects a request with no Authorization header', () => {
  assertUnauthorized(checkAdminBasicAuth(null, PRODUCTION_ENV));
  assertUnauthorized(checkAdminBasicAuth(undefined, PRODUCTION_ENV));
  assertUnauthorized(checkAdminBasicAuth('', PRODUCTION_ENV));
});

test('accepts the correct credentials', () => {
  assert.equal(checkAdminBasicAuth(VALID_HEADER, PRODUCTION_ENV), null);
});

test('rejects a wrong password with the same 401 shape', () => {
  assertUnauthorized(checkAdminBasicAuth(basicHeader(USER, 'not-the-password'), PRODUCTION_ENV));
});

test('rejects a wrong user', () => {
  assertUnauthorized(checkAdminBasicAuth(basicHeader('someone-else', PASSWORD), PRODUCTION_ENV));
});

test('rejects malformed Authorization headers', () => {
  const malformedHeaders = [
    'Basic',
    'Basic ',
    'Basic not-base64!!!',
    'Basic ' + Buffer.from('no-colon-separator').toString('base64'),
    'Basic ' + Buffer.from(':password-only').toString('base64'),
    'Bearer ' + Buffer.from(`${USER}:${PASSWORD}`).toString('base64'),
    'Basic dXNlcjpwYXNz extra',
    `Basic ${Buffer.from(`${USER}:${PASSWORD}`).toString('base64').slice(0, 5)}`,
  ];

  for (const header of malformedHeaders) {
    assertUnauthorized(checkAdminBasicAuth(header, PRODUCTION_ENV));
  }
});

test('rejects every request in production when a credential env var is missing', () => {
  const missingUser = { ...PRODUCTION_ENV, ADMIN_UI_BASIC_USER: undefined };
  const missingPassword = { ...PRODUCTION_ENV, ADMIN_UI_BASIC_PASSWORD: undefined };

  assertUnauthorized(checkAdminBasicAuth(VALID_HEADER, missingUser));
  assertUnauthorized(checkAdminBasicAuth(VALID_HEADER, missingPassword));
  assertUnauthorized(checkAdminBasicAuth(VALID_HEADER, { NODE_ENV: 'production' }));
});

test('rejects every request in production when a credential env var is empty', () => {
  assertUnauthorized(
    checkAdminBasicAuth(VALID_HEADER, { ...PRODUCTION_ENV, ADMIN_UI_BASIC_USER: '' }),
  );
  assertUnauthorized(
    checkAdminBasicAuth(VALID_HEADER, { ...PRODUCTION_ENV, ADMIN_UI_BASIC_PASSWORD: '' }),
  );
  assertUnauthorized(
    checkAdminBasicAuth(VALID_HEADER, {
      ...PRODUCTION_ENV,
      ADMIN_UI_BASIC_USER: '',
      ADMIN_UI_BASIC_PASSWORD: '',
    }),
  );
});

test('ignores the opt-out flag in production', () => {
  const productionOptOut = { ...PRODUCTION_ENV, ADMIN_UI_BASIC_AUTH_DISABLED: '1' };
  const config = resolveAdminBasicAuthConfig(productionOptOut);

  assert.equal(config.isProduction, true);
  assert.equal(config.disabled, false);
  assertUnauthorized(checkAdminBasicAuth(null, productionOptOut));
});

test('honours the opt-out flag outside production only', () => {
  const devOptOut = { ...PRODUCTION_ENV, NODE_ENV: 'development', ADMIN_UI_BASIC_AUTH_DISABLED: '1' };
  assert.equal(checkAdminBasicAuth(null, devOptOut), null);

  const testOptOut = { ...PRODUCTION_ENV, NODE_ENV: undefined, ADMIN_UI_BASIC_AUTH_DISABLED: '1' };
  assert.equal(checkAdminBasicAuth(null, testOptOut), null);

  // Any other flag value keeps the gate on.
  const devNoOptOut = { ...PRODUCTION_ENV, NODE_ENV: 'development', ADMIN_UI_BASIC_AUTH_DISABLED: '0' };
  assertUnauthorized(checkAdminBasicAuth(null, devNoOptOut));
  assert.equal(checkAdminBasicAuth(VALID_HEADER, devNoOptOut), null);
});

test('still rejects in non-production when the credentials are not configured', () => {
  assertUnauthorized(
    checkAdminBasicAuth(VALID_HEADER, { NODE_ENV: 'development', ADMIN_UI_BASIC_USER: '', ADMIN_UI_BASIC_PASSWORD: '' }),
  );
});

test('parses Basic headers case-insensitively and keeps colons in the password', () => {
  const header = `bAsIc ${Buffer.from(`${USER}:pa:ss:word`).toString('base64')}`;
  assert.deepEqual(parseBasicAuthorizationHeader(header), { user: USER, password: 'pa:ss:word' });
  assert.equal(parseBasicAuthorizationHeader(null), null);
});

test('constant-time comparison has no early exit and handles length differences', () => {
  assert.equal(constantTimeEquals('same-value', 'same-value'), true);
  assert.equal(constantTimeEquals('same-value', 'same-valuf'), false);
  assert.equal(constantTimeEquals('same-value', 'same-valu'), false);
  assert.equal(constantTimeEquals('', ''), true);
  assert.equal(constantTimeEquals('', 'x'), false);
  assert.equal(constantTimeEquals(undefined, 'x'), false);
});
