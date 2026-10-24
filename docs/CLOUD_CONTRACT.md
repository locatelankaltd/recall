# Recall cloud contract v1

The Flutter app calls Supabase Auth and public RPC functions. It never writes
project tables. `supabase/migrations/202610240001_recall_cloud.sql` is the complete
schema migration. Cloud deployment is a separate step; local test success does
not mean a Supabase project is deployed.

## Authentication and canonical project data

The client build variable `SUPABASE_ANON_KEY` accepts a modern publishable key
(`sb_publishable_...`) or a legacy anon key. Public review read/respond RPCs use an
independent plain HTTP client with only the `apikey` header, no `Authorization`
header and no private-session/token lookup. An expired owner session therefore
cannot hijack a recipient request. The scoped review token stays in the RPC body;
it is separate from the Supabase API key. This protocol is covered by client tests;
hosted behavior still needs the selected project's integration check.

All owner RPCs require an authenticated Supabase user. Ownership is a UUID from
`auth.uid()`, stored separately from the project's domain participants. Domain
IDs remain the strings `you` and `client`. The owner can act only as `you`.

`Project` JSON uses the exact Dart `Project.toJson()` field names and enum values:
`id`, `title`, `clientName`, `category`, `participants`, `currentRevision`,
`proposals`, `archivedRevisions`, `history`, `itemStatuses`, `isDemo`. Item and
revision IDs are text, not UUID columns. Server-generated timestamps are ISO 8601.
`amountMinor` is an integer in minor units, between zero and 9,007,199,254,740,991.
Dates are date-only, emitted as `YYYY-MM-DDT00:00:00.000`. Unicode text, currency
codes and free-form source-language labels support international projects.

Cloud source evidence contains the Dart fields `id`, `text`, `language`, `kind`,
`createdAt`, `attachmentPath:null`. The server creates `createdAt`. Non-null
`attachmentPath` is rejected; the client must remove device recording paths
before an upload. No audio or files are uploaded by this backend. Source kinds
remain `originalText` and `personalRecollection`; recollections never become
verified quotes. Translation is not implied by the stored language label.

## Owner project RPCs

| RPC | Parameters | Result |
| --- | --- | --- |
| `recall_list_projects` | none | `[{project: Project, version: integer}]` |
| `recall_create_project` | `p_title`, `p_client_name`, `p_category`, `p_request_id` | `{project: Project, version: integer}` |
| `recall_mutate_project` | `p_project_id`, `p_expected_version`, `p_action`, `p_payload`, `p_request_id` | `{project: Project, version: integer}` |

The request ID is 8–128 ASCII letters, numbers, dashes or underscores; a random
UUID is suitable. An identical create/mutation retry returns its original result.
Reusing an ID for a different payload fails. A retry can return a historical
snapshot: refresh after uncertain connectivity before making a new edit.

`p_expected_version` is the project envelope version, starting at 1 and incremented
by every successful project mutation or recipient response. It is separate from
a revision's displayed `number`. A row lock and version comparison make the
mutation atomic. A rejected request changes nothing.

| `p_action` | `p_payload` |
| --- | --- |
| `add_item` | `{item: PlanItemJSON}` |
| `propose_change` | `{items: [PlanItemJSON], evidence: [EvidenceJSON], authorId: "you"}` |
| `confirm` | `{revisionId: string, actorId: "you"}` |
| `correction` | `{revisionId: string, actorId: "you", note: string}` |
| `set_status` | `{itemId: string, status: "open"\|"inProgress"\|"delivered"\|"accepted", actorId: "you"}` |
| `delete` | `{}` |

`delete` returns `{project:null, version:integer, deleted:true, projectId:string}`.
It deletes snapshots, review links, receipts, progress and events. Old idempotency
responses are scrubbed into deletion tombstones, so they retain no project text.

A private baseline initially requires only `you`; adding an item creates a new
confirmed private snapshot and archives the old one. Once a version has been
shared, additions must use a proposal. Proposals always require both project
participants, automatically record the author's review, and preserve the current
plan. Proposals must contain a real change, 1–100 items, and 1–20 evidence sources.
Each source permits at most 30,000 characters and an 80-character language label.
Titles, details, dates, ownership, amounts, duplicates and currency are validated.
The authenticated owner cannot submit `actorId:"client"` or author a client reply.

