# ADR-001: Authoritative cloud agreements and verified subscriptions

**Status:** Superseded by [ADR-002: Firebase](ADR-002-firebase.md). The Supabase
implementation is retained under `legacy/supabase` for historical reference.

**Date:** 2026-10-24

**Deciders:** Nanthan (deployment/account owner), Recall implementation team

## Context

Recall keeps a current plan, immutable proposed changes, original sources and
responses across languages. The app must not invent client acceptance, publish a
stale proposal, expose another owner's records, upload device recording paths, or
unlock a subscription from an unverified client result. The existing Flutter
models and Python service provide useful invariants, but a device snapshot or
single local owner token cannot establish a globally accessible account service.

## Decision

Use Supabase Auth for accounts and PostgreSQL atomic RPCs for authoritative
project state. Keep tables in an unexposed private schema with RLS and no client
write grants. Public functions authenticate the owner, serialize writes with row
locks, compare project versions and return the existing Dart `Project` JSON.
Store domain participant IDs `you`/`client` separately from the Auth owner UUID.

Keep revision content immutable. Review links are scoped to an exact revision and
selected changed items, use 256 random bits, and store only token hashes. A link
holder's identity remains unverified. Publish a proposal only after every required
participant has confirmed every changed item; corrections close proposals, and a
new current plan makes competing proposals stale.

Use RevenueCat's native store SDK for real offerings, purchase and restore. Grant
server `pro` status only after a trusted server read of RevenueCat's current
subscriber state. Authenticate webhooks, reconcile transfer sources/destinations,
deduplicate events, reject older observations and deny sandbox access by default.
Enforce actual account plans: Free 3 projects / 5 daily AI requests, verified Pro
100 projects / 20 daily AI requests. Serialize project creation per owner and
reserve per-user AI allowance together with a service-wide 100-request UTC-day
budget. Administrator caps may lower allowances. No SDK result changes a limit.

Optional AI runs through authenticated Edge Functions with explicit consent,
server-only credentials, bounded inputs and a shared daily quota. Analysis returns
verbatim-supported drafts; transcription returns a machine transcript for review.
Neither function writes an agreement. Audio stays private on the device until the
owner explicitly chooses to send a recording for transcription.

## Options Considered

| Option | Complexity | Cost | Scalability | Familiarity |
| --- | --- | --- | --- | --- |
| Supabase Auth + atomic PostgreSQL RPC + RLS | Moderate: SQL transitions and deployment configuration | Current project quote is $0/month; usage and future services remain separate | Database transactions handle competing writes; hosted Auth/API support account access | Existing Dart models and SQL tests retained; hosted operations need verification |
| Keep the Python/SQLite review service | Low for a local preview; high for public multi-user operations | Local execution is inexpensive; public hosting/Auth/operations must be added | Requires a multi-user identity, hosting and concurrency design | Existing service behavior is directly inspectable |
| Sync whole JSON workspaces between devices | Initially low, then high conflict/security complexity | Storage can be small; conflict handling and audit costs move into the app | Whole-snapshot conflicts risk overwriting reviews and provenance | Closest to existing local backup format |
| Trust store SDK or webhook payload paid flags | Low initial wiring | Low initial backend work | Client tampering, event reordering and transfers complicate correctness | SDK display data is convenient but insufficient for server access control |

## Trade-off Analysis

Atomic server transitions make acceptance and publication reviewable in one place,
at the cost of maintaining SQL migrations and RPC contracts. A global project
version rejects conflicting writes; immutable revision IDs preserve exact reviewed
content. Scoped bearer links support lightweight recipient review while retaining
the explicit limitation that possession does not verify identity.

Server billing reconciliation adds an API round trip and external configuration.
It also supports expiry, refunds, restores and transfers without relying on client
assertions. A 24-hour verification freshness window bounds stale cached access;
provider outages preserve the previous record only within its normal constraints.

The local Python service remains a development reference. Local projects and
exports remain separate from accounts and are not silently uploaded. Optional AI
adds provider cost and review work, so manual written-source entry remains usable.
After a downgrade, existing projects remain readable; creation is blocked above
the current cap. AI capacity is an upper allowance subject to provider availability
and the shared service budget, disclosed on the subscription page.

## Consequences

- Owner isolation, CAS, exact-version publication, replay handling and deletion
  are enforced by SQL and covered by executable security/workflow tests.
- Flutter consumes canonical server snapshots; arbitrary JSON imports cannot
  rewrite an account's history or client responses.
- Auth redirects, hosted configuration, actual devices, email and stores need
  deployment checks beyond mocked/local tests.
- Store identities, merchant configuration, credentials and publication stay
  explicit external prerequisites. This ADR does not claim a deployed service.

## Action Items

1. [x] Implement private/RLS schema, immutable transitions, owner/review RPCs and
   cascading account deletion.
2. [x] Implement secure billing reconciliation, authenticated AI functions,
   native store flow and dependency-injected tests.
3. [x] Run isolated PostgreSQL tests, mock Edge tests and real Deno import/type
   checks. Root verification owns the final Flutter/native build results.
4. [ ] Obtain the user's Supabase organization choice, create the Recall project,
   apply migrations and deploy the five Edge Functions.
5. [ ] Complete secure credential provisioning and actual RevenueCat/store product
   setup; configure final web/mobile auth redirects and store identities.
6. [ ] Verify controlled account, recipient review, recording and store flows on
   the deployed version before publication review.

Implementation details: [cloud contract](CLOUD_CONTRACT.md),
[transcription contract](TRANSCRIPTION.md), [delivery status](FULL_VERSION_STATUS.md).

Primary references: [Supabase functions](https://supabase.com/docs/guides/database/functions),
[RLS](https://supabase.com/docs/guides/database/postgres/row-level-security),
[RevenueCat SDK setup](https://www.revenuecat.com/docs/getting-started/configuring-sdk),
[subscriber API](https://www.revenuecat.com/docs/api-v1/customers),
[webhooks](https://www.revenuecat.com/docs/integrations/webhooks),
[OpenAI structured outputs](https://developers.openai.com/api/docs/guides/structured-outputs),
[speech to text](https://developers.openai.com/api/docs/guides/speech-to-text).
