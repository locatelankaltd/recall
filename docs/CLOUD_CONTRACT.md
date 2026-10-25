# Recall Firebase backend contract

The active account backend is `functions/`: one Node 22 Firebase Functions v2
HTTP function, `recallApi`, in `europe-west1`. Firebase Admin Auth validates users;
Firestore transactions own agreement state, review responses, limits and quotas.
The former `supabase/` implementation is retained as a reference and is not an
active runtime dependency. Deployment and live integration results are recorded
separately from implementation/emulator evidence.

## HTTP and authentication

Base URLs:

- Web Hosting: `https://recall-f1d1e.web.app/api`.
- Native: `https://europe-west1-recall-f1d1e.cloudfunctions.net/recallApi`.
- Local tests use isolated demo-project emulators and never those live URLs.

`POST /rpc` accepts `{name:"recall_list_projects",params:{...}}` and returns
`{data:<canonical RPC result>}`. The router normalizes an optional `/api` prefix.
Named routes accept their existing raw JSON or multipart payload and return raw
JSON: `/analyze-source`, `/transcribe-recording`, `/refresh-entitlement`,
`/account-delete` and `/billing-webhook`.

Errors are flat `{message:string,code:string}`: authentication `28000`/401,
forbidden `42501`/403, unavailable record `P0002`/404, invalid input `22023`/400,
stale/conflicting state `40001`/409, and allowance `54000`/429. Size/type errors
can use 413/415. Unknown errors expose only a safe unavailable message.

Private operations require `Authorization: Bearer <Firebase ID token>`, validated
with revocation checks, and `email_verified:true`. Domain participants remain
`you` and `client`; Firebase UID ownership is separate. The token's UID is the
only owner identity accepted. `recall_review_link` and `recall_respond_review` are
public capability operations: they omit Authorization and never inherit or look
up a private session. All Firestore client reads/writes are denied by rules;
clients use this API. The Admin SDK authorization checks are mandatory because
server credentials bypass client rules.

Account deletion permits an unverified owner to remove their own account, but
requires `auth_time` within five minutes. Reauthentication and a refreshed ID token
precede the request. The request body cannot select a different user.

## Canonical projects and transitions

JSON uses the existing Dart model shape: `id`, `title`, `clientName`, `category`,
`participants`, `currentRevision`, `proposals`, `archivedRevisions`, `history`,
`itemStatuses`, `isDemo:false`. Item/revision IDs are text. Dates are date-only
`YYYY-MM-DDT00:00:00.000`; money is a nonnegative safe integer in minor units with
a three-letter uppercase currency. Source language is independent of UI language.

| RPC | Parameters | Result |
| --- | --- | --- |
| `recall_list_projects` | none | `[{project,version}]` |
| `recall_create_project` | `p_title,p_client_name,p_category,p_request_id` | `{project,version}` |
| `recall_mutate_project` | `p_project_id,p_expected_version,p_action,p_payload,p_request_id` | `{project,version}` |
| `recall_entitlement` | none | verified limits/entitlement described below |

Mutation payloads:

| Action | Payload |
| --- | --- |
| `add_item` | `{item:PlanItemJSON}` |
| `propose_change` | `{items:[PlanItemJSON],evidence:[EvidenceJSON],authorId:"you"}` |
| `confirm` | `{revisionId,actorId:"you"}` |
| `correction` | `{revisionId,actorId:"you",note}` |
| `set_status` | `{itemId,status,actorId:"you"}` |
| `delete` | `{}`; result `{project:null,version,deleted:true,projectId}` |

The owner transaction checks the envelope version and updates that project
atomically. Request IDs are 8–128 letters/numbers/dashes/underscores. Identical
retries return the exact saved response; reusing an ID for another payload fails.
Large responses are stored in private replay chunks so they do not exceed a
Firestore document's size. A project including its reserved publication/closure
headroom is bounded to 5 MiB. A shared
6 MiB workspace budget is tracked on the owner and updated transactionally by
creation, mutation, recipient response and deletion. It charges canonical project
responses plus a publication copy and 32 KiB of response/correction headroom for
each open proposal. This reserves room for recipient publication and keeps the
complete workspace below the client's 8 MiB response limit. New content that
exceeds the budget fails before committing; exporting/deleting a project releases
space. List reads check aggregate metadata before loading projects and bound
serialized output incrementally. Revision payloads remain below Firestore's
document limit. No partial snapshot silently replaces an account workspace.

Revision payloads are separate immutable server records with integrity hashes;
only review state changes. Shared proposals require `you` and `client`, with the
author's review recorded initially. An owner cannot confirm as the client. A
proposal never changes the current plan until every required actor confirms every
changed item. Corrections/declines close the proposal and clear acceptance.
Competing publication changes the current base, making other proposals stale.
Progress is separate from agreement/payment; changed items reset progress on
publication. Private baselines may add items; shared plans require proposals.

Inputs allow up to 100 plan items and 20 sources. Source text is bounded to 30,000
characters, with original-text/recollection kinds preserved. Non-null local
`attachmentPath` is rejected and cloud evidence emits it as null. Audio is not
uploaded as part of a proposal. Original source wording is never automatically
translated or upgraded into verified identity/agreement.

## Scoped recipient capabilities

`recall_create_review_link(p_project_id,p_revision_id,p_participant_id,
p_item_ids?,p_ttl_seconds?)` requires the owner and an open/current-base proposal.
Only `client` is eligible. Item IDs are a unique nonempty subset of changed items;
null selects all. TTL is 60–604800 seconds. Result:
`{id,token,expires,revisionId,participantId,itemIds,identity}`.

