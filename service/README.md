# Local recipient review service

A working **development-only** Python standard-library service. It persists plan revisions and recipient responses in SQLite and serves an actual responsive browser review page in English, Spanish or French. No third-party Python packages are required.

This service is a local workflow foundation, **not a deployed SaaS**. It does not send email, authenticate the recipient's real identity, translate user content, collect payments, or provide an electronic-signature service. Optional AI analysis is disabled unless explicitly configured; it produces review suggestions only. The browser explicitly labels responses **“link-holder response; identity not verified.”**

## Run locally

Python 3.10+ is required. From the `recall_next` directory:

```sh
python3 service/run.py --port 8765
```

The runner creates/reuses a private, ignored `service/local-data/owner-token.txt` when `RECALL_SERVICE_TOKEN` is absent. It never prints the token. The file is mode 600; symlinked or broadly readable existing credential files are rejected. A configured `RECALL_SERVICE_TOKEN` takes precedence. A trusted local owner API client can read that private file; it must never be bundled in the mobile app.

Alternatively, configure a random `RECALL_SERVICE_TOKEN` of at least 32 characters through the process environment and run the service directly:

```sh
python3 service/app.py --port 8765
```

Default bind: `127.0.0.1`, loopback only. Default database: `service/local-data/recall.sqlite3`, excluded by `.gitignore`. The command never prints the owner token or recipient URLs. The CLI deliberately has no public-interface bind option.

Generate/load the owner token through a trusted environment/secret configuration. Do not commit it, paste it into screenshots, store it in a distributed mobile app, or put it into a URL. The owner API is intended for a trusted local development client. A shipping app needs per-user authentication and scoped authorization instead of one administrative token.

When using a sandbox that prohibits binding sockets, run the server/tests with the required local execution permissions. A permission-denied socket bind is not a working HTTP service.

## Core rules

1. Project creation records version 1 as an **owner-supplied baseline**. It does not claim that other participants independently confirmed that baseline in this service.
2. Proposals name the exact current `base_version`. A proposal receives a unique version number and stable revision ID, and its proposed plan is immutable.
3. The authenticated owner may respond only as the project's configured owner. Other participants receive scoped links bound to a revision and selected changed item IDs.
4. A participant reviewing only some items confirms **only those items**. Publication needs confirmation of **every changed item by every required participant**, including the owner. Several partial links can accumulate that coverage.
5. Publication and base-version checks happen in one `BEGIN IMMEDIATE` transaction. No pending proposal changes the current plan. Publishing one proposal makes competing pending proposals stale.
6. A correction or decline closes the proposal. It cannot later publish; create a fresh proposal based on the still-current plan.
7. Opening a page is not a response. Read receipts never approve anything. Identity remains unverified even after a successful link-holder confirmation.
8. Each issued link records at most one response. Repeating the same action/comment/version is idempotent; conflicting reuse is HTTP 409. The same rule applies to the owner response. A new proposal is required to change an already recorded answer.
9. Expired or revoked links cannot be opened or used for further responses. Revocation does not erase a response already accepted into the historical record. This dev service cannot retract published revisions; propose a correcting revision.
10. Only selected item values, source excerpts and original wording are included in a recipient page. Full project plans/other participants' responses remain owner-only. No full transcript is stored by this service.

The current implementation changes existing plan items only. Adding/removing items, defining participant-specific approval policies and participant administration are future API work. Every participant currently approves every changed item.

## Owner API contract

All `/api/*` endpoints require `Authorization: Bearer <RECALL_SERVICE_TOKEN>`. POST JSON must use `Content-Type: application/json`. Request bodies are capped at 64 KB. Cross-origin browser requests are rejected; there is no permissive CORS configuration.

| Method | Path | Purpose |
|---|---|---|
| GET | `/health` | Unauthenticated dev-mode health status; no project data. |
| GET | `/api/projects` | Owner list of project IDs/names/current revision pointers. |
| POST | `/api/analyze` | Optional consent-gated AI suggestions; no project/response writes. Disabled by default. |
| POST | `/api/projects` | Create owner-supplied initial plan and participants. |
| GET | `/api/projects/{project_id}` | Full owner snapshot with immutable revisions, responses, scoped-link metadata and identity labels. Raw link tokens are not recoverable. |
| POST | `/api/projects/{project_id}/revisions` | Propose a change to the exact current base. |
| POST | `/api/revisions/{revision_id}/owner-response` | Owner confirms, requests correction or declines. |
| POST | `/api/revisions/{revision_id}/links` | Issue one participant/item/revision-scoped review link. |
| POST | `/api/links/{link_id}/revoke` | Revoke a link; repeat revocation is safe. |

### Create project

```json
{
  "name": "Studio North launch videos",
  "owner_id": "alex",
  "participants": [
    {"id": "alex", "name": "Alex"},
    {"id": "marta", "name": "Marta"}
  ],
  "items": [
    {"id": "videos", "label": "Deliverables", "value": "2 short videos"},
    {"id": "date", "label": "Delivery date", "value": "30 October 2026"},
    {"id": "fee", "label": "Total fee", "value": "EUR 600"}
  ]
}
```

