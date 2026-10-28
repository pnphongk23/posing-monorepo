import test from 'node:test';
import assert from 'node:assert/strict';
import { NextRequest } from 'next/server';

import { config, proxy } from './proxy.js';

// Throwaway credentials invented for this test file - never real values.
const USER = 'qa-proxy-user';
const PASSWORD = 'qa-proxy-throwaway-pass-4c1d';
const AUTHORIZATION = `Basic ${Buffer.from(`${USER}:${PASSWORD}`, 'utf8').toString('base64')}`;

function withEnv(overrides) {
  const previous = new Map();
  for (const [key, value] of Object.entries(overrides)) {
    previous.set(key, process.env[key]);
    if (value === undefined) {
      delete process.env[key];
    } else {
      process.env[key] = value;
    }
  }

  return () => {
    for (const [key, value] of previous.entries()) {
      if (value === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = value;
      }
    }
  };
}

function buildRequest(pathname, { method = 'GET', authorization } = {}) {
  const headers = new Headers();
  if (authorization !== undefined) {
    headers.set('authorization', authorization);
  }
  return new NextRequest(`http://localhost:3000${pathname}`, { method, headers });
}

function productionEnv(t, overrides = {}) {
  t.after(
    withEnv({
      NODE_ENV: 'production',
      ADMIN_UI_BASIC_USER: USER,
      ADMIN_UI_BASIC_PASSWORD: PASSWORD,
      ...overrides,
    }),
  );
}

test('proxy is exported from the Next 16 `proxy` convention file', () => {
  assert.equal(typeof proxy, 'function');
  assert.ok(Array.isArray(config.matcher));
});

test('proxy returns 401 with a Basic challenge when no header is sent', (t) => {
  productionEnv(t);

  const response = proxy(buildRequest('/admin'));

  assert.equal(response.status, 401);
  assert.equal(response.headers.get('WWW-Authenticate'), 'Basic realm="posing admin"');
});

test('proxy returns 401 for a wrong password and a malformed header', (t) => {
  productionEnv(t);

  for (const authorization of [
    `Basic ${Buffer.from(`${USER}:wrong`).toString('base64')}`,
    'Basic',
    'Basic not-base64!!!',
    'Bearer token',
  ]) {
    const response = proxy(buildRequest('/admin', { authorization }));
    assert.equal(response.status, 401, `expected 401 for ${authorization}`);
    assert.equal(response.headers.get('WWW-Authenticate'), 'Basic realm="posing admin"');
  }
});

test('proxy lets a correctly authenticated request through', (t) => {
  productionEnv(t);

  const response = proxy(buildRequest('/admin', { authorization: AUTHORIZATION }));

  assert.notEqual(response.status, 401);
  assert.equal(response.headers.get('x-middleware-next'), '1');
});

test('proxy gates API routes for every method, including server actions', (t) => {
  productionEnv(t);

  const gatedRequests = [
    buildRequest('/api/admin/keys'),
    buildRequest('/api/admin/keys', { method: 'POST' }),
    buildRequest('/api/admin/keys/reset', { method: 'POST' }),
    buildRequest('/api/admin/extract-pose', { method: 'POST' }),
    buildRequest('/api/extract', { method: 'POST' }),
    buildRequest('/admin/keys', { method: 'POST' }), // server action POST target
    buildRequest('/api/admin/keys', { method: 'OPTIONS' }),
  ];

  for (const request of gatedRequests) {
    assert.equal(proxy(request).status, 401, `expected 401 for ${request.method} ${request.nextUrl.pathname}`);
  }

  for (const request of gatedRequests) {
    const headers = new Headers(request.headers);
    headers.set('authorization', AUTHORIZATION);
    const authorized = new NextRequest(request.url, { method: request.method, headers });
    assert.notEqual(proxy(authorized).status, 401, `expected pass-through for ${request.method} ${request.nextUrl.pathname}`);
  }
});

test('proxy fails closed in production when env credentials are missing or empty', (t) => {
  productionEnv(t, { ADMIN_UI_BASIC_USER: undefined, ADMIN_UI_BASIC_PASSWORD: undefined });
  assert.equal(proxy(buildRequest('/admin', { authorization: AUTHORIZATION })).status, 401);

  t.after(withEnv({ ADMIN_UI_BASIC_USER: '', ADMIN_UI_BASIC_PASSWORD: '' }));
  assert.equal(proxy(buildRequest('/admin', { authorization: AUTHORIZATION })).status, 401);
});

test('proxy ignores the opt-out flag in production', (t) => {
  productionEnv(t, { ADMIN_UI_BASIC_AUTH_DISABLED: '1' });

  assert.equal(proxy(buildRequest('/admin')).status, 401);
});

test('proxy allows the dev opt-out outside production', (t) => {
  t.after(
    withEnv({
      NODE_ENV: 'development',
      ADMIN_UI_BASIC_USER: undefined,
      ADMIN_UI_BASIC_PASSWORD: undefined,
      ADMIN_UI_BASIC_AUTH_DISABLED: '1',
    }),
  );

  assert.notEqual(proxy(buildRequest('/admin')).status, 401);
});

test('matcher gates app routes and skips Next build output only', () => {
  const [matcherSource] = config.matcher;
  const matcher = new RegExp(`^${matcherSource}$`);

  for (const gatedPath of ['/', '/admin', '/admin/keys', '/api/admin/keys', '/api/extract', '/manifest.json']) {
    assert.equal(matcher.test(gatedPath), true, `expected ${gatedPath} to be gated`);
  }

  for (const skippedPath of [
    '/_next/static/chunks/main.js',
    '/_next/static/css/app.css',
    '/_next/image',
    '/favicon.ico',
  ]) {
    assert.equal(matcher.test(skippedPath), false, `expected ${skippedPath} to skip the proxy`);
  }
});
