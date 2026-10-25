import { before, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { createServer } from 'node:http';
import express from 'express';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { RecallStore } from '../lib/store.js';
import { createRecallApi } from '../lib/http.js';
if (process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:18080' || process.env.FIREBASE_AUTH_EMULATOR_HOST !== '127.0.0.1:19099') throw new Error('HTTP tests require isolated Firebase emulators.');
const app = initializeApp({ projectId: 'demo-recall-backend' }, 'http-tests');
const auth = getAuth(app); const db = getFirestore(app); const store = new RecallStore(db);
const users = []; let base; let server; let providerCalls = 0;
let sequence = 0;
const requestId = () => `http-request-${++sequence}`;
const rpc = (name, params = {}, token = undefined, path = '/rpc') => fetch(`${base}${path}`, { method: 'POST', headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) }, body: JSON.stringify({ name, params }) });
async function identity(verified = true) {
  const password = randomBytes(24).toString('hex'); const email = `recall-http-${randomBytes(8).toString('hex')}@example.test`;
  const user = await auth.createUser({ email, password, emailVerified: verified }); users.push(user.uid);
  const login = await fetch(`http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo-key`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password, returnSecureToken: true }) });
  const data = await login.json(); assert.equal(login.status, 200, data.error?.message);
  return { uid: user.uid, token: data.idToken };
}
before(async () => {
  const api = express();
  api.use(express.raw({ type: () => true, limit: '22mb' }));
  const handler = createRecallApi({ store, verifyToken: token => auth.verifyIdToken(token, true), deleteUser: uid => auth.deleteUser(uid), userExists: async uid => { try { await auth.getUser(uid); return true; } catch (error) { if (error.code === 'auth/user-not-found') return false; throw error; } }, env: key => ({ APP_ORIGIN: 'https://recall.example', RECALL_AI_ENABLED: '0', RECALL_BILLING_ENABLED: '0' })[key], fetchProvider: async () => { providerCalls++; throw new Error('No provider network allowed'); } });
  api.use((req, res) => { req.rawBody = req.body; return handler(req, res); });
  server = createServer(api); await new Promise(accept => server.listen(0, '127.0.0.1', accept)); base = `http://127.0.0.1:${server.address().port}`;
});
after(async () => {
  await new Promise(accept => server.close(accept));
  for (const uid of users) { try { await store.deleteAccount(uid, () => auth.deleteUser(uid)); } catch { /* A deletion test may already have removed it. */ } }
  await db.terminate(); await deleteApp(app);
});
test('real Auth emulator ID tokens protect owner RPCs and enforce verified email', async () => {
  const unsigned = await rpc('recall_list_projects'); assert.equal(unsigned.status, 401); assert.equal((await unsigned.json()).code, '28000');
  const unverified = await identity(false); assert.equal((await rpc('recall_list_projects', {}, unverified.token)).status, 403);
  const verified = await identity(); const created = await rpc('recall_create_project', { p_title: 'HTTP project', p_client_name: 'Client', p_category: 'Creative', p_request_id: requestId() }, verified.token, '/api/rpc');
  assert.equal(created.status, 200); const data = await created.json(); assert.equal(data.data.project.title, 'HTTP project'); assert.equal(data.data.version, 1);
  const outsider = await identity(); const own = await rpc('recall_list_projects', {}, outsider.token); assert.deepEqual((await own.json()).data, []);
});
test('public reviews ignore an invalid owner Authorization header and return flat safe errors', async () => {
  const response = await rpc('recall_review_link', { p_token: 'invalid' }, 'expired-private-token');
  assert.equal(response.status, 404); const data = await response.json(); assert.equal(data.code, 'P0002'); assert.equal(Object.hasOwn(data, 'error'), false); assert.equal(Object.hasOwn(data, 'message'), true);
});
test('RPC parsing rejects duplicate keys and malformed UTF-8 without identity lookup or mutation', async () => {
  const malformed = [Buffer.from('{"name":"recall_list_projects","name":"recall_create_project","params":{}}'), Buffer.concat([Buffer.from('{"name":"'), Buffer.from([0xc3, 0x28]), Buffer.from('","params":{}}')])];
  for (const body of malformed) {
    const response = await fetch(`${base}/rpc`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body });
    assert.equal(response.status, 400); assert.equal((await response.json()).code, '22023');
  }
});
test('protected named routes are email-gated and missing providers make zero calls', async () => {
  const user = await identity(); const unverified = await identity(false);
  const body = { consent: true, source_text: 'Please change fee to EUR 850', current_items: [{ id: 'fee', label: 'Fee', value: 'EUR 600' }] };
  const headers = token => ({ Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' });
  const denied = await fetch(`${base}/analyze-source`, { method: 'POST', headers: headers(unverified.token), body: JSON.stringify(body) }); assert.equal(denied.status, 403);
  const disabled = await fetch(`${base}/api/analyze-source`, { method: 'POST', headers: headers(user.token), body: JSON.stringify(body) }); assert.equal(disabled.status, 503);
  assert.equal((await fetch(`${base}/refresh-entitlement`, { method: 'POST', headers: headers(user.token), body: '{}' })).status, 503);
  assert.equal(providerCalls, 0);
});
test('recent authenticated account deletion ignores body identity and cleans only its owner', async () => {
  const user = await identity(false); const other = await identity();
  // Unverified owners can still delete their account; no invitation/email is sent.
  const response = await fetch(`${base}/api/account-delete`, { method: 'POST', headers: { Authorization: `Bearer ${user.token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ uid: other.uid }) });
  assert.equal(response.status, 200); assert.deepEqual(await response.json(), { deleted: true });
  await assert.rejects(auth.getUser(user.uid), error => error.code === 'auth/user-not-found'); assert.equal((await auth.getUser(other.uid)).uid, other.uid);
});
test('account deletion rejects a non-recent auth_time even with otherwise valid claims', async () => {
  let deletion = false;
  const api = createRecallApi({ store, verifyToken: async () => ({ uid: 'oldAuthFirebase0000000000001', auth_time: Math.floor(Date.now() / 1000) - 600, email_verified: true }), deleteUser: async () => { deletion = true; }, userExists: async () => true, env: () => undefined });
  const result = {}; const response = { set() { return this; }, status(value) { result.status = value; return this; }, json(value) { result.data = value; return this; } };
  await api({ method: 'POST', path: '/account-delete', rawBody: Buffer.from('{}'), headers: { authorization: 'Bearer test' }, get: key => key === 'Authorization' ? 'Bearer test' : undefined }, response);
  assert.equal(result.status, 401); assert.equal(result.data.code, '28000'); assert.equal(deletion, false);
});
test('an HTTP request verified before account deletion cannot recreate data after cleanup', async () => {
  const user = await identity(); let ready; let release;
  const verified = new Promise(accept => { ready = accept; }); const gate = new Promise(accept => { release = accept; });
  const handler = createRecallApi({ store, verifyToken: async token => { const claims = await auth.verifyIdToken(token, true); ready(); await gate; return claims; }, deleteUser: uid => auth.deleteUser(uid), userExists: async () => true, env: () => undefined });
  const raw = Buffer.from(JSON.stringify({ name:'recall_create_project',params:{p_title:'Cannot resurrect',p_client_name:'Client',p_category:'Creative',p_request_id:requestId()} }));
  const result = {}; const response = { set() { return this; }, status(value) { result.status=value; return this; }, json(value) { result.data=value; return this; } };
  const pending = handler({ method:'POST',path:'/rpc',rawBody:raw,headers:{authorization:`Bearer ${user.token}`},get:key=>key==='Authorization'?`Bearer ${user.token}`:undefined,is:kind=>kind==='application/json' },response);
  await verified; await store.deleteAccount(user.uid,()=>auth.deleteUser(user.uid)); release(); await pending;
  assert.equal(result.status,403);assert.equal(result.data.code,'42501');
  assert.equal((await db.collection('recallProjects').where('ownerId','==',user.uid).get()).empty,true);
});
