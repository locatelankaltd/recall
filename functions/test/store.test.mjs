import { before, after, test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { initializeTestEnvironment, assertFails } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, collection, getDocs } from 'firebase/firestore';
import { RecallStore, WORKSPACE_MAX } from '../lib/store.js';
import { revisionHash, digest } from '../lib/domain.js';
if (process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:18080') throw new Error('Tests require the isolated Firestore emulator; refusing cloud access.');
const projectId = 'demo-recall-backend';
const app = initializeApp({ projectId }, 'store-tests');
const db = getFirestore(app);
let now = Date.now();
const store = new RecallStore(db, () => now);
let sequence = 0;
const req = () => `test-request-${++sequence}`;
const create = (uid, title = 'Project') => store.create(uid, { p_title: title, p_client_name: 'Client', p_category: 'Creative', p_request_id: req() });
const change = (uid, envelope, action, payload = {}, request = req()) => store.mutate(uid, { p_project_id: envelope.project.id, p_expected_version: envelope.version, p_action: action, p_payload: payload, p_request_id: request });
const item = (id, title = id) => ({ id, title, details: '', ownerId: 'you', dueDate: null, amountMinor: null, currency: 'USD' });
const evidence = [{ id: 'source', text: 'Please change the tasks. தமிழ்', language: 'ta', kind: 'originalText' }];
const propose = (uid, env, items) => change(uid, env, 'propose_change', { items, evidence });
async function link(uid, env, index = -1, ids = undefined) {
  const revision = env.project.proposals.at(index);
  return store.createLink(uid, { p_project_id: env.project.id, p_revision_id: revision.id, p_participant_id: 'client', ...(ids ? { p_item_ids: ids } : {}) });
}
let rules;
before(async () => {
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${projectId}/databases/(default)/documents`, { method: 'DELETE' });
  rules = await initializeTestEnvironment({ projectId, firestore: { host: '127.0.0.1', port: 18080, rules: await fs.readFile(new URL('../../firestore.rules', import.meta.url), 'utf8') } });
});
after(async () => { await rules.cleanup(); await db.terminate(); await deleteApp(app); });

test('client rules deny anonymous and owner reads/writes to all private data', async () => {
  const uid = 'ownerRulesFirebaseUid000000001'; const env = await create(uid);
  for (const context of [rules.unauthenticatedContext(), rules.authenticatedContext(uid, { email_verified: true })]) {
    const client = context.firestore();
    await assertFails(getDoc(doc(client, `recallProjects/${env.project.id}`)));
    await assertFails(setDoc(doc(client, `recallProjects/${env.project.id}`), { ownerId: uid, version: 999 }));
    await assertFails(getDocs(collection(client, 'recallReviewLinks')));
    await assertFails(setDoc(doc(client, `recallOwners/${uid}/entitlements/pro`), { active: true }));
  }
});
test('owner isolation and forbidden client response are enforced by the server', async () => {
  const uid = 'ownerIsolationFirebase000001'; let env = await create(uid);
  env = await change(uid, env, 'add_item', { item: item('a') });
  await assert.rejects(change('outsiderFirebase000000000001', env, 'delete'), error => error.code === 'P0002');
  assert.deepEqual(await store.listProjects('outsiderFirebase000000000001'), []);
  env = await propose(uid, env, [item('a', 'Changed')]);
  await assert.rejects(change(uid, env, 'confirm', { revisionId: env.project.proposals[0].id, actorId: 'client' }), error => error.code === '42501');
  await assert.rejects(store.rpc('recall_apply_billing_state', { active: true }, uid), error => error.code === '42501');
});
test('project creation is idempotent and concurrent Free cap cannot exceed three', async () => {
  const uid = 'ownerProjectCapFirebase000001'; const params = { p_title: 'One', p_client_name: 'Client', p_category: 'Creative', p_request_id: req() };
  const first = await store.create(uid, params); assert.deepEqual(await store.create(uid, params), first);
  await assert.rejects(store.create(uid, { ...params, p_title: 'Different' }), error => error.code === '22023');
  await create(uid, 'Two');
  const results = await Promise.allSettled([create(uid, 'Three'), create(uid, 'Four')]);
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
  assert.equal(results.find(r => r.status === 'rejected').reason.code, '54000');
  assert.equal((await store.listProjects(uid)).length, 3);
  assert.deepEqual(await store.create(uid, params), first);
});
test('competing CAS writes commit exactly one version and exact retry is not replayed', async () => {
  const uid = 'ownerCasFirebase000000000001'; let env = await create(uid); env = await change(uid, env, 'add_item', { item: item('a') });
  const params = { p_project_id: env.project.id, p_expected_version: env.version, p_action: 'set_status', p_payload: { itemId: 'a', status: 'delivered' }, p_request_id: req() };
  const results = await Promise.allSettled([store.mutate(uid, params), change(uid, env, 'set_status', { itemId: 'a', status: 'inProgress' })]);
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
  assert.equal(results.find(r => r.status === 'rejected').reason.code, '40001');
  const winner = results.find(r => r.status === 'fulfilled').value;
  if (results[0].status === 'fulfilled') assert.deepEqual(await store.mutate(uid, params), winner);
  assert.equal((await store.listProjects(uid))[0].version, env.version + 1);
});
test('scoped hashed links expose selected items only and all actors/items must accept', async () => {
  const uid = 'ownerScopeFirebase00000000001'; let env = await create(uid);
  env = await change(uid, env, 'add_item', { item: item('a') }); env = await change(uid, env, 'add_item', { item: item('b') });
  env = await change(uid, env, 'set_status', { itemId: 'a', status: 'delivered' });
  const baseline = env.project.currentRevision.id;
  env = await propose(uid, env, [item('a', 'Changed A'), item('b', 'Changed B')]);
  const a = await link(uid, env, -1, ['a']); const b = await link(uid, env, -1, ['b']);
  const stored = (await db.doc(`recallReviewLinks/${digest(a.token)}`).get()).data();
  assert.equal(Object.hasOwn(stored, 'token'), false);
  const view = await store.review(a.token); assert.equal(view.changes.length, 1); assert.equal(view.changes[0].itemId, 'a'); assert.deepEqual(view.evidence, []); assert.equal(view.evidenceOmitted, true);
  assert.equal(Object.hasOwn(view, 'ownerId'), false); assert.equal(Object.hasOwn(view, 'history'), false);
  const responseA = { p_token: a.token, p_action: 'confirm', p_note: '', p_request_id: req() };
  const receipt = await store.respond(responseA); assert.equal(receipt.status, 'proposed'); assert.deepEqual(await store.respond(responseA), receipt);
  assert.equal((await store.listProjects(uid))[0].project.currentRevision.id, baseline);
  await store.respond({ p_token: b.token, p_action: 'confirm', p_note: '', p_request_id: req() });
  const final = (await store.listProjects(uid))[0].project;
  assert.equal(final.currentRevision.id, env.project.proposals[0].id); assert.deepEqual(final.currentRevision.acceptedBy, ['you', 'client']); assert.deepEqual(final.itemStatuses, {});
});
test('simultaneous competing publication makes the loser stale', async () => {
  const uid = 'ownerPublicationFirebase00001'; let env = await create(uid); env = await change(uid, env, 'add_item', { item: item('a') });
  env = await propose(uid, env, [item('a', 'A')]); const a = await link(uid, env);
  env = await propose(uid, env, [item('a', 'B')]); const b = await link(uid, env);
  const results = await Promise.allSettled([a, b].map(l => store.respond({ p_token: l.token, p_action: 'confirm', p_note: '', p_request_id: req() })));
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1); assert.equal(results.find(r => r.status === 'rejected').reason.code, '40001');
  const losingLink = results[0].status === 'rejected' ? a : b; assert.equal((await store.review(losingLink.token)).status, 'stale');
});
test('correction clears acceptance and requires a new immutable proposal', async () => {
  const uid = 'ownerCorrectionFirebase00001'; let env = await create(uid); env = await change(uid, env, 'add_item', { item: item('a') }); env = await propose(uid, env, [item('a', 'Changed')]);
  const l = await link(uid, env); const original = env.project.proposals[0];
  await store.respond({ p_token: l.token, p_action: 'correction', p_note: 'Fix scope', p_request_id: req() });
  const project = (await store.listProjects(uid))[0].project; assert.deepEqual(project.proposals[0].acceptedBy, []); assert.equal(project.proposals[0].status, 'correctionRequested'); assert.equal(revisionHash(project.proposals[0]), revisionHash(original));
  await assert.rejects(store.respond({ p_token: l.token, p_action: 'confirm', p_note: '', p_request_id: req() }), e => e.code === '40001');
});
test('closed committed links replay only matching minimal receipts without reopening evidence', async () => {
  const uid = 'ownerReceiptFirebase000000001'; let env = await create(uid); env = await change(uid, env, 'add_item', { item: item('a') }); env = await propose(uid, env, [item('a', 'Changed')]);
  const l = await link(uid, env); const unused = await link(uid, env);
  const params = { p_token: l.token, p_action: 'confirm', p_note: '', p_request_id: req() }; const receipt = await store.respond(params);
  await db.doc(`recallReviewLinks/${digest(l.token)}`).update({ expires: new Date(now - 1000).toISOString(), revokedAt: new Date(now).toISOString() });
  await db.doc(`recallReviewLinks/${digest(unused.token)}`).update({ expires: new Date(now - 1000).toISOString() });
  assert.deepEqual(await store.respond(params), receipt); assert.equal(Object.hasOwn(receipt, 'evidence'), false);
  await assert.rejects(store.review(l.token), e => e.code === 'P0002');
  await assert.rejects(store.respond({ ...params, p_note: 'Changed' }), e => e.code === '40001');
  await assert.rejects(store.respond({ ...params, p_token: unused.token, p_request_id: req() }), e => e.code === 'P0002');
});
test('local attachment paths, negative amounts and duplicate IDs cannot enter cloud revisions', async () => {
  const uid = 'ownerValidationFirebase000001'; let env = await create(uid); env = await change(uid, env, 'add_item', { item: item('a') });
  for (const payload of [{ items: [item('a', 'Changed')], evidence: [{ ...evidence[0], attachmentPath: '/private/secret.m4a' }] }, { items: [{ ...item('a'), amountMinor: -1 }], evidence }, { items: [item('a'), item('a')], evidence }]) await assert.rejects(change(uid, env, 'propose_change', payload), e => e.code === '22023');
  assert.equal((await store.listProjects(uid))[0].project.proposals.length, 0);
});
test('verified Pro limits, expiry/staleness and monotonic billing state are authoritative', async () => {
  const uid = 'ownerProFirebase000000000001'; await create(uid);
  const update = { ownerId: uid, active: true, environment: 'production', observedAt: new Date(now).toISOString(), expiresAt: new Date(now + 86400000).toISOString() };
  await store.applyBilling([update], 'event-pro'); assert.equal((await store.entitlement(uid)).projectLimit, 100); assert.equal((await store.entitlement(uid)).analysisDailyLimit, 20);
  await store.applyBilling([{ ...update, active: false, observedAt: new Date(now - 1000).toISOString() }], 'event-old'); assert.equal((await store.entitlement(uid)).active, true);
  assert.equal((await store.applyBilling([{ ...update, active: false }], 'event-pro')).duplicate, true);
  await db.doc(`recallOwners/${uid}/entitlements/pro`).update({ expiresAt: new Date(now - 1000).toISOString() }); assert.equal((await store.entitlement(uid)).projectLimit, 3);
  await db.doc(`recallOwners/${uid}/entitlements/pro`).update({ expiresAt: null, verifiedAt: new Date(now - 90000000).toISOString() }); assert.equal((await store.entitlement(uid)).status, 'stale');
});
test('per-user quota races and shared service budget are reserved atomically', async () => {
  const uid = 'ownerQuotaFirebase0000000001'; const day = new Date(now).toISOString().slice(0, 10);
  await db.doc(`recallOwners/${uid}/analysisUsage/${day}`).set({ count: 4 }); await db.doc(`recallServiceUsage/${day}`).set({ count: 0 });
  const free = await Promise.all([store.reserveAnalysis(uid, 100), store.reserveAnalysis(uid, 100)]); assert.deepEqual(free.sort(), [false, true]);
  assert.equal((await db.doc(`recallServiceUsage/${day}`).get()).data().count, 1);
  await db.doc(`recallServiceUsage/${day}`).set({ count: 99 });
  const global = await Promise.all(['quotaFanoutFirebaseA000000001', 'quotaFanoutFirebaseB000000001'].map(id => store.reserveAnalysis(id, 100))); assert.deepEqual(global.sort(), [false, true]);
  assert.equal((await db.doc(`recallServiceUsage/${day}`).get()).data().count, 100);
});
test('project and account deletion scrub cached sources/links and remain retry safe', async () => {
  const uid = 'ownerDeleteFirebase000000001'; let env = await create(uid); env = await change(uid, env, 'add_item', { item: item('a') }); env = await propose(uid, env, [item('a', 'Changed')]); const l = await link(uid, env);
  const params = { p_project_id: env.project.id, p_expected_version: env.version, p_action: 'delete', p_payload: {}, p_request_id: req() };
  const removed = await store.mutate(uid, params); assert.deepEqual(await store.mutate(uid, params), removed); assert.deepEqual(await store.listProjects(uid), []);
  await assert.rejects(store.review(l.token), e => e.code === 'P0002');
  const journals = await db.collection(`recallOwners/${uid}/requests`).get(); assert.equal(journals.docs.every(d => d.data().response.project === null), true);
  const globalBefore = (await db.collection('recallServiceUsage').get()).docs.map(d => d.data());
  let deleted = false; await store.deleteAccount(uid, async () => { deleted = true; }); assert.equal(deleted, true); assert.equal((await db.doc(`recallOwners/${uid}`).get()).exists, false);
  assert.deepEqual((await db.collection('recallServiceUsage').get()).docs.map(d => d.data()), globalBefore);
});

test('cached sandbox entitlements never unlock production limits by default', async () => {
  const uid = 'ownerSandboxFirebase00000001';
  await store.applyBilling([{ ownerId: uid, active: true, environment: 'sandbox', observedAt: new Date(now).toISOString(), expiresAt: new Date(now + 86400000).toISOString() }], 'sandbox-event');
  assert.equal((await store.entitlement(uid)).active, false); assert.equal((await store.entitlement(uid)).projectLimit, 3);
  const testing = new RecallStore(db, () => now, { allowSandbox: () => true }); assert.equal((await testing.entitlement(uid)).active, true);
});
test('Pro receives twenty AI reservations and the administrator cap only lowers the plan', async () => {
  const uid = 'ownerProQuotaFirebase0000001'; const day = new Date(now).toISOString().slice(0, 10);
  await store.applyBilling([{ ownerId: uid, active: true, environment: 'production', observedAt: new Date(now).toISOString(), expiresAt: new Date(now + 86400000).toISOString() }], 'pro-quota-event');
  await db.doc(`recallServiceUsage/${day}`).set({ count: 0 });
  for (let i = 0; i < 20; i++) assert.equal(await store.reserveAnalysis(uid, 100), true);
  assert.equal(await store.reserveAnalysis(uid, 100), false);
  const limited = 'ownerAdminCapFirebase0000001'; assert.equal(await store.reserveAnalysis(limited, 1), true); assert.equal(await store.reserveAnalysis(limited, 1), false);
});
test('large exact replay receipts are chunked and preserve Unicode without 1 MiB document overflow', async () => {
  const uid = 'ownerChunkFirebase0000000001'; let env = await create(uid);
  env = await change(uid, env, 'add_item', { item: item('a') });
  const payload = { items: [item('a', 'Changed')], evidence: Array.from({ length: 17 }, (_, index) => ({ id: `source-${index}`, text: 'தமிழ்😀'.repeat(2500), language: 'ta', kind: 'originalText' })) };
  const params = { p_project_id: env.project.id, p_expected_version: env.version, p_action: 'propose_change', p_payload: payload, p_request_id: req() };
  // Stay below the existing 800 KB request bound while exercising replay chunks.
  payload.evidence = Array.from({ length: 17 }, (_, index) => ({ id: `source-${index}`, text: 'x'.repeat(28000) + ' தமிழ்😀', language: 'ta', kind: 'originalText' }));
  const response = await store.mutate(uid, params); assert.deepEqual(await store.mutate(uid, params), response);
  const journal = (await db.doc(`recallOwners/${uid}/requests/${params.p_request_id}`).get()).data(); assert.ok(journal.chunkCount >= 2);
});

test('durable hashed deletion fence blocks verified continuations and post-deletion billing resurrection', async () => {
  const uid = 'ownerDeletionFenceFirebase001'; await create(uid);
  let release; const gate = new Promise(accept => { release = accept; });
  const pendingCreate = (async () => { await gate; return create(uid, 'Must not resurrect'); })();
  const pendingQuota = (async () => { await gate; return store.reserveAnalysis(uid); })();
  await store.deleteAccount(uid, async () => {}); release();
  const results = await Promise.allSettled([pendingCreate, pendingQuota]); assert.equal(results.every(r => r.status === 'rejected' && r.reason.code === '42501'), true);
  const update = { ownerId: uid, active: true, environment: 'production', observedAt: new Date(now).toISOString(), expiresAt: null };
  assert.equal((await store.applyBilling([update], 'post-delete-billing')).applied, 0);
  assert.equal((await db.doc(`recallOwners/${uid}/entitlements/pro`).get()).exists, false);
  assert.equal((await db.collection('recallProjects').where('ownerId', '==', uid).get()).empty, true);
  const fence = (await db.doc(`recallDeletedOwners/${digest(uid)}`).get()).data(); assert.deepEqual(Object.keys(fence), ['deletedAt']);
});

test('workspace budget serializes cross-project races, reserves publication space and releases deleted content', async () => {
  const uid = 'ownerWorkspaceBudgetFirebase1'; let a = await create(uid, 'Large A'); let b = await create(uid, 'Large B');
  a = await change(uid, a, 'add_item', { item: item('a') }); b = await change(uid, b, 'add_item', { item: item('b') });
  const sources = Array.from({ length: 17 }, (_, index) => ({ id: `budget-source-${index}`, text: 'x'.repeat(28000), language: 'en', kind: 'originalText' }));
  const addProposal = (env, suffix) => change(uid, env, 'propose_change', { items: [item(env.project.currentRevision.items[0].id, suffix)], evidence: sources });
  for (let index = 0; index < 3; index++) a = await addProposal(a, `Draft A ${index}`);
  for (let index = 0; index < 2; index++) b = await addProposal(b, `Draft B ${index}`);
  const races = await Promise.allSettled([addProposal(a, 'Racing A'), addProposal(b, 'Racing B')]);
  assert.equal(races.filter(result => result.status === 'fulfilled').length, 1);
  assert.equal(races.find(result => result.status === 'rejected').reason.code, '54000');
  const workspace = await store.listProjects(uid); const before = (await db.doc(`recallOwners/${uid}`).get()).data().workspaceBudgetBytes;
  assert.ok(before <= WORKSPACE_MAX); assert.ok(Buffer.byteLength(JSON.stringify({ data: workspace })) < 8 * 1024 * 1024);
  const accepted = races.find(result => result.status === 'fulfilled').value;
  const review = await link(uid, accepted); const receipt = await store.respond({ p_token: review.token, p_action: 'confirm', p_note: '', p_request_id: req() });
  assert.equal(receipt.status, 'confirmed');
  const after = (await db.doc(`recallOwners/${uid}`).get()).data().workspaceBudgetBytes; assert.ok(after < before);
  const projects = await store.listProjects(uid); const largeA = projects.find(env => env.project.id === a.project.id);
  await change(uid, largeA, 'delete');
  assert.ok((await db.doc(`recallOwners/${uid}`).get()).data().workspaceBudgetBytes < after);
  const remaining = (await store.listProjects(uid))[0]; await addProposal(remaining, 'Space is available again');
});
