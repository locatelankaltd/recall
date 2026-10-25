import type { Request, Response as ExpressResponse } from 'express';
import type { DecodedIdToken } from 'firebase-admin/auth';
import { ApiError, fail, Json, object, uidIdentifier } from './domain.js';
import { RecallStore } from './store.js';
import { createAnalysisHandler, strictJson } from './providers/analysis.js';
import { createTranscriptionHandler } from './providers/transcription.js';
import { createBillingHandlers } from './providers/billing.js';
export interface HttpDependencies {
  store: RecallStore;
  verifyToken: (token: string) => Promise<DecodedIdToken>;
  deleteUser: (uid: string) => Promise<void>;
  userExists: (uid: string) => Promise<boolean>;
  env: (name: string) => string | undefined;
  fetchProvider?: typeof fetch;
  clock?: () => number;
}
const publicRpc = new Set(['recall_review_link', 'recall_respond_review']);
function tokenFrom(request: Request): string {
  const header = request.get('Authorization') ?? '';
  if (!header.startsWith('Bearer ') || header.length > 16384) return fail('28000', 'Sign in to continue.', 401);
  return header.slice(7);
}
export function createRecallApi(deps: HttpDependencies) {
  return async (request: Request, response: ExpressResponse): Promise<void> => {
    const origin = deps.env('APP_ORIGIN');
    response.set({ 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer', 'Vary': 'Origin', 'Access-Control-Allow-Origin': origin ?? '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' });
    const sendError = (error: unknown): void => {
      if (error instanceof ApiError) response.status(error.status).json({ message: error.message, code: error.code });
      else response.status(503).json({ message: 'The service could not complete this request. Please retry.', code: 'UNAVAILABLE' });
    };
    try {
      if (origin && request.get('Origin') && request.get('Origin') !== origin) return void response.status(403).json({ message: 'Origin unavailable.', code: '42501' });
      if (request.method === 'OPTIONS') return void response.status(204).end();
      if (request.method !== 'POST') return void response.status(405).json({ message: 'Use POST.', code: '22023' });
      let path = request.path.replace(/^\/api(?=\/|$)/, '').replace(/^\/recallApi(?=\/|$)/, '');
      if (path.endsWith('/') && path.length > 1) path = path.slice(0, -1);
      const raw = (request as Request & { rawBody?: Buffer }).rawBody ?? Buffer.from(typeof request.body === 'string' ? request.body : JSON.stringify(request.body ?? {}));
      const json = (): Json => {
        if (!request.is('application/json')) return fail('22023', 'Use application/json.', 415);
        if (raw.length > 1000000) return fail('54000', 'The request exceeds its size limit.', 413);
        let body;
        try { body = strictJson(new TextDecoder('utf-8', { fatal: true }).decode(raw)); } catch { return fail('22023', 'Invalid JSON request.'); }
        if (!object(body)) return fail('22023', 'Invalid JSON request.');
        return body;
      };
      const identity = async (allowUnverified = false): Promise<DecodedIdToken> => {
        let user;
        try { user = await deps.verifyToken(tokenFrom(request)); } catch (error) { if (error instanceof ApiError) throw error; return fail('28000', 'Sign in again to continue.', 401); }
        if (!uidIdentifier(user.uid)) return fail('28000', 'Sign in again to continue.', 401);
        if (!allowUnverified && user.email_verified !== true) return fail('42501', 'Verify your email before opening your account workspace.', 403);
        return user;
      };
      if (path === '/rpc') {
        const body = json();
        if (typeof body.name !== 'string' || !object(body.params) || Object.keys(body).some(k => !['name', 'params'].includes(k))) return fail('22023', 'Provide an RPC name and parameters.');
        // Public link capabilities never inherit or validate an owner session.
        const owner = publicRpc.has(body.name) ? null : await identity();
        const result = await deps.store.rpc(body.name, body.params, owner?.uid ?? null);
        return void response.status(200).json({ data: result });
      }
      if (path === '/account-delete') {
        const owner = await identity(true);
        const now = (deps.clock ?? Date.now)() / 1000;
        if (!Number.isFinite(owner.auth_time) || owner.auth_time > now + 60 || now - owner.auth_time > 300) return fail('28000', 'Sign in again before deleting your account.', 401);
        await deps.store.deleteAccount(owner.uid, () => deps.deleteUser(owner.uid));
        return void response.status(200).json({ deleted: true });
      }
      if (!['/analyze-source', '/transcribe-recording', '/refresh-entitlement', '/billing-webhook'].includes(path)) return fail('P0002', 'Route not found.', 404);
      const owner = path === '/billing-webhook' ? null : await identity();
      const env = deps.env;
      const verifyUser = async (token: string): Promise<Json | null> => owner && token === tokenFrom(request) ? { id: owner.uid } : null;
      const reserveAnalysis = async (uid: string, limit: number): Promise<boolean> => {
        if (!owner || uid !== owner.uid) return fail('42501', 'Invalid analysis identity.', 403);
        return deps.store.reserveAnalysis(uid, limit);
      };
      const webHeaders = new Headers();
      for (const [key, value] of Object.entries(request.headers)) if (typeof value === 'string') webHeaders.set(key, value);
      const webRequest = new globalThis.Request(`https://recall.invalid${path}`, { method: 'POST', headers: webHeaders, body: new Uint8Array(raw) });
      let result: globalThis.Response;
      if (path === '/analyze-source') result = await createAnalysisHandler({ env, verifyUser, reserveAnalysis, fetchProvider: deps.fetchProvider })(webRequest);
      else if (path === '/transcribe-recording') result = await createTranscriptionHandler({ env, verifyUser, reserveAnalysis, fetchProvider: deps.fetchProvider })(webRequest);
      else {
        const billing = createBillingHandlers({ env, verifyUser, fetchProvider: deps.fetchProvider, now: deps.clock ?? Date.now, eventSeen: (id: string) => deps.store.eventSeen(id), applyState: async (updates: Json[], eventId: string | null) => {
          const existing = [];
          for (const update of updates) if (await deps.userExists(update.ownerId)) existing.push(update);
          return existing.length ? deps.store.applyBilling(existing, eventId) : { applied: 0 };
        }, readEntitlement: async () => {
          if (!owner) return fail('28000', 'Sign in to continue.', 401);
          return deps.store.entitlement(owner.uid);
        } });
        result = path === '/billing-webhook' ? await billing.webhook(webRequest) : await billing.refresh(webRequest);
      }
      const payload = await result.json();
      if (!result.ok) {
        const code = result.status === 401 ? '28000' : result.status === 403 ? '42501' : result.status === 429 ? '54000' : result.status === 400 || result.status === 413 || result.status === 415 ? '22023' : result.status === 504 ? 'TIMEOUT' : 'UNAVAILABLE';
        return void response.status(result.status).json({ message: payload.error ?? 'The request could not complete.', code });
      }
      response.status(result.status).json(payload);
    } catch (error) { sendError(error); }
  };
}
