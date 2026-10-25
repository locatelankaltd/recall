// All dependency injection is in memory. Never contacts Auth, OpenAI or an account.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createAnalysisHandler, strictJson } from '../lib/providers/analysis.js';

const body = () => ({ consent: true, source_text: 'Please change the fee to EUR 850. The date is not decided.', current_items: [{ id: 'fee', label: 'Total fee', value: 'EUR 600' }, { id: 'date', label: 'Delivery date', value: '30 October 2026' }] });
const row = (changes = {}) => ({ item_id: 'fee', proposed_value: 'EUR 850', source_quote: 'Please change the fee to EUR 850.', intent: 'request', needs_clarification: false, question: null, ...changes });
const provider = (data = { suggestions: [row()] }, extras = {}) => new Response(JSON.stringify({ status: 'completed', output: [{ type: 'message', content: [{ type: 'output_text', text: JSON.stringify(data) }] }], ...extras }), { status: 200 });
const request = (payload = body(), changes = {}) => new Request('https://edge.invalid/analyze-source', { method: 'POST', headers: { authorization: 'Bearer test-token', 'content-type': 'application/json' }, body: typeof payload === 'string' ? payload : JSON.stringify(payload), ...changes });
function harness({ environment = {}, response = () => provider(), user = { id: 'verified-owner' }, quota = true } = {}) {
  const calls = { auth: [], quota: [], provider: [] };
  const settings = { RECALL_AI_ENABLED: '1', OPENAI_API_KEY: 'fake-test-key-no-network', ...environment };
  const handler = createAnalysisHandler({ env: key => settings[key], verifyUser: async token => { calls.auth.push(token); return user; }, reserveAnalysis: async (...args) => { calls.quota.push(args); return quota; }, fetchProvider: async (...args) => { calls.provider.push(args); return response(...args); } });
  return { handler, calls };
}

