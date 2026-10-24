# Recording transcription contract

`transcribe-recording` is an optional authenticated Supabase Edge Function. It
transcribes the whole recording only after explicit consent and returns a draft
for the owner to inspect. It does not save audio or transcripts, add evidence to a
project, publish an agreement, identify a speaker, or confirm another participant.
The source editor decides what the owner keeps after review.

Send an authenticated multipart `POST` containing exactly:

| Field | Value |
| --- | --- |
| `consent` | the single string `true` |
| `audio` | one nonempty audio file |

Unknown fields, duplicate consent/audio fields, local path fields and client
identity/model fields are rejected. The verified Auth user's UUID selects the
shared server AI quota. No request-body identity is accepted. UI consent must
explain that the entire recording will be sent to OpenAI; permission to keep a
recording on the device is a separate choice.

The file limit is **20 MiB**. The complete multipart request is bounded to 20 MiB
plus 64 KiB, including actual streamed bytes. A missing or forged Content-Length
cannot bypass either limit. MIME type and an audio-container signature must match.
Accepted MIME types cover M4A/MP4, WebM, WAV, MP3, FLAC and Ogg. These checks identify
the container, not whether the recording contains intelligible speech; the
provider must still be able to decode it.

The provider destination is fixed to
`https://api.openai.com/v1/audio/transcriptions`. The server creates a fresh
multipart body with a sanitized `recording.<extension>` filename, so the sender's
filename and device path are not forwarded. It requests JSON output, blocks
redirects, uses a 45-second timeout and makes no automatic paid retries.

Successful response:

```json
{
  "status": "review_required",
  "kind": "machine_transcript",
  "model": "gpt-transcribe",
  "text": "Transcript requiring review"
}
```

Responses use `Cache-Control: no-store`. They contain no owner ID, device filename,
path, audio bytes or original multipart fields. Transcript text can contain names
spoken in the recording; the function does not remove or verify those words.
The provider's result must be valid bounded UTF-8 JSON with a nonempty text field,
no duplicate JSON keys, no invalid surrogate/control characters, and at most
30,000 text units / 128 KiB response bytes. A machine transcript must retain its
machine-generated provenance when copied into a draft; it is not a verified
original quote, translation, speaker identification or agreement.

## Server deployment

The handler verifies the bearer access token with `auth.getUser`, so its config
uses `verify_jwt=false` while retaining application-level authentication.
Deployment requires the function and the existing analysis-quota migration.

| Server variable | Purpose |
| --- | --- |
| `RECALL_AI_ENABLED=1` | Explicit server enablement for optional AI calls |
| `OPENAI_API_KEY` | Server-only provider credential |
| `RECALL_TRANSCRIBE_MODEL` | Optional allowlisted model override |
| `RECALL_AI_DAILY_LIMIT` | Administrator upper cap for AI, default 20; 1–100 |
| `APP_ORIGIN` | Deployed web origin for CORS; native clients omit Origin |
| Supabase runtime variables | Auth verification and service-only quota reservation |

The default transcription model is `gpt-transcribe`. The current implementation
also permits server overrides `gpt-4o-mini-transcribe` and `gpt-4o-transcribe`.
Model choice never comes from the multipart input. Missing configuration leaves
transcription unavailable and written-source entry remains usable. Never put
provider or service-role secrets into Flutter's public build configuration.

A daily reservation occurs before the provider request and is not refunded for
provider failures. Transcription and source analysis share the same Auth UUID /
UTC-day counter through the service-only `recall_reserve_analysis` RPC. Free
accounts have up to 5 combined requests/day; fresh verified Pro has up to 20.
The administrator cap may lower those values. Every account also shares the
service-wide hard budget of 100 requests per UTC day, reserved atomically with
the per-user count. A denied reservation consumes neither counter. Account
deletion does not release spent aggregate budget. Provider
failure responses contain no provider error body, token or private diagnostics.
The transcription API has no documented `store` parameter here; this implementation
makes **no zero-retention claim about the provider**.

## Verification

Run `node --test supabase/tests/transcription_functions.test.mjs`. Its 18 tests
mock Auth, quota and provider calls in memory; no recording is uploaded and no
paid provider call occurs. Coverage includes consent/identity/configuration
checks, unknown and duplicate fields, actual streamed caps, MIME/signatures,
filename stripping, exact file limits, model routing, provider errors/timeouts,
malformed/oversized output, no retries and no-store responses.

Real Auth, deployed Edge invocation, device recording formats, speech accuracy,
latency and multilingual transcription quality require deployment/device checks.
Provider contract reference:
[OpenAI speech-to-text documentation](https://developers.openai.com/api/docs/guides/speech-to-text).
