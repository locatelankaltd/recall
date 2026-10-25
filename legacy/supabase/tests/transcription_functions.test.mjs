// All Auth/quota/provider dependencies are mocks. No audio leaves this process.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createTranscriptionHandler, maxAudioBytes } from '../functions/transcribe-recording/core.ts';
const owner = '11111111-1111-1111-1111-111111111111';
const audio = (type = 'audio/mpeg', bytes = new Uint8Array([0x49, 0x44, 0x33, 0])) => new File([bytes], '/private/person/recording-secret.mp3', { type });
const form = ({ consent = 'true', file = audio(), extra, duplicateConsent = false, duplicateAudio = false } = {}) => {
  const body = new FormData();
  if (consent !== null) body.append('consent', consent);
  body.append('audio', file);
  if (duplicateConsent) body.append('consent', 'true');
  if (duplicateAudio) body.append('audio', file);
  if (extra) body.append(extra, 'forged-user-or-private-path');
  return body;
};
const request = (body = form(), changes = {}) => new Request('https://edge.invalid/transcribe-recording', { method: 'POST', headers: { Authorization: 'Bearer verified-test-token' }, body, ...changes });
function harness({ environment = {}, user = { id: owner }, quota = true, provider = () => new Response(JSON.stringify({ text: 'தமிழ் source text 😀' })), verifyError = false } = {}) {
  const calls = { auth: [], quota: [], provider: [] };
  const settings = { RECALL_AI_ENABLED: '1', OPENAI_API_KEY: 'fake-key-never-sent-to-network', ...environment };
  const handler = createTranscriptionHandler({ env: key => settings[key], verifyUser: async token => { calls.auth.push(token); if (verifyError) throw new Error('private auth detail'); return user; }, reserveAnalysis: async (...args) => { calls.quota.push(args); return quota; }, fetchProvider: async (...args) => { calls.provider.push(args); return provider(...args); } });
  return { handler, calls };
}