Revision IDs and all proposal content are immutable at the database level. A
confirmation references the immutable revision and current project CAS version;
client-provided replacement snapshots are never accepted. Corrections close a
proposal, clear its acceptances and item confirmations, and require a new proposal.
Staleness derives from the proposal's base revision versus the current revision.

Progress belongs to the current plan, separately from agreement snapshots. Only
the item owner records progress or delivery; only the recipient can accept after
delivery. Progress does not record payment. Changed items reset progress when a
proposal becomes current; unchanged items keep their progress.

## Review link RPCs

`recall_create_review_link(p_project_id, p_revision_id, p_participant_id,
p_item_ids DEFAULT NULL, p_ttl_seconds DEFAULT 86400)` requires the project owner.
The participant must be `client`. The proposal must still be open and based on
the current plan. `p_item_ids` is a nonempty unique subset of changed item IDs;
NULL selects all changes. TTL is 60–604800 seconds (one minute to seven days).

The result is `{id, token, expires, revisionId, participantId, itemIds, identity}`.
The bearer token has 256 random bits, encoded as 64 hexadecimal characters. Only
its SHA-256 hash is stored. The token is shown once; neither list RPCs nor the
database can retrieve it. Creating another link mints a separate revocable link.
Do not log the token, store it in analytics, or put it into a query string. A web
client can use a URL fragment and then call the RPC via POST.

`recall_list_review_links(p_project_id)` requires ownership and returns
`[{id, revisionId, participantId, itemIds, expires, revoked:boolean,
responded:boolean}]`. It returns neither raw tokens nor their hashes.
`recall_revoke_review_link(p_link_id)` requires ownership and returns
`{id, revoked:true}`; repeated revocation is safe.

`recall_review_link(p_token)` can be called by `anon` or `authenticated` and returns:

```json
{
  "projectTitle": "Project title",
  "participantName": "Client name",
  "revisionId": "revision-id",
  "version": 4,
  "baseRevisionId": "base-id",
  "currentRevisionId": "current-id",
  "status": "proposed",
  "changes": [{"itemId":"item-id", "previous":{}, "proposed":{}}],
  "evidence": [],
  "evidenceOmitted": false,
  "canRespond": true,
  "response": null,
  "identity": "link-holder response; identity not verified"
}
```

`previous` and `proposed` contain one canonical PlanItem each, or null for an
addition/removal. Only selected changed items are returned. Full revision evidence
is exposed only for links covering every changed item; partial scopes omit the
unscoped sources and set `evidenceOmitted:true`. The link never exposes the full
project, participant list, unrelated plan items, history, owner UUID, other links,
or device attachment paths. Status uses Dart revision states plus derived `stale`.
Expired, revoked and unknown links return an unavailable error.

`recall_respond_review(p_token, p_action, p_note, p_request_id)` takes action
`confirm`, `correction` or `decline`; a correction needs a nonempty note. Notes
permit at most 2,000 characters. Its receipt is
`{receiptId, revisionId, version, action, status, identity}`. A repeat with the
same link, request ID and payload returns the same minimal committed receipt,
including after later expiry or revocation. Full source/context access remains
closed after expiry or revocation; an uncommitted closed link cannot respond. A conflicting repeat fails. One link records one immutable response.
Review reads include `response:{receiptId,action,note,identity}` after a response.

Each confirmation covers only the link's immutable version and selected item IDs.
A revision becomes current only when every required participant has confirmed
every changed item. Overlapping links cannot increase coverage incorrectly.
A project row lock serializes simultaneous responses, corrections, owner changes
and publication. After one competing proposal publishes, others become stale and
cannot replace it. Correction or decline closes the whole proposal.

A bearer response explicitly has **unverified identity**. Possession of a link
is not proof of the named recipient, a signature, identity verification, payment,
or legal enforceability. There is no email sending in this backend.

## Account deletion

Call the `account-delete` Edge Function via an authenticated `POST`. Its body
accepts no user ID. The function validates the supplied access token with
`auth.getUser`, then uses the server-only service role to delete that exact Auth
user. Foreign-key cascades remove all workspace, evidence, links, responses and
request records. A deleted account cannot authenticate a retry; the app should
clear its session on success. The service key never belongs in Flutter config.

The function authenticates the JWT itself, so `verify_jwt=false` supports current
Supabase signing-key formats without relying on the gateway's legacy verifier.
Set `APP_ORIGIN` to the deployed web app origin; native clients omit Origin.
Without it, CORS permits origins but every destructive call still requires a
valid bearer access token verified by Auth. Errors expose no credentials or user
records. Deployment must include this function as well as the SQL migration.

