import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createBillingHandlers, deriveEntitlement } from '../functions/_shared/billing.ts';
const owner = '11111111-1111-1111-1111-111111111111';
const other = '22222222-2222-2222-2222-222222222222';
const clock = Date.parse('2026-10-24T12:00:00Z');
const secret = 'Bearer long-random-webhook-test-secret-never-live';
function subscriber({ sandbox = false, expires = '2026-11-24T12:00:00Z', grace = null, refunded = null, entitled = true, observed = clock, product = 'monthly', purchase = true } = {}) {
  return { request_date_ms: observed, subscriber: { entitlements: entitled ? { pro: { product_identifier: product, expires_date: expires, grace_period_expires_date: grace, purchase_date: '2026-10-24T11:00:00Z' } } : {}, subscriptions: purchase ? { [product]: { is_sandbox: sandbox, refunded_at: refunded } } : {}, non_subscriptions: {} } };
}
function harness({ environment = {}, response = () => new Response(JSON.stringify(subscriber())), user = { id: owner }, duplicate = false } = {}) {
  const calls = { auth: [], fetch: [], seen: [], updates: [], reads: [] };
  const settings = { REVENUECAT_WEBHOOK_AUTH: secret, REVENUECAT_SECRET_API_KEY: 'fake-revenuecat-server-key-no-network', ...environment };
  const handlers = createBillingHandlers({ env: key => settings[key], now: () => clock, verifyUser: async token => { calls.auth.push(token); return user; }, eventSeen: async id => { calls.seen.push(id); return duplicate; }, applyState: async (...args) => { calls.updates.push(args); }, readEntitlement: async token => { calls.reads.push(token); return { active: true, entitlement: 'pro', status: 'active' }; }, fetchProvider: async (...args) => { calls.fetch.push(args); return response(...args); } });
  return { ...handlers, calls };
}
const webhookRequest = (event = {}, changes = {}) => new Request('https://edge.invalid/billing-webhook', { method: 'POST', headers: { Authorization: secret, 'Content-Type': 'application/json' }, body: JSON.stringify({ event: { id: 'event-0001', type: 'INITIAL_PURCHASE', app_user_id: owner, ...event } }), ...changes });
const refreshRequest = (changes = {}) => new Request('https://edge.invalid/refresh-entitlement', { method: 'POST', headers: { Authorization: 'Bearer verified-token' }, body: JSON.stringify({ user_id: other, active: true }), ...changes });

