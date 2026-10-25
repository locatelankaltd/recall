# ADR-002: Firebase for the Recall cloud service

**Status:** Accepted; implementation and deployment are tracked separately.
**Date:** 2026-10-25
**Decider:** Project owner

## Context

Recall needs authenticated private workspaces, immutable change proposals,
version-specific client review, optional source analysis, and verified native
subscription entitlements. The first cloud implementation used Supabase, but it
was never deployed and has no production users or records to migrate.

The project owner selected one Firebase project for authentication, data, server
functions, and web hosting. The source repository is
[locatelankaltd/recall](https://github.com/locatelankaltd/recall).

## Decision

- Use Firebase Authentication for accounts and hosted email verification/reset.
- Use Firestore transactions for canonical project snapshots, version checks,
  idempotency, review receipts, quotas, and verified entitlements.
- Route owner mutations and public review operations through an authenticated
  Cloud Functions HTTP service. Public review endpoints authenticate the scoped
  bearer link; they must not inherit the owner's session.
- Deny direct client access to server-managed Firestore collections.
- Serve the Flutter web build through Firebase Hosting. Keep provider secrets in
  server configuration, and public Firebase app configuration in client builds.
- Preserve the private device workflow and the separation between agreement,
  delivery progress, original evidence, and personal recollection.

The deployment target is `recall-f1d1e`, with the public web address
`https://recall-f1d1e.web.app`. Project creation and public app registration do not
establish that the server functions or business workflows are deployed.

## Trade-offs

One provider simplifies account administration and web hosting. Firestore uses a
document model, so the existing SQL procedures must be ported and tested for
concurrent writes, bounded documents, exact review scope, and receipt replay.
The previous SQL tests remain historical evidence for that implementation; they
do not prove the Firebase port.

Cloud Functions deployment requires the Blaze billing plan. Local emulator tests
and frontend preparation can proceed before enabling billing. Enabling billing,
provider secrets, and store setup are separate deployment steps.

## Verification and rollout

1. Preserve the existing source snapshot in Git.
2. Port the cloud interfaces without changing the local agreement rules.
3. Test Firestore rules, transaction races, authentication boundaries, quotas,
   client review scope, and provider failure handling using emulators and mocks.
4. Build the web and native candidates with the correct platform Firebase app IDs.
5. Deploy configured services and verify controlled account and recipient flows.
6. Record the actual deployed commit and build, rather than inferring completion
   from project creation or a successful compilation.

References: [Firebase functions deployment](https://firebase.google.com/docs/functions/get-started),
[Firestore transactions](https://firebase.google.com/docs/firestore/manage-data/transactions),
[Firestore security](https://firebase.google.com/docs/firestore/security/overview).