## Security and local verification

All data tables live in an unexposed `recall_private` schema with RLS enabled and
owner-only SELECT policies. API roles receive no schema/table access and no write
policies. Public RPC functions use `SECURITY DEFINER`, `search_path=''`, explicit
ownership checks and explicit execute grants. Private helpers have no API grants.
Do not add blanket table grants or put the private schema in exposed API schemas.

Errors: `28000` authentication required, `42501` forbidden actor/action, `P0002`
unavailable project/link, `22023` invalid payload/request reuse, `40001` stale CAS
or closed/conflicting response. Treat unknown errors as retryable without showing
SQL or secrets. Refetch after `40001` and ask the user to review the new state.

Run `supabase/tests/run_local.sh`. It starts a disposable UTF-8 PostgreSQL cluster,
loads a minimal Auth/role harness, applies every migration, and checks 89 security
and workflow assertions. It also races separate sessions to verify CAS and
competing revision publication. It never connects to a cloud database. Override
`RECALL_PG_BIN` and `RECALL_TEST_PORT` for another local PostgreSQL installation.
The tests cover SQL behavior and mocked `auth.uid()`, not live Auth, gateway,
Edge Function deployment, email delivery or device integration.

Implementation references: [Supabase API key migration](https://supabase.com/docs/guides/getting-started/migrating-to-new-api-keys),
[Supabase database functions](https://supabase.com/docs/guides/database/functions)
and [row-level security](https://supabase.com/docs/guides/database/postgres/row-level-security).

## Optional source analysis

The `analyze-source` Edge Function accepts the existing local-service contract:
`{consent:true, source_text:string, current_items:[{id,label,value}]}`. The exact
field set is enforced. It requires a verified bearer Auth user, explicit consent,
server `RECALL_AI_ENABLED=1`, and server-only `OPENAI_API_KEY`. No provider call is
made when any gate fails. `RECALL_AI_MODEL` defaults to the existing app's
`gpt-5.4-mini`; deployment can select another compatible Responses model.

Source text is limited to 12,000 Unicode characters / 32 KB; 1–20 selected items
and the complete request are bounded to 48 KB. Invalid Unicode, control characters,
duplicate JSON keys and duplicate item IDs are rejected. Device paths and source
files are not accepted as fields. A server-only atomic daily quota reserves one
analysis before a paid call; `RECALL_AI_DAILY_LIMIT` defaults to 20 and permits
1–100 as an administrator upper cap. Actual account limits are Free 5 / verified
Pro 20 requests per UTC day, lowered when the administrator cap is smaller.
Analysis and transcription also share an atomic global service budget of 100
attempts per UTC day, protecting against account fanout. Quotas use the verified
Auth UUID and retain counts only.
The `recall_reserve_analysis` RPC is executable only by `service_role`.

The provider destination is fixed to OpenAI's Responses endpoint, redirects are
blocked, `store:false` is sent, strict JSON Schema is requested, output is bounded
to 4096 tokens / 128 KB, and the request times out after 25 seconds. There are no
automatic paid retries and no model tools. The function never writes a project or
records a participant response. A provider failure still consumes its daily
reservation, bounding the number of attempted paid calls.

Successful output is `{status:"review_required",model,source_sha256,suggestions,
warnings}`. Each suggestion contains `item_id`, `proposed_value`, `source_quote`,
`intent`, `needs_clarification`, `question`. Quotes must be exact contiguous source
substrings; proposed values must be verbatim inside their quote. Unsupported,
translated, tentative, withdrawn, questioned or ambiguous values remain null and
need human clarification. Missing item suggestions are explicitly unknown. Every
amount, currency and date still needs review. There is no automatic agreement,
date resolution, money calculation, source translation or speaker verification.

Reference: [OpenAI structured outputs](https://developers.openai.com/api/docs/guides/structured-outputs).

## Verified subscriptions

Billing uses RevenueCat with the authenticated Supabase UUID as App User ID.
`recall_entitlement()` requires Auth and returns only the caller's entitlement:
`{entitlement:"pro", active:boolean, expiresAt:ISO|null, verifiedAt:ISO|null,
environment:"production"|"sandbox"|"unknown",
status:"active"|"inactive"|"unverified"|"stale", projectLimit:3|100,
analysisDailyLimit:5|20}`.

The enforced account plans are Free: 3 projects / up to 5 combined AI requests
per UTC day, and verified Pro: 100 projects / up to 20 combined AI requests.
Project creation is serialized per owner so concurrent requests cannot exceed
the cap. Existing records remain readable after a downgrade; new creation is
blocked while the owner is at or above the current limit. An identical creation
retry remains idempotent at the limit. SQLSTATE `54000` reports a project cap.

A row never written by the server is unverified and inactive. Expiry is evaluated
at read time, including verified billing grace time. Verification older than
24 hours becomes stale and inactive until refreshed. The service role alone can
write the private entitlement table. Neither direct client writes, webhook paid
flags nor SDK `CustomerInfo` unlock a server entitlement.

Call `refresh-entitlement` via authenticated `POST` after purchase/restore or when
refreshing subscription status. It verifies Auth and reconciles only that UUID;
request-body identifiers and paid flags are ignored. The result has the same shape
as `recall_entitlement()`. Missing server billing configuration returns unavailable
and grants no paid status. A provider outage leaves the previous verified record
intact, subject to its normal expiry and 24-hour freshness limit.

`billing-webhook` accepts RevenueCat POSTs only when their full `Authorization`
header exactly matches server `REVENUECAT_WEBHOOK_AUTH` (at least 32 characters).
Configure that same random value in the RevenueCat webhook dashboard. Secret
hashes are compared without early-exit string comparison. Dashboard TEST events
are acknowledged without changing paid state.

Authenticated events select UUID identities to reconcile, not entitlement values.
The function fetches fresh `GET https://api.revenuecat.com/v1/subscribers/{uuid}`
using server `REVENUECAT_SECRET_API_KEY`. It derives `pro` from the returned
entitlement, product purchase, expiry, grace period, refund and `is_sandbox`.
Unknown purchase environments remain inactive. Sandbox purchases do not grant paid
access unless server `RECALL_ALLOW_SANDBOX_BILLING=1` is explicitly enabled for a
test deployment. A webhook's claimed environment cannot override the REST state.
No email address, arbitrary URL or RevenueCat anonymous ID becomes a Recall user.

TRANSFER events reconcile UUIDs in both `transferred_from` and `transferred_to`;
normal events reconcile UUIDs in the user/original-user/alias fields. Event IDs
are deduplicated as hashes after successful transactional writes. No raw billing
webhook, subscriber attributes, email, card details or access token is stored.
All writes use the provider's fresh request timestamp, so an older response that
arrives late cannot overwrite a newer observation. Failed reconciliation returns
an error for RevenueCat's retry; it never marks an unapplied event processed.

Account deletion cascades entitlement and quota metadata. Payment cancellation
and store subscription management remain separate store operations; deleting a
Recall account does not itself cancel an App Store or Play Store subscription.
RevenueCat/store product, entitlement, offering, merchant and webhook setup are
external deployment requirements. No live billing or provider calls are used by
these tests.

References: [RevenueCat customer API](https://www.revenuecat.com/docs/api-v1/customers),
[customer info](https://www.revenuecat.com/docs/api-v1/customer-info-model),
[webhook authentication](https://www.revenuecat.com/docs/integrations/webhooks),
[transfer event fields](https://www.revenuecat.com/docs/integrations/webhooks/event-types-and-fields).

## Full backend verification commands

- `supabase/tests/run_local.sh`: 89 PostgreSQL security/workflow assertions,
  including separate-session CAS and competing-publication races.
- `node --test supabase/tests/edge_functions.test.mjs supabase/tests/billing_functions.test.mjs`:
  29 pure mock tests for consent, authentication, quota, strict/verbatim AI
  validation, account deletion identity, trusted billing, transfers, sandbox,
  event dedupe and refresh ownership. No external provider or Auth calls occur.

The Node tests exercise the actual dependency-injected handler modules. With
`supabase/tests/transcription_functions.test.mjs` added, all 47 Edge mock tests pass.
See [recording transcription](TRANSCRIPTION.md) for its consent and multipart contract.

Deno 2.9.6 type-checking passes all five actual Edge entrypoints, resolving the
real Supabase JavaScript SDK 2.118.0 and dependencies. No provider or Auth request
is executed by this check. Hosted Supabase invocation, email, real purchase/restore,
real credentials, provider output quality and store review still require
deployment verification.