Returns HTTP 201 with `id`, `current_revision`, `participants` and `revisions`. Baseline version is 1. Participant/item IDs are unique strings containing letters, digits, underscore or hyphen. Two to twenty participants and one to one hundred plan items are supported.

### Propose revision

```json
{
  "base_version": 1,
  "changes": [
    {
      "item_id": "videos",
      "value": "3 short videos",
      "excerpt": "Could you add a third video?",
      "original": "¿Podrías añadir un tercer vídeo?",
      "language": "es"
    },
    {
      "item_id": "fee",
      "value": "EUR 850",
      "excerpt": "EUR 850 total, rather than an additional EUR 850.",
      "original": "por un total de 850 euros",
      "language": "es"
    }
  ]
}
```

Returns HTTP 201 with `revision_id`, `version`, `base_version` and `status: "pending"`. The creator remains responsible for correct values and evidence. Evidence/original excerpts are capped at 1,500 characters each; values at 2,000. Money and dates are strings in this small service; no parsing or currency/timezone inference is performed.

### Owner response

```json
{"version": 2, "action": "confirm", "comment": "I can deliver the revised work."}
```

Actions: `confirm`, `correction`, `decline`. The reviewed version must exactly match the route's revision. Owner confirmation covers all changed items. It does not impersonate or mark a recipient confirmed.

### Create recipient link

```json
{"participant_id": "marta", "item_ids": ["videos", "fee"], "ttl_seconds": 86400}
```

`item_ids` defaults to all changed items. Expiry is between 60 seconds and seven days. Returns HTTP 201 with `link_id`, **one-time returned `url`**, `expires` epoch seconds and `identity`. The raw URL is a bearer credential: give it only to the intended recipient, never to logs or analytics. Only a SHA-256 hash of the random 256-bit token is retained. There is no email send step.

### Browser recipient flow

`GET /review/{token}?lang=en` renders selected items. `lang` supports `en`, `es`, `fr`. Page UI is localized; **user-provided labels/values/excerpts are not machine-translated** and are explicitly described as such. No language-quality claim is implied.

The page embeds a short-lived CSRF nonce. Its POST form submits `action`, `comment`, exact `version`, `csrf` and `lang` to the same `/review/{token}` route. The server validates the **exact configured Origin**, nonce/token binding, link expiry/revocation, version and proposal state. Response is a persisted HTML receipt. No scripts, third-party assets or external network calls appear on the page.

Headers disable caching/framing, reduce referrers to origin only (never the bearer path), and restrict content with CSP. The origin-only policy preserves browser Origin on form submission; submissions with a missing/null Origin remain rejected. Owner API uses header credentials rather than ambient cookies. The built-in HTTP access logger is suppressed to avoid leaking bearer links. SQLite writes are serialized for publication. JSON duplicate properties and non-finite numbers are rejected, as are ambiguous request lengths or transfer encoding.

A receipt uses the validated review snapshot and committed response result. Expiry/revocation immediately after a successful commit cannot turn the receipt into a false “nothing recorded” error. Reopening a subsequently expired/revoked link still fails.

Historical published links distinguish a previously published revision from the newer current plan. An idempotent retry of an old response cannot make the receipt display that historical plan as current.

The review page offers full accessible language names, current-language state, visible keyboard focus, touch targets of at least 44 pixels for language/original controls, wrapping of long values and automatic direction for supplied text. Test supported languages with real assistive technology before launch; these local safeguards are not an accessibility certification.

## Optional AI analysis

The owner-only endpoint uses Python `urllib` and the OpenAI Responses API, with no third-party SDK. It is disabled by default. After a server credential has been provisioned securely, enable it in that process with `RECALL_AI_ENABLED=1`; `OPENAI_API_KEY` must already be configured on the server. Env files are **not automatically loaded**. `RECALL_AI_MODEL` optionally overrides the default `gpt-5.4-mini`; the selected model must support Responses and strict structured outputs. No key appears in requests from the mobile app, browser pages, service logs or responses.