test('AI requires explicit consent before Auth, quota or provider access', async () => {
  for (const consent of [false, null, 'true', 1]) {
    const { handler, calls } = harness();
    assert.equal((await handler(request({ ...body(), consent }))).status, 400);
    assert.deepEqual(calls, { auth: [], quota: [], provider: [] });
  }
});
test('AI checks source, selection, duplicate IDs and exact request fields before network', async () => {
  const duplicate = body(); duplicate.current_items.push(duplicate.current_items[0]);
  for (const payload of [{ ...body(), source_text: 'x'.repeat(12001) }, { ...body(), source_text: '😀'.repeat(9000) }, { ...body(), source_text: '\uD800' }, { ...body(), current_items: [] }, { ...body(), extra: true }, duplicate]) {
    const { handler, calls } = harness();
    assert.ok([400, 413].includes((await handler(request(payload))).status));
    assert.deepEqual(calls, { auth: [], quota: [], provider: [] });
  }
});
test('AI permits valid multilingual non-BMP characters within byte limits', async () => {
  const { handler } = harness({ response: () => provider({ suggestions: [] }) });
  assert.equal((await handler(request({ ...body(), source_text: 'தமிழ் العربية 日本語 😀 change request' }))).status, 200);
});
test('AI rejects duplicate JSON keys including escaped equivalents', () => {
  for (const input of ['{"x":1,"x":2}', '{"x":1,"\\u0078":2}', '{"nested":{"x":1,"x":2}}']) assert.throws(() => strictJson(input));
  assert.deepEqual(strictJson('{"x":[{"x":1},{"x":2}]}'), { x: [{ x: 1 }, { x: 2 }] });
});
test('AI requires Auth verification and enabled key before quota/provider', async () => {
  for (const options of [{ user: null }, { environment: { RECALL_AI_ENABLED: '' } }, { environment: { OPENAI_API_KEY: '' } }, { environment: { RECALL_AI_MODEL: 'https://evil.invalid' } }]) {
    const { handler, calls } = harness(options);
    const result = await handler(request());
    assert.ok([401, 503].includes(result.status));
    assert.equal(calls.quota.length, 0);
    assert.equal(calls.provider.length, 0);
  }
});
test('AI server quota gates the paid request and uses verified Auth identity', async () => {
  const { handler, calls } = harness({ quota: false });
  assert.equal((await handler(request())).status, 429);
  assert.deepEqual(calls.quota, [['verified-owner', 20]]);
  assert.equal(calls.provider.length, 0);
});
test('AI uses fixed bounded private strict Responses request without tools or redirects', async () => {
  const { handler, calls } = harness();
  const result = await handler(request());
  assert.equal(result.status, 200);
  const output = await result.json();
  assert.equal(output.status, 'review_required');
  assert.equal(output.suggestions[0].proposed_value, 'EUR 850');
  assert.equal(output.suggestions[1].proposed_value, null);
  assert.equal(output.suggestions[1].needs_clarification, true);
  assert.match(output.source_sha256, /^[a-f0-9]{64}$/);
  assert.equal(Object.hasOwn(output, 'source_text'), false);
  const [url, config] = calls.provider[0];
  const sent = JSON.parse(config.body);
  assert.equal(url, 'https://api.openai.com/v1/responses');
  assert.equal(config.redirect, 'error');
  assert.equal(sent.store, false);
  assert.equal(sent.max_output_tokens, 4096);
  assert.equal(sent.text.format.strict, true);
  assert.equal(sent.text.format.schema.additionalProperties, false);
  assert.equal(Object.hasOwn(sent, 'tools'), false);
  assert.equal(config.body.includes('fake-test-key'), false);
  assert.equal(calls.provider.length, 1);
  assert.equal(result.headers.get('cache-control'), 'no-store');
});
test('AI discards unsupported quotes, translations and inferred values', async () => {
  for (const bad of [row({ source_quote: 'We agreed EUR 850.' }), row({ proposed_value: '€850' }), row({ proposed_value: 'EUR 1450' }), row({ source_quote: null })]) {
    const { handler } = harness({ response: () => provider({ suggestions: [bad] }) });
    const result = await (await handler(request())).json();
    assert.equal(result.suggestions[0].proposed_value, null);
    assert.equal(result.suggestions[0].needs_clarification, true);
  }
});
test('AI tentative, withdrawn, unclear and questioned values stay unknown', async () => {
  for (const changes of [{ intent: 'tentative' }, { intent: 'withdrawal' }, { intent: 'unclear' }, { needs_clarification: true }, { question: 'Does that include tax?' }]) {
    const { handler } = harness({ response: () => provider({ suggestions: [row(changes)] }) });
    const result = await (await handler(request())).json();
    assert.equal(result.suggestions[0].proposed_value, null);
    assert.equal(result.suggestions[0].needs_clarification, true);
    assert.ok(result.suggestions[0].question);
  }
});
test('AI rejects extra, unknown and duplicate suggestions', async () => {
  for (const data of [{ suggestions: [row({ item_id: 'other' })] }, { suggestions: [row(), row()] }, { suggestions: [row({ confirmed: true })] }, { suggestions: [row({ needs_clarification: 'false' })] }, { suggestions: [], publish: true }]) {
    const { handler } = harness({ response: () => provider(data) });
    assert.equal((await handler(request())).status, 502);
  }
});
test('AI rejects incomplete, refused and oversized provider bodies', async () => {
  for (const response of [() => provider(undefined, { status: 'incomplete' }), () => provider(undefined, { output: [{ type: 'message', content: [{ type: 'refusal', refusal: 'private provider reason' }] }] }), () => new Response('x'.repeat(131073))]) {
    const { handler } = harness({ response });
    const result = await handler(request());
    assert.ok([422, 502].includes(result.status));
    assert.equal((await result.text()).includes('private provider reason'), false);
  }
});
test('AI provider failures expose no secret and are never retried', async () => {
  for (const status of [400, 401, 403, 429, 500]) {
    const { handler, calls } = harness({ response: () => new Response('private fake-test-key-no-network', { status }) });
    const result = await handler(request());
    assert.ok([502, 503].includes(result.status));
    assert.equal((await result.text()).includes('fake-test-key'), false);
    assert.equal(calls.provider.length, 1);
  }
  const { handler, calls } = harness({ response: () => { throw new DOMException('private timeout', 'TimeoutError'); } });
  assert.equal((await handler(request())).status, 504);
  assert.equal(calls.provider.length, 1);
});
test('AI rejects missing bearer, cross-origin calls and unsupported content type', async () => {
  const { handler, calls } = harness({ environment: { APP_ORIGIN: 'https://recall.invalid' } });
  assert.equal((await handler(request(body(), { headers: { 'content-type': 'application/json' } }))).status, 401);
  assert.equal((await handler(request(body(), { headers: { authorization: 'Bearer test', Origin: 'https://evil.invalid', 'content-type': 'application/json' } }))).status, 403);
  assert.equal((await handler(request(body(), { headers: { authorization: 'Bearer test', 'content-type': 'text/plain' } }))).status, 415);
  assert.equal(calls.provider.length, 0);
});
