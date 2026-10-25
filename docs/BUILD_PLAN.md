# Recall 0.3 build plan

Updated 25 October 2026. Package **0.3.0+3** uses Firebase Auth, server-managed Firestore, Cloud Functions and Hosting in project `recall-f1d1e`. The code port, infrastructure, live deployment and store release have separate acceptance evidence.

## Product and trust rules

Recall preserves one current plan while client conversations change the work. Original text and recollection stay distinct. Proposals contain immutable versions, and every required person must confirm every changed item before that version replaces the current plan. Link possession has unverified identity. Corrections and declines close the proposal; stale proposals cannot publish. Delivery and payment remain separate states.

Source text supports Unicode and an independent language label. The interface is English, Spanish and French; the editor supports USD, EUR, GBP, CAD and AUD as integer minor units. Additional RTL/currency conventions and live multilingual AI quality still need evaluation.

## Implemented layers

| Layer | Firebase 0.3 implementation | Remaining acceptance |
| --- | --- | --- |
| Accounts | Firebase Auth, verified-email API guard, token revocation checks, recovery/deletion, isolated account workspaces | Hosted signup/email/recovery and physical account transitions |
| Agreements | Firestore transactions, canonical RPC snapshots, CAS, immutable content hashes and idempotent requests | Final budget regressions and controlled live flow |
| Review links | Scoped hash-only capabilities, expiry/revocation, exact-version responses, minimal receipt replay | Live/browser scope, stale/revocation and replay checks |
| Sources | Written imports, Android plain-text sharing, private recording/index/export/removal | Physical microphone/share/lifecycle flows; iOS Share extension remains absent |
| AI | Explicit consent, exact-quote drafts, reviewed machine transcripts, atomic quotas | Server secret setup and representative live quality checks |
| Billing | Native SDK, account guards, real offerings, trusted server reconciliation | Store keys/SKUs and actual sandbox purchase/restore/expiry checks |
| Reminders | Default-off local permission, IANA zones, generic notifications and cancellation | Actual delivery, reboot, time-zone changes and battery restrictions |
| Storage/design | Bounded backups/recovery, private audio ownership, original brand, light/dark, EN/ES/FR | Native accessibility, wording and store assets |

Free: 3 cloud projects and 5 AI requests/day. Verified Pro: 100 projects and 20 AI requests/day. The service-wide AI budget is 100 combined requests per UTC day. Current development bounds are 6 MiB across the account and a 5 MiB reserved-charge limit per project. Admission reserves review headroom, but a large partial confirmation can still stop safely at a capacity limit until the owner frees space. Fresh server entitlements remain authoritative; a client purchase result cannot grant Pro.

## Completed evidence

- Flutter: the final 157 tests passed and analysis reported zero issues.
- Backend: build and 70 tests passed with Firebase Admin 14.5 / Functions 7.4. The final workspace-budget regressions passed; production dependency audit reported zero vulnerabilities.
- Web: the publish build passed in 32.1s with a successful Wasm dry run. The 82-file Hosting release is live; subsequent loader/PWA-icon polish leaves compiled Dart unchanged. Live home/sign-in rendering was checked.
- Firebase: selected account/project ownership and existing Blaze billing verified; email/password Auth, three app registrations, default Firestore and dedicated keyless runtime IAM configured. Deny-all client rules deployed, read back exactly and checked with an anonymous 403 response.
- Source: initial snapshot `e6f5c30` uploaded and remote commit matched; use the selected repository history to identify later release commits.

## Next actions

1. Retain the deployed `recallApi` and Hosting release evidence. Final live verification passed 18/18 checks at the direct function URL and 18/18 through `/api`; all synthetic fixture Auth/project/link records were cleaned up. Minimal hashed deletion fences intentionally remain.
2. Complete the native candidates and identify the exact installed version on controlled devices. Android is retrying after the earlier disk-space failure; iOS dependency prefetch is in progress. No completed 0.3 native artifact is verified yet. Last verified Samsung installation remains 0.1; the latest ADB listing has no device.
3. Test real email verification/recovery delivery separately. API fixtures were marked verified by Admin SDK; no inbox flow was claimed.
4. Configure optional providers and store products, then verify paid/provider features separately. Complete privacy/support/deletion resources, signing, accessibility and reviewer assets before any store submission.

The original application/source and its data remain separate and preserved. Earlier backend references are archived in `legacy/supabase` and `legacy/service`; active cloud code is `functions/`. Historical 0.2 builds/tests do not prove Firebase 0.3 behavior; the earlier generated native outputs were removed for disk space. See [release acceptance](RELEASE.md), [full status](FULL_VERSION_STATUS.md) and [Firebase deployment](FIREBASE_DEPLOYMENT.md).