The default model and `text.format` JSON-schema request were verified against official documentation on 24 October 2026: [GPT-5.4 mini](https://developers.openai.com/api/docs/models/gpt-5.4-mini), [Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs?api-mode=responses). Model availability remains subject to the configured OpenAI project.

```json
{
  "consent": true,
  "source_text": "Please change the total fee to EUR 850. The date is not decided.",
  "current_items": [
    {"id": "fee", "label": "Total fee", "value": "EUR 600"},
    {"id": "date", "label": "Delivery date", "value": "30 October 2026"}
  ]
}
```

`consent` must be the JSON boolean `true`. The caller must first show which selected text/current values will be sent to OpenAI and obtain the person's explicit permission. The API boolean alone is not a complete consent experience. Only send the minimum text the person selected, with no full transcript attached implicitly.

Limits: 12,000 source characters, 32 KB source UTF-8, one to twenty selected items, 48 KB total selected payload, 4,096 maximum output tokens and a 25-second network I/O timeout. The destination is fixed to `https://api.openai.com/v1/responses`; redirects are rejected. There are no tools or automatic retries. Each deliberate repeat request can incur API usage. `store: false` is set; this is not a promise of zero provider retention. Review the provider/project data controls before processing real data.

Successful HTTP 200 returns `status: "review_required"`, `model`, `source_sha256`, `warnings`, and `suggestions` in selected-item order. Each suggestion has `item_id`, nullable `proposed_value`, nullable `source_quote`, `intent` (`request`, `tentative`, `withdrawal`, `unclear`, `no_change`), `needs_clarification` and nullable `question`.

Strict JSON output is checked again locally. A source quote must be an exact contiguous substring of the submitted source. A non-null suggested value must be verbatim inside that quote. Unsupported evidence/values are discarded with a warning; ambiguous, tentative, withdrawn or missing values remain null. No currency conversion, added fee, inferred date/year/timezone or numeric calculation is accepted through normalization. **Exact wording does not prove its meaning or intent**: the model can still pick the wrong quoted amount or misread negation. A person must review every suggestion, especially money/currency/dates, then explicitly create a normal proposed revision. Analysis never confirms a participant or publishes a plan.

Disabled/missing configuration returns 503; missing consent/invalid input 400; provider refusal 422; invalid/incomplete provider output 502; network timeout 504. Provider error bodies, credentials and raw source are not logged or persisted by this module. The existing manual workflow remains available when analysis fails.

All AI verification in this build uses mocked responses. No paid live API call or model-accuracy evaluation has been performed. **Managed production AI remains blocked** on tenant authentication, rate/spending limits, retention/deletion rules, consent and privacy review, provider access, operational monitoring, and real multilingual/numeric/negation quality evaluations. This optional local foundation does not establish production AI quality.

### Errors

| Status | Meaning |
|---|---|
| 400 | Invalid body, IDs, values, participant or scope. |
| 401 | Missing/incorrect owner authentication. |
| 403 | Wrong/missing Origin on recipient POST, invalid CSRF session or cross-origin request. |
| 404 | Missing route/project/revision/link. |
| 409 | Wrong version, stale base, closed proposal or conflicting duplicate answer. |
| 410 | Expired/revoked link. |
| 413 | Missing/oversized body. |
| 415 | Wrong request content type. |
| 422 | Configured AI provider declined the selected analysis. |
| 502 / 504 | Invalid/unavailable AI response or network timeout; no plan change. |
| 503 | AI disabled, credential/configuration issue or provider rate/spending limit. |

The owner can poll `GET /api/projects/{project_id}` to see real recipient responses and the current published revision. Do not synthesize a recipient response in the mobile app to make its status appear complete.

## Tests

```sh
python3 -m unittest discover -s service -v
```

Tests cover immutable historical plans, persistence after restart, all-party/exact-version approval (including three participants), partial-link isolation, correction/decline, stale proposals, view-without-response, idempotent and concurrent retries, owner authentication, expiry/revocation, the receipt race, hash-only token persistence, private runner credentials, CSRF/Origin checks, strict JSON, HTTP behavior and escaped HTML. AI tests mock every network call and cover consent/configuration gates, input bounds, strict output, verbatim evidence/value checks, uncertainty, refusal, timeouts and safe errors. HTTP tests bind an ephemeral loopback port and need a permission context that allows this.

A real local Chrome check on 24 October 2026 covered widths of 390 and 320 pixels, doubled text without horizontal overflow, keyboard opening/focus of original wording, Spanish/French page navigation and a persisted confirmation that published version 2. The [fictional recipient screenshot](artifacts/recipient-review-mobile.png) shows that local review fixture; it contains no live customer or bearer-link data.

## Production prerequisites

Before using real external recipients, implement and independently test:

- TLS, a real deployed origin, hardened production server, backups and monitoring.
- Per-user auth, project/tenant authorization and recipient identity verification (for example, verified email challenge) tied to the exact reviewed version. Link possession alone remains unverified.
- A trusted server layer for the mobile app; never distribute the administrative service token.
- Correct recipient invitation/delivery, explicit send approval, rate limiting/abuse controls and protection against accidental link leakage.
- Schema migrations, concurrency/transaction behavior under deployment load, operational recovery, data retention/export/deletion and lifecycle rules for shared records.
- Billing/entitlements, real store purchase restoration and AI processing/consent if added elsewhere.
- Native review of supported UI/content translations, structured money/timezone semantics, participant-policy changes and material edits requiring fresh confirmation.
- A truthful legal/identity model: this service records development workflow responses and does not guarantee legal agreement, payment receipt or an electronic signature.

Do not expose the current `http.server` process to the internet or call the SQLite file encrypted storage. Local file permissions and hash-only link tokens are useful safeguards, not a complete production security design.