Tokens have 256 random bits. Only SHA-256 token hashes are stored; raw tokens are
shown once and never appear in list results, URLs sent to the API, logs or
analytics. Sharing uses the web URL fragment. Recreating a link mints a separate
revocable capability, without paid retries.

`recall_list_review_links(p_project_id)` returns owner-only link metadata:
`[{id,revisionId,participantId,itemIds,expires,revoked,responded}]`.
`recall_revoke_review_link(p_link_id)` returns `{id,revoked:true}`.

`recall_review_link(p_token)` returns project/client display names, immutable
revision/version/base/current IDs, state, selected
`changes:[{itemId,previous:PlanItem|null,proposed:PlanItem|null}]`, `evidence`,
`evidenceOmitted`, `canRespond`, `response` and the explicit identity label.
It omits owner UID, full project/history, other links and unrelated items. Sources
are exposed only when the link covers every changed item; partial links omit
unscoped revision evidence. Expired/revoked tokens cannot reopen context.

`recall_respond_review(p_token,p_action,p_note,p_request_id)` accepts
`confirm`, `correction` or `decline`, with a nonempty correction note and a
2,000-character note limit. The receipt is
`{receiptId,revisionId,version,action,status,identity}`. An exact committed retry
returns its minimal receipt after later expiry/revocation, but cannot change it
or retrieve closed context. Uncommitted expired/revoked links cannot respond.
Every response remains **link-holder response; identity not verified**. The API
sends no invitations and makes no signature, payment or legal-enforceability claim.

## Limits, billing and deletion

Free accounts support 3 cloud projects and up to 5 combined AI requests per UTC
day. Fresh verified Pro supports 100 projects and up to 20 AI requests. Project
creation updates an owner counter in the same transaction, preventing concurrent
cap bypass. Downgrades preserve readable projects while blocking excess creation.
The administrator AI cap can lower allowances; a shared hard service budget of
100 attempts/day commits atomically with the per-user reservation. Failed provider
attempts retain their reservation. Deleting an account cannot release spent
aggregate budget or permit account-fanout bypass.

`recall_entitlement()` returns
`{entitlement:"pro",active,expiresAt,verifiedAt,environment,status,projectLimit,
analysisDailyLimit}`. Expiry is checked at read time; verification older than 24
hours is inactive/stale. Cached sandbox grants remain inactive unless the current
server `RECALL_ALLOW_SANDBOX_BILLING=1` explicitly permits them.

`/refresh-entitlement` validates the owner and fetches only that Firebase UID from
RevenueCat. `/billing-webhook` requires the configured long full Authorization
secret. Webhook paid flags are ignored; fresh RevenueCat REST state derives `pro`,
expiry/grace/refund/environment. Firebase UIDs are case-sensitive, validated and
URL-encoded; they are not restricted to UUIDs. Existing Firebase users alone
receive updates. Network/permission lookup errors fail for retry instead of
silently discarding state. Transfers reconcile source and destination identities;
event hashes deduplicate successful writes and older observations cannot regress
newer state. SDK purchase success alone never unlocks service.

Project deletion closes public access and scrubs replay/source/link records.
Account deletion sets an immediate durable deletion fence keyed by a UID hash,
containing only its deletion timestamp. It removes Firestore
projects, links, journals, entitlements and per-user usage, then removes Auth.
Failed cleanup retains a retryable barrier. The minimal fence remains after
Auth deletion so already-verified in-flight requests cannot recreate projects,
quotas or billing status; no email/source text is retained there. One account
cannot delete another.
Store subscriptions must still be managed/cancelled in the store.

## Optional providers and deployment

AI/transcription and billing are disabled by default. Public server flags
`RECALL_AI_ENABLED=1` and `RECALL_BILLING_ENABLED=1` must be set at deployment to
bind their Secret Manager values. Enabling AI binds `OPENAI_API_KEY`; enabling
billing binds `REVENUECAT_SECRET_API_KEY` and `REVENUECAT_WEBHOOK_AUTH`.
Create/configure secrets through the approved secure workflow and redeploy after
changing bindings. No secret belongs in source, public client defines or logs.
Initial deployment with both flags zero requires no provider secrets. The
runtime uses `recall-api@recall-f1d1e.iam.gserviceaccount.com` with Firestore/Auth
access; enabling a provider later also requires read access to its specific
Secret Manager values, without placing service-account keys in the app.
`APP_ORIGIN` restricts browser CORS; native clients omit Origin.

`/analyze-source` preserves the consent/strict JSON/verbatim draft contract.
`/transcribe-recording` preserves strict multipart audio limits and machine
provenance; see [transcription](TRANSCRIPTION.md). Provider destinations are fixed,
redirects and automatic paid retries are disabled, output is bounded, and neither
provider route mutates an agreement.

The function uses minimum zero/maximum two instances, concurrency one and a
512 MiB memory limit to bound the initial deployment. Cloud deployment is a
separate root-controlled action after tests. Run `npm --prefix functions run
build` and `npm --prefix functions run test:emulator`. The runner uses Node 22,
Auth/Firestore emulators on isolated ports and `demo-recall-backend`; it never
connects to the production project. Client-rule tests, real emulator transactions,
HTTP token checks and mocked provider checks cover different boundaries.

After a Functions deployment, verify public invocation for the intended
`recallApi` service. The deployed service uses the standard unconditional
`allUsers` / `roles/run.invoker` binding configured by Firebase. Recall validates
Firebase ID tokens and verified email for private operations; public reviews
validate only their scoped capability. Verify missing-token private requests,
unknown review capabilities, controlled owner/recipient flows and fixture cleanup
against the actual deployed endpoint.
