# Recall 0.3 implementation and deployment status

Snapshot: **25 October 2026**, package **0.3.0+3**. Recall's active stack is Firebase Auth, Firestore, Cloud Functions and Hosting, using project **recall-f1d1e**. The web app and core API are live; native and store release acceptance remains incomplete.

## What is implemented

| Area | Concrete behavior |
| --- | --- |
| Accounts | Firebase Auth; verified-email/revocation-aware server checks; isolated sessions/workspaces; recovery and recent-auth account deletion |
| Agreements | Canonical server snapshots; immutable revision hashes; Firestore CAS transactions; retry-safe mutations; correction/stale handling |
| Recipient review | Scoped expiring/revocable hashed links; selected old/new changes; unverified link-holder identity; all-item acceptance and minimal receipt replay |
| Sources | Written text/import/share and local private recordings; local paths never become cloud evidence |
| Optional AI | Consent-led analysis drafts with exact quotes; reviewed machine transcripts; combined atomic quotas |
| Optional subscriptions | Real native offerings/purchase/restore code, account binding and server RevenueCat reconciliation |
| Reminders/design | Default-off local reminders; IANA zones; generic text; original brand/icons; light/dark and EN/ES/FR |

Free limits are 3 projects / 5 daily AI requests; verified Pro supports 100 / 20. The shared service AI budget is 100 requests per UTC day. Current development admission bounds are 6 MiB across the account and 5 MiB per project reserved charge, including review headroom. Large partial confirmations can still return a safe capacity error requiring the owner to free space; project allowances do not promise unlimited content. AI and billing are disabled until their server and store configuration is supplied.

## Verification snapshot

| Gate | Result |
| --- | --- |
| Flutter suite | Final 157/157 pass |
| Dart analysis | Final analysis reports zero issues |
| Backend build/tests | Final Admin 14.5 / Functions 7.4 build and 70 tests pass |
| Production dependency audit | Zero reported vulnerabilities |
| Web release | 32.1s publish build; Wasm dry run passed; static loader/icon polish is separate from compiled Dart |
| Firebase infrastructure | Project owner/Blaze plan verified; Auth, database and three app registrations configured |
| Firestore rules | Deny-all release verified against local source; anonymous client read denied with 403 |
| Runtime IAM | Dedicated keyless service account; datastore.user and firebaseauth.admin; zero user-managed keys |
| Functions / Hosting | API ACTIVE; 82-file Hosting release live; home/sign-in rendering verified |
| Controlled live API test | 18/18 direct + 18/18 Hosting-proxy checks pass; all fixture Auth/data/link cleanup verified |
| Android 0.3 | Retry in progress after the earlier disk-space failure; no completed 0.3 APK verified yet |
| iOS 0.3 | Dependency prefetch in progress; no compile/launch result yet |
| Samsung | Last verified installation is 0.1; latest ADB listing has no device |
| Store-signed distribution/submission | Not performed |

The earlier 0.2 native files were removed as generated build output to recover space. Their hashes and screenshots are historical evidence only. See [release acceptance](RELEASE.md#historical-02-evidence).

## External configuration

The requested project account is `locatelankaltd@gmail.com`. Public Firebase SDK/build configuration is in `config/firebase`; it contains no administrative or provider secrets. Auth's authorized domains include `recall-f1d1e.web.app` and `recall-f1d1e.firebaseapp.com`. Cloud Storage has not been provisioned for recordings; audio stays local.

OpenAI and RevenueCat server secrets, native merchant/store keys, products/SKUs, offerings and entitlements remain unset. No live AI quality check, real store transaction or email delivery test is recorded. Mock/emulator success does not prove any of those integrations.

Initial Git commit [`e6f5c30`](https://github.com/locatelankaltd/recall/commit/e6f5c30c2acc05c9abb0d539f4df75e136565da0) was pushed to the selected public repository, and the remote commit matched. Use the repository history to identify subsequent release commits. Private QA evidence stays Git-ignored. The original app/source is preserved separately; historical backends are archived in `legacy/supabase` and `legacy/service`.

## Remaining delivery sequence

1. Keep the live web/API evidence with the delivered source revision; apply any static Hosting polish to the same reviewed Dart build.
2. Test actual email verification/recovery delivery. Controlled API tests used Admin-marked synthetic verification, not inbox delivery; all fixture data was removed, with minimal hashed deletion fences retained.
3. Complete and verify 0.3 on physical Android/iOS, including recording/share, account switches, large text/accessibility and reminder delivery.
4. Complete provider/store configuration and evaluate explicit-consent AI, real prices, purchase/restore/expiry and trusted entitlements.
5. Confirm final app identities/signing, support/privacy/deletion resources, subscription disclosures and store reviewer access before submission.

Details: [Firebase deployment](FIREBASE_DEPLOYMENT.md), [Firebase architecture](ADR-002-firebase.md), [backend contract](CLOUD_CONTRACT.md), [transcription contract](TRANSCRIPTION.md).