test('transcription requires explicit single true consent before any Auth or provider access', async () => {
  for (const options of [{ consent: null }, { consent: 'false' }, { consent: '1' }, { consent: 'TRUE' }, { duplicateConsent: true }]) {
    const { handler, calls } = harness();
    assert.equal((await handler(request(form(options)))).status, 400);
    assert.deepEqual(calls, { auth: [], quota: [], provider: [] });
  }
});
test('transcription rejects duplicate audio, unknown identity/path fields and non-file audio', async () => {
  for (const options of [{ duplicateAudio: true }, { extra: 'user_id' }, { extra: 'attachmentPath' }, { file: '/private/recording.mp3' }]) {
    const { handler, calls } = harness();
    assert.equal((await handler(request(form(options)))).status, 400);
    assert.deepEqual(calls, { auth: [], quota: [], provider: [] });
  }
});
test('transcription checks bearer, content type, method and origin without network', async () => {
  const { handler, calls } = harness({ environment: { APP_ORIGIN: 'https://recall.invalid' } });
  assert.equal((await handler(request(form(), { headers: {} }))).status, 401);
  assert.equal((await handler(request('{}', { headers: { Authorization: 'Bearer token', 'Content-Type': 'application/json' } }))).status, 415);
  assert.equal((await handler(new Request('https://edge.invalid', { method: 'GET' }))).status, 405);
  assert.equal((await handler(request(form(), { headers: { Authorization: 'Bearer token', Origin: 'https://evil.invalid' } }))).status, 403);
  const preflight = await handler(new Request('https://edge.invalid', { method: 'OPTIONS', headers: { Origin: 'https://recall.invalid' } }));
  assert.equal(preflight.status, 204);
  assert.equal(preflight.headers.get('access-control-allow-origin'), 'https://recall.invalid');
  assert.deepEqual(calls, { auth: [], quota: [], provider: [] });
});
test('transcription rejects malformed multipart and empty recordings', async () => {
  const { handler, calls } = harness();
  assert.equal((await handler(request('not multipart', { headers: { Authorization: 'Bearer token', 'Content-Type': 'multipart/form-data; boundary=bad' } }))).status, 400);
  assert.equal((await handler(request(form({ file: audio('audio/mpeg', new Uint8Array()) })))).status, 400);
  assert.equal(calls.provider.length, 0);
});
test('transcription rejects unsupported MIME and mismatched file signatures before network', async () => {
  for (const file of [audio('text/plain'), audio('application/octet-stream'), audio('audio/wav'), audio('audio/mp4'), audio('audio/webm'), audio('audio/ogg'), audio('audio/flac'), audio('audio/mpeg', new Uint8Array([1, 2, 3]))]) {
    const { handler, calls } = harness();
    assert.equal((await handler(request(form({ file })))).status, 415);
    assert.equal(calls.auth.length, 0);
    assert.equal(calls.provider.length, 0);
  }
});
test('transcription accepts supported audio signatures and sanitizes names for each format', async () => {
  const fixture = [
    ['audio/mp4', [0, 0, 0, 12, 102, 116, 121, 112, 0, 0, 0, 0], 'm4a'],
    ['audio/webm', [0x1a, 0x45, 0xdf, 0xa3], 'webm'],
    ['audio/wav', [...Buffer.from('RIFF0000WAVE')], 'wav'],
    ['audio/flac', [...Buffer.from('fLaC')], 'flac'],
    ['audio/ogg', [...Buffer.from('OggS')], 'ogg'],
    ['audio/mpeg', [0xff, 0xfb], 'mp3'],
  ];
  for (const [type, bytes, extension] of fixture) {
    const { handler, calls } = harness();
    assert.equal((await handler(request(form({ file: audio(type, new Uint8Array(bytes)) })))).status, 200);
    assert.equal(calls.provider[0][1].body.get('file').name, `recording.${extension}`);
  }
});
test('transcription accepts a 20 MiB audio file and rejects any larger file', async () => {
  const bytes = new Uint8Array(maxAudioBytes); bytes.set([0x49, 0x44, 0x33]);
  const { handler, calls } = harness();
  assert.equal((await handler(request(form({ file: audio('audio/mpeg', bytes) })))).status, 200);
  assert.equal(calls.provider[0][1].body.get('file').size, maxAudioBytes);
  const tooLarge = new Uint8Array(maxAudioBytes + 1); tooLarge.set([0x49, 0x44, 0x33]);
  const rejected = harness();
  assert.equal((await rejected.handler(request(form({ file: audio('audio/mpeg', tooLarge) })))).status, 413);
  assert.equal(rejected.calls.provider.length, 0);
});
test('transcription enforces streamed actual body cap despite absent or forged Content-Length', async () => {
  for (const declaredLength of [null, '1']) {
    let cancelled = false;
    const stream = new ReadableStream({ start(controller) { controller.enqueue(new Uint8Array(maxAudioBytes + 65537)); }, cancel() { cancelled = true; } });
    const headers = { Authorization: 'Bearer token', 'Content-Type': 'multipart/form-data; boundary=test' };
    if (declaredLength !== null) headers['Content-Length'] = declaredLength;
    const { handler, calls } = harness();
    const result = await handler(new Request('https://edge.invalid', { method: 'POST', headers, body: stream, duplex: 'half' }));
    assert.equal(result.status, 413);
    assert.equal(cancelled, true);
    assert.deepEqual(calls, { auth: [], quota: [], provider: [] });
  }
});
test('transcription rejects invalid and oversized Content-Length without reading body', async () => {
  for (const length of ['not-a-number', String(maxAudioBytes + 65537)]) {
    const { handler, calls } = harness();
    const result = await handler(request('not multipart', { headers: { Authorization: 'Bearer token', 'Content-Type': 'multipart/form-data; boundary=test', 'Content-Length': length } }));
    assert.equal(result.status, 413);
    assert.equal(calls.auth.length, 0);
  }
});
test('transcription requires verified Auth, enabled AI, safe key and allowed model before quota/provider', async () => {
  for (const options of [{ user: null }, { verifyError: true }, { environment: { RECALL_AI_ENABLED: '' } }, { environment: { OPENAI_API_KEY: '' } }, { environment: { OPENAI_API_KEY: 'invalid secret whitespace' } }, { environment: { RECALL_TRANSCRIBE_MODEL: 'https://evil.invalid' } }, { environment: { RECALL_AI_DAILY_LIMIT: '101' } }]) {
    const { handler, calls } = harness(options);
    assert.ok([401, 503].includes((await handler(request())).status));
    assert.equal(calls.quota.length, 0);
    assert.equal(calls.provider.length, 0);
  }
});
test('transcription reserves shared server quota for Auth UUID only', async () => {
  const { handler, calls } = harness({ quota: false, environment: { RECALL_AI_DAILY_LIMIT: '7' } });
  assert.equal((await handler(request())).status, 429);
  assert.deepEqual(calls.quota, [[owner, 7]]);
  assert.equal(calls.provider.length, 0);
});
test('transcription uses fixed multipart endpoint/model, sanitized filename and no paid retries', async () => {
  const { handler, calls } = harness();
  const response = await handler(request());
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('cache-control'), 'no-store');
  const output = await response.json();
  assert.deepEqual(Object.keys(output).sort(), ['kind', 'model', 'status', 'text']);
  assert.equal(output.status, 'review_required');
  assert.equal(output.kind, 'machine_transcript');
  assert.equal(output.model, 'gpt-transcribe');
  assert.equal(output.text, 'தமிழ் source text 😀');
  assert.equal(JSON.stringify(output).includes(owner), false);
  assert.equal(JSON.stringify(output).includes('/private'), false);
  const [url, config] = calls.provider[0];
  assert.equal(url, 'https://api.openai.com/v1/audio/transcriptions');
  assert.equal(config.method, 'POST');
  assert.equal(config.redirect, 'error');
  assert.ok(config.signal instanceof AbortSignal);
  assert.equal(config.body.get('model'), 'gpt-transcribe');
  assert.equal(config.body.get('response_format'), 'json');
  assert.equal(config.body.get('file').name, 'recording.mp3');
  assert.deepEqual([...config.body.keys()].sort(), ['file', 'model', 'response_format']);
  assert.equal(calls.provider.length, 1);
});
test('transcription allows server model override without accepting client model fields', async () => {
  const { handler, calls } = harness({ environment: { RECALL_TRANSCRIBE_MODEL: 'gpt-4o-mini-transcribe' } });
  assert.equal((await handler(request())).status, 200);
  assert.equal(calls.provider[0][1].body.get('model'), 'gpt-4o-mini-transcribe');
  assert.equal((await handler(request(form({ extra: 'model' })))).status, 400);
  assert.equal(calls.provider.length, 1);
});
test('transcription provider failures never expose error bodies, credentials or retry', async () => {
  for (const status of [400, 401, 403, 404, 429, 500]) {
    const { handler, calls } = harness({ provider: () => new Response('private fake-key-never-sent-to-network', { status }) });
    const result = await handler(request());
    assert.equal(result.status, status === 500 ? 502 : 503);
    const text = await result.text();
    assert.equal(text.includes('fake-key'), false);
    assert.equal(text.includes('private'), false);
    assert.equal(calls.provider.length, 1);
  }
});
test('transcription provider timeouts and transport errors do not retry', async () => {
  for (const [error, status] of [[new DOMException('private', 'TimeoutError'), 504], [new DOMException('private', 'AbortError'), 504], [new Error('private connection'), 502]]) {
    const { handler, calls } = harness({ provider: () => { throw error; } });
    const result = await handler(request());
    assert.equal(result.status, status);
    assert.equal((await result.text()).includes('private'), false);
    assert.equal(calls.provider.length, 1);
  }
});
test('transcription rejects invalid, empty, control-character and oversized provider results', async () => {
  for (const raw of ['not json', '{}', '{"text":null}', '{"text":""}', JSON.stringify({ text: 'x'.repeat(30001) }), JSON.stringify({ text: '\u0000bad' }), 'x'.repeat(131073)]) {
    const { handler, calls } = harness({ provider: () => new Response(raw) });
    assert.equal((await handler(request())).status, 502);
    assert.equal(calls.provider.length, 1);
  }
  const { handler } = harness({ provider: () => new Response(new Uint8Array([0xff, 0xff])) });
  assert.equal((await handler(request())).status, 502);
});
test('transcription rejects streamed oversized provider bodies without trusting length header', async () => {
  let cancelled = false;
  const { handler, calls } = harness({ provider: () => new Response(new ReadableStream({ start(controller) { controller.enqueue(new Uint8Array(131073)); }, cancel() { cancelled = true; } }), { headers: { 'Content-Length': '1' } }) });
  assert.equal((await handler(request())).status, 502);
  assert.equal(cancelled, true);
  assert.equal(calls.provider.length, 1);
});
test('transcription rejects duplicate provider JSON text keys and malformed surrogate text', async () => {
  for (const raw of ['{"text":"first","text":"second"}', JSON.stringify({ text: '\uD800' })]) {
    const { handler } = harness({ provider: () => new Response(raw) });
    assert.equal((await handler(request())).status, 502);
  }
});