test('billing derives active/expired/no-entitlement state from provider, not event', () => {
  assert.equal(deriveEntitlement(subscriber(), { now: clock }).active, true);
  assert.equal(deriveEntitlement(subscriber({ expires: '2026-10-23T12:00:00Z' }), { now: clock }).active, false);
  assert.equal(deriveEntitlement(subscriber({ entitled: false }), { now: clock }).active, false);
  assert.equal(deriveEntitlement(subscriber({ refunded: '2026-10-24T11:30:00Z' }), { now: clock }).active, false);
});
test('billing sandbox cannot unlock production without explicit server switch', () => {
  const state = subscriber({ sandbox: true });
  assert.equal(deriveEntitlement(state, { now: clock }).active, false);
  assert.equal(deriveEntitlement(state, { now: clock }).environment, 'sandbox');
  assert.equal(deriveEntitlement(state, { now: clock, allowSandbox: true }).active, true);
  assert.equal(deriveEntitlement(subscriber({ purchase: false }), { now: clock }).active, false);
});
test('billing includes verified grace period and recognizes production lifetime purchases', () => {
  assert.equal(deriveEntitlement(subscriber({ expires: '2026-10-23T12:00:00Z', grace: '2026-10-25T12:00:00Z' }), { now: clock }).active, true);
  const lifetime = subscriber({ expires: null, purchase: false, product: 'lifetime' });
  lifetime.subscriber.non_subscriptions.lifetime = [{ is_sandbox: false, purchase_date: '2026-10-24T11:00:00Z' }];
  assert.equal(deriveEntitlement(lifetime, { now: clock }).active, true);
});
test('billing rejects stale or malformed provider state and dates', () => {
  for (const value of [subscriber({ observed: clock - 600000 }), subscriber({ expires: 'invalid-date' }), { subscriber: {} }]) assert.throws(() => deriveEntitlement(value, { now: clock }));
});
test('webhook requires a configured long exact Authorization secret before any IO', async () => {
  for (const options of [{ environment: { REVENUECAT_WEBHOOK_AUTH: '' } }, { environment: { REVENUECAT_WEBHOOK_AUTH: 'too-short' } }, {}]) {
    const { webhook, calls } = harness(options);
    const response = await webhook(webhookRequest({}, { headers: { Authorization: 'forged', 'Content-Type': 'application/json' } }));
    assert.ok([401, 503].includes(response.status));
    assert.deepEqual(calls, { auth: [], fetch: [], seen: [], updates: [], reads: [] });
  }
});
test('webhook paid payload is ignored; fresh REST state alone controls status', async () => {
  const { webhook, calls } = harness({ response: () => new Response(JSON.stringify(subscriber({ entitled: false }))) });
  assert.equal((await webhook(webhookRequest({ active: true, entitlement_ids: ['pro'], expiration_at_ms: clock + 999999999, environment: 'PRODUCTION' }))).status, 200);
  assert.equal(calls.updates[0][0][0].active, false);
  const [url, config] = calls.fetch[0];
  assert.equal(url, `https://api.revenuecat.com/v1/subscribers/${owner}`);
  assert.equal(config.method, 'GET');
  assert.equal(config.redirect, 'error');
  assert.equal(config.headers.Authorization, 'Bearer fake-revenuecat-server-key-no-network');
  assert.equal(Object.hasOwn(config.headers, 'X-Platform'), false);
});
test('out-of-order webhook event dates never replace fresh provider observation', async () => {
  const { webhook, calls } = harness();
  assert.equal((await webhook(webhookRequest({ event_timestamp_ms: 1, type: 'EXPIRATION' }))).status, 200);
  assert.equal(calls.updates[0][0][0].active, true);
  assert.equal(calls.updates[0][0][0].observedAt, new Date(clock).toISOString());
});
test('webhook deduplicates event IDs before provider calls', async () => {
  const { webhook, calls } = harness({ duplicate: true });
  const response = await webhook(webhookRequest());
  assert.equal(response.status, 200);
  assert.equal((await response.json()).duplicate, true);
  assert.equal(calls.fetch.length, 0);
  assert.equal(calls.updates.length, 0);
});
test('TRANSFER reconciles source and destination UUID users and ignores anonymous aliases', async () => {
  const { webhook, calls } = harness();
  const response = await webhook(webhookRequest({ type: 'TRANSFER', app_user_id: undefined, transferred_from: [owner, '$RCAnonymousID:abc'], transferred_to: [other, owner] }));
  assert.equal(response.status, 200);
  assert.equal(calls.fetch.length, 2);
  assert.deepEqual(calls.updates[0][0].map(row => row.ownerId), [owner, other]);
});
test('webhook never fetches emails, anonymous IDs or arbitrary URLs as user identities', async () => {
  const { webhook, calls } = harness();
  assert.equal((await webhook(webhookRequest({ app_user_id: 'person@example.com', aliases: ['$RCAnonymousID:abc', 'https://evil.invalid'] }))).status, 200);
  assert.equal(calls.fetch.length, 0);
  assert.equal(calls.updates.length, 0);
});
test('sandbox REST state remains inactive even for production event claims', async () => {
  const { webhook, calls } = harness({ response: () => new Response(JSON.stringify(subscriber({ sandbox: true }))) });
  assert.equal((await webhook(webhookRequest({ environment: 'PRODUCTION' }))).status, 200);
  assert.equal(calls.updates[0][0][0].active, false);
});
test('missing server billing key and provider failures do not apply claimed entitlements', async () => {
  for (const options of [{ environment: { REVENUECAT_SECRET_API_KEY: '' } }, { response: () => new Response('private failure', { status: 401 }) }, { response: () => { throw new Error('private transport error'); } }]) {
    const { webhook, calls } = harness(options);
    const result = await webhook(webhookRequest());
    assert.equal(result.status, 503);
    assert.equal((await result.text()).includes('private'), false);
    assert.equal(calls.updates.length, 0);
    assert.ok(calls.fetch.length <= 1);
  }
});
test('refresh reconciles only Auth identity regardless of request-body user or paid claims', async () => {
  const { refresh, calls } = harness();
  const result = await refresh(refreshRequest());
  assert.equal(result.status, 200);
  assert.deepEqual(calls.auth, ['verified-token']);
  assert.equal(calls.fetch.length, 1);
  assert.ok(calls.fetch[0][0].endsWith(owner));
  assert.equal(calls.updates[0][0][0].ownerId, owner);
  assert.equal(calls.updates[0][1], null);
  assert.deepEqual(calls.reads, ['verified-token']);
});
test('refresh rejects unauthenticated and cross-origin requests without provider calls', async () => {
  const { refresh, calls } = harness({ user: null, environment: { APP_ORIGIN: 'https://recall.invalid' } });
  assert.equal((await refresh(refreshRequest())).status, 401);
  assert.equal((await refresh(refreshRequest({ headers: { Authorization: 'Bearer token', Origin: 'https://evil.invalid' } }))).status, 403);
  assert.equal(calls.fetch.length, 0);
});
