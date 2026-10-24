// @ts-nocheck
// No audio/transcript persistence, content logging, redirects, or paid retries.
// Official multipart + JSON contract and current model checked 2026-10-24:
// https://developers.openai.com/api/docs/guides/speech-to-text
// https://developers.openai.com/api/reference/resources/audio/subresources/transcriptions/methods/create
// This endpoint has no documented `store` parameter. Do not claim zero provider retention.
import { strictJson } from '../analyze-source/core.ts';
export const maxAudioBytes = 20 * 1024 * 1024;
const maxRequestBytes = maxAudioBytes + 65536;
const endpoint = 'https://api.openai.com/v1/audio/transcriptions';
const models = new Set(['gpt-transcribe', 'gpt-4o-mini-transcribe', 'gpt-4o-transcribe']);
const types = new Map([
  ['audio/mp4', 'm4a'], ['audio/m4a', 'm4a'], ['audio/x-m4a', 'm4a'],
  ['audio/webm', 'webm'], ['video/webm', 'webm'], ['audio/wav', 'wav'],
  ['audio/x-wav', 'wav'], ['audio/mpeg', 'mp3'], ['audio/flac', 'flac'],
  ['audio/ogg', 'ogg'],
]);
class TranscriptionProblem extends Error {
  constructor(status, message) { super(message); this.status = status; }
}
async function boundedBytes(message, max, status = 413) {
  const length = message.headers.get('content-length');
  if (length && (!/^\d+$/.test(length) || Number(length) > max)) {
    throw new TranscriptionProblem(status, 'The recording or response exceeds its size limit.');
  }
  const reader = message.body?.getReader();
  if (!reader) throw new TranscriptionProblem(400, 'The recording is missing.');
  const chunks = [];
  let count = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      count += value.byteLength;
      if (count > max) {
        await reader.cancel();
        throw new TranscriptionProblem(status, 'The recording or response exceeds its size limit.');
      }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(count);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return bytes;
}
function matchesFormat(bytes, extension) {
  const ascii = (start, text) => [...text].every((char, i) => bytes[start + i] === char.charCodeAt(0));
  if (extension === 'm4a') return bytes.length >= 12 && ascii(4, 'ftyp');
  if (extension === 'webm') return [0x1a, 0x45, 0xdf, 0xa3].every((v, i) => bytes[i] === v);
  if (extension === 'wav') return bytes.length >= 12 && ascii(0, 'RIFF') && ascii(8, 'WAVE');
  if (extension === 'flac') return ascii(0, 'fLaC');
  if (extension === 'ogg') return ascii(0, 'OggS');
  return ascii(0, 'ID3') || (bytes.length >= 2 && bytes[0] === 0xff && (bytes[1] & 0xe0) === 0xe0);
}
export function createTranscriptionHandler({ env, verifyUser, reserveAnalysis, fetchProvider = fetch }) {
  return async request => {
    const origin = env('APP_ORIGIN');
    const headers = { 'content-type': 'application/json', 'cache-control': 'no-store', 'access-control-allow-origin': origin ?? '*', 'access-control-allow-headers': 'authorization, apikey, content-type, x-client-info', 'access-control-allow-methods': 'POST, OPTIONS', 'vary': 'Origin' };
    const send = (status, data) => new Response(JSON.stringify(data), { status, headers });
    try {
      if (origin && request.headers.get('origin') && request.headers.get('origin') !== origin) return send(403, { error: 'Origin unavailable.' });
      if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers });
      if (request.method !== 'POST') return send(405, { error: 'Use POST.' });
      const authorization = request.headers.get('authorization') ?? '';
      if (!authorization.startsWith('Bearer ')) return send(401, { error: 'Sign in before transcribing a recording.' });
      const contentType = request.headers.get('content-type') ?? '';
      if (!/^multipart\/form-data\s*;/i.test(contentType)) return send(415, { error: 'Use multipart/form-data.' });
      const bytes = await boundedBytes(request, maxRequestBytes);
      let input;
      try {
        input = await new Request('https://memory.invalid/', { method: 'POST', headers: { 'content-type': contentType }, body: bytes }).formData();
      } catch (_) { throw new TranscriptionProblem(400, 'The recording form could not be read.'); }
      if (input.getAll('consent').length !== 1 || input.get('consent') !== 'true') throw new TranscriptionProblem(400, 'Explicit consent=true is required before sending the whole recording to OpenAI.');
      if (input.getAll('audio').length !== 1 || [...input.keys()].some(key => !['consent', 'audio'].includes(key))) throw new TranscriptionProblem(400, 'Send consent and one audio file only.');
      const file = input.get('audio');
      if (!(file instanceof File) || file.size < 1) throw new TranscriptionProblem(400, 'The recording is empty.');
      if (file.size > maxAudioBytes) throw new TranscriptionProblem(413, 'Choose a recording no larger than 20 MiB.');
      const extension = types.get(file.type.toLowerCase());
      if (!extension) throw new TranscriptionProblem(415, 'This recording format is not supported.');
      const audio = new Uint8Array(await file.arrayBuffer());
      if (!matchesFormat(audio, extension)) throw new TranscriptionProblem(415, 'The recording does not match its audio format.');
      const user = await verifyUser(authorization.slice(7));
      if (!user) return send(401, { error: 'Sign in before transcribing a recording.' });
      if (env('RECALL_AI_ENABLED') !== '1') throw new TranscriptionProblem(503, 'AI transcription is not enabled on this server. Add a written source instead.');
      const key = env('OPENAI_API_KEY') ?? '';
      if (!key || key.length > 4096 || /[\s\u0000-\u001f]/.test(key)) throw new TranscriptionProblem(503, 'AI transcription is not configured. Add a written source instead.');
      const model = env('RECALL_TRANSCRIBE_MODEL') ?? 'gpt-transcribe';
      if (!models.has(model)) throw new TranscriptionProblem(503, 'The transcription model is unavailable. Add a written source instead.');
      const dailyLimit = Number(env('RECALL_AI_DAILY_LIMIT') ?? '20');
      if (!Number.isInteger(dailyLimit) || dailyLimit < 1 || dailyLimit > 100) throw new TranscriptionProblem(503, 'The transcription allowance is unavailable.');
      if (!reserveAnalysis || !(await reserveAnalysis(user.id, dailyLimit))) throw new TranscriptionProblem(429, 'Your daily AI allowance has been reached. Add a written source or try tomorrow.');
      const form = new FormData();
      form.set('model', model);
      form.set('response_format', 'json');
      // Sender filenames and local device paths never reach the provider.
      form.set('file', new Blob([audio], { type: file.type }), `recording.${extension}`);
      let transcript;
      try {
        const response = await fetchProvider(endpoint, { method: 'POST', redirect: 'error', signal: AbortSignal.timeout(45000), headers: { authorization: `Bearer ${key}` }, body: form });
        if (!response.ok) {
          await response.body?.cancel();
          throw new TranscriptionProblem([400, 401, 403, 404, 429].includes(response.status) ? 503 : 502, 'The transcription provider is unavailable. No automatic retry was made.');
        }
        const envelope = strictJson(new TextDecoder('utf-8', { fatal: true }).decode(await boundedBytes(response, 131072, 502)));
        if (!envelope || typeof envelope.text !== 'string' || !envelope.text.trim() || envelope.text.length > 30000 || /[\u0000-\u0008\u000b\u000c\u000e-\u001f\uD800-\uDFFF]/u.test(envelope.text)) throw new TranscriptionProblem(502, 'The transcription result could not be used. Your written source was not changed.');
        transcript = envelope.text;
      } catch (error) {
        if (error instanceof TranscriptionProblem) throw error;
        if (['TimeoutError', 'AbortError'].includes(error?.name)) throw new TranscriptionProblem(504, 'Transcription timed out. No automatic retry was made.');
        throw new TranscriptionProblem(502, 'Transcription could not complete. Your written source was not changed.');
      }
      return send(200, { status: 'review_required', kind: 'machine_transcript', model, text: transcript });
    } catch (error) {
      if (error instanceof TranscriptionProblem) return send(error.status, { error: error.message });
      return send(503, { error: 'Transcription is temporarily unavailable. Your written source was not changed.' });
    }
  };
}
