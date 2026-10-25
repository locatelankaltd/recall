// @ts-nocheck
// RevenueCat payloads select existing Firebase Auth UIDs to reconcile, never paid status.
import { strictJson } from './analysis.js';
const uidPattern = /^[A-Za-z0-9:_-]{1,128}$/;
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
export class BillingProblem extends Error { constructor(status, message) { super(message); this.status = status; } }
export const isUserId = value => typeof value === 'string' && uidPattern.test(value);
const validKey = key => typeof key === 'string' && key.length >= 16 && key.length <= 4096 && !/[\s\u0000-\u001f]/.test(key);
function parseDate(value) {
  if (value === null || value === undefined) return null;
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$/.test(value) || !Number.isFinite(Date.parse(value))) throw new BillingProblem(502, 'Billing returned an invalid expiry.');
  return Date.parse(value);
}
export function deriveEntitlement(envelope, { now = Date.now(), allowSandbox = false } = {}) {
  if (!object(envelope) || !object(envelope.subscriber) || !object(envelope.subscriber.entitlements) || !Number.isSafeInteger(envelope.request_date_ms) || Math.abs(envelope.request_date_ms - now) > 300000) throw new BillingProblem(502, 'Fresh verified billing state was unavailable.');
  const observedAt = new Date(envelope.request_date_ms).toISOString();
  const entitlement = envelope.subscriber.entitlements.pro;
  if (entitlement === undefined) return { active: false, expiresAt: null, environment: 'unknown', observedAt };
  if (!object(entitlement) || typeof entitlement.product_identifier !== 'string' || !Object.hasOwn(entitlement, 'expires_date')) throw new BillingProblem(502, 'Billing entitlement data was unavailable.');
  const product = entitlement.product_identifier;
  let purchase = envelope.subscriber.subscriptions?.[product];
  if (!object(purchase)) {
    const purchases = envelope.subscriber.non_subscriptions?.[product];
    if (Array.isArray(purchases)) {
      const matches = purchases.filter(row => object(row) && row.purchase_date === entitlement.purchase_date);
      purchase = matches.length === 1 ? matches[0] : (purchases.length === 1 ? purchases[0] : undefined);
    }
  }
  const sandbox = purchase?.is_sandbox;
  const environment = sandbox === true ? 'sandbox' : sandbox === false ? 'production' : 'unknown';
  const expiry = parseDate(entitlement.expires_date);
  const grace = parseDate(entitlement.grace_period_expires_date);
  const effectiveExpiry = expiry === null ? null : Math.max(expiry, grace ?? expiry);
  const active = environment !== 'unknown' && (environment === 'production' || allowSandbox) && !purchase?.refunded_at && (effectiveExpiry === null || effectiveExpiry > now);
  return { active, expiresAt: effectiveExpiry === null ? null : new Date(effectiveExpiry).toISOString(), environment, observedAt };
}
async function readText(response, limit = 262144) {
  const reader = response.body?.getReader();
  if (!reader) throw new BillingProblem(502, 'Billing response unavailable.');
  const chunks = []; let size = 0;
  try {
    for (;;) {
      const { value, done } = await reader.read(); if (done) break;
      size += value.byteLength;
      if (size > limit) { await reader.cancel(); throw new BillingProblem(413, 'Billing request or response exceeded its size limit.'); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
}
export function createBillingHandlers({ env, verifyUser, eventSeen, applyState, readEntitlement, fetchProvider = fetch, now = Date.now }) {
  const response = (status, data, headers = {}) => new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', ...headers } });
  const reconcile = async ids => {
    const key = env('REVENUECAT_SECRET_API_KEY');
    if (!validKey(key)) throw new BillingProblem(503, 'Billing verification is not configured.');
    const updates = [];
    for (const ownerId of ids) {
      let result;
      try {
        const fetched = await fetchProvider(`https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(ownerId)}`, { method: 'GET', redirect: 'error', signal: AbortSignal.timeout(10000), headers: { 'Authorization': `Bearer ${key}`, 'Accept': 'application/json' } });
        if (!fetched.ok) { await fetched.body?.cancel(); throw new BillingProblem(503, 'The billing provider is temporarily unavailable.'); }
        result = strictJson(await readText(fetched));
      } catch (error) {
        if (error instanceof BillingProblem) throw error;
        throw new BillingProblem(503, 'Billing verification could not complete.');
      }
      updates.push({ ownerId, ...deriveEntitlement(result, { now: now(), allowSandbox: env('RECALL_ALLOW_SANDBOX_BILLING') === '1' }) });
    }
    return updates;
  };
  const webhook = async request => {
    if (request.method !== 'POST') return response(405, { error: 'Use POST.' });
    const secret = env('REVENUECAT_WEBHOOK_AUTH');
    // Dashboard Authorization must match this full long random value exactly.
    if (typeof secret !== 'string' || secret.length < 32 || secret.length > 4096) return response(503, { error: 'Billing webhook is not configured.' });
    const supplied = request.headers.get('Authorization') ?? '';
    const expectedHash = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(secret)));
    const suppliedHash = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(supplied)));
    let difference = expectedHash.length ^ suppliedHash.length;
    for (let i = 0; i < expectedHash.length; i++) difference |= expectedHash[i] ^ suppliedHash[i];
    if (difference !== 0) return response(401, { error: 'Webhook authentication required.' });
    try {
      if (request.headers.get('Content-Type')?.split(';')[0] !== 'application/json') throw new BillingProblem(415, 'Use application/json.');
      let body;
      try { body = strictJson(await readText(request, 65536)); } catch (error) { if (error instanceof BillingProblem) throw error; throw new BillingProblem(400, 'Invalid webhook JSON.'); }
      const event = body?.event;
      if (!object(event) || typeof event.id !== 'string' || event.id.length < 1 || event.id.length > 200 || typeof event.type !== 'string') throw new BillingProblem(400, 'Invalid billing event.');
      if (event.type === 'TEST') return response(200, { received: true, ignored: true });
      let candidates;
      if (event.type === 'TRANSFER') {
        if (!Array.isArray(event.transferred_from) || !Array.isArray(event.transferred_to)) throw new BillingProblem(400, 'Invalid transfer identities.');
        candidates = [...event.transferred_from, ...event.transferred_to];
      } else candidates = [event.app_user_id, event.original_app_user_id, ...(Array.isArray(event.aliases) ? event.aliases : [])];
      if (candidates.length > 100) throw new BillingProblem(400, 'Too many billing identities.');
      const ids = [...new Set(candidates.filter(isUserId))].sort();
      if (ids.length > 20) throw new BillingProblem(400, 'Too many billing identities.');
      if (ids.length === 0) return response(200, { received: true, ignored: true });
      if (await eventSeen(event.id)) return response(200, { received: true, duplicate: true });
      const updates = await reconcile(ids);
      await applyState(updates, event.id);
      return response(200, { received: true });
    } catch (error) {
      return response(error instanceof BillingProblem ? error.status : 503, { error: error instanceof BillingProblem ? error.message : 'Billing reconciliation could not complete.' });
    }
  };
  const refresh = async request => {
    const origin = env('APP_ORIGIN');
    const headers = { 'Access-Control-Allow-Origin': origin ?? '*', 'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Vary': 'Origin' };
    if (origin && request.headers.get('Origin') && request.headers.get('Origin') !== origin) return response(403, { error: 'Origin unavailable.' }, headers);
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers });
    if (request.method !== 'POST') return response(405, { error: 'Use POST.' }, headers);
    const authorization = request.headers.get('Authorization') ?? '';
    if (!authorization.startsWith('Bearer ')) return response(401, { error: 'Sign in before verifying a subscription.' }, headers);
    try {
      const user = await verifyUser(authorization.slice(7));
      if (!user || !isUserId(user.id)) return response(401, { error: 'Sign in before verifying a subscription.' }, headers);
      const updates = await reconcile([user.id]);
      await applyState(updates, null);
      return response(200, await readEntitlement(authorization.slice(7)), headers);
    } catch (error) {
      return response(error instanceof BillingProblem ? error.status : 503, { error: error instanceof BillingProblem ? error.message : 'Billing verification could not complete.' }, headers);
    }
  };
  return { webhook, refresh };
}
