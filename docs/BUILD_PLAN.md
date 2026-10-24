# Recall 0.2 build plan and current stage

Deployment update: 25 October 2026; implementation/build evidence below is from 24 October 2026. The implementation has moved from a separate local preview/service to a Flutter app wired to Supabase Auth and atomic RPCs, with optional authenticated AI, actual native billing integration and local reminders. The hosted Recall environment and merchant/provider setup remain unprovisioned; implementation, deployment and publication are separate stages.

## Product direction

Recall helps independent professionals and small client teams track one current scope, deadline and fee while requests change across messages and conversations. It preserves the request's source, shows the old and proposed values, and keeps changes proposed until the required people review the same immutable version. Original text and recollection remain distinct; delivery progress, agreement and payment are different states.

Source text supports Unicode and an independent language label. Interface copy is English, Spanish and French. The current editor supports USD, EUR, GBP, CAD and AUD, stored as integer minor units. Full RTL, additional currency conventions and multilingual transcription/analysis quality require deliberate evaluation; broad language availability is not proof of semantic accuracy.

## Implemented layers

| Layer | 0.2 behavior | Remaining verification |
| --- | --- | --- |
| Auth/workspaces | Supabase Auth, verified account workspace, session-bound requests, recovery/deletion; private device workspace stays separate | Provision selected environment; real controlled Auth/email checks |
| Authoritative agreements | RPC-only canonical snapshots, RLS/private tables, immutable revisions, CAS, idempotency, correction/stale handling and exact-version publication | Connected device/browser concurrency and outage checks |
| Recipient review | Scoped expiring/revocable links, selected old/new items, explicit unverified bearer identity; committed receipt replay after expiry without reopening context | Hosted public review browser flow and correct application URL |
| Source capture | Typing/paste, bounded UTF-8 import, Android plain-text share receiver, private recording/index/export/removal | Physical source-app, microphone, file/share and lifecycle checks; iOS Share extension remains absent |
| Optional AI | Explicit consent, source-analysis drafts with exact quote checks, whole-recording machine transcription, server credentials and atomic quotas | Secure credential setup and representative live quality evaluation |
| Billing/limits | Native store SDK, actual localized offerings, purchase/restore, account guards; server RevenueCat reconciliation; Free 3 projects/5 AI, Pro 100/20 | Merchant/store keys, SKUs/offerings, trusted end-to-end transaction and expiry/restore checks |
| Reminders | Default-off Android/iOS permission flow, IANA-zone planning, generic notifications, up to 32 unfinished-item reminders, workspace/session cancellation | Real notification delivery, timezone change, reboot and battery restrictions |
| Local storage/design | Secure-plugin project text, recovery/export/import, private audio ownership checks, light/dark, original brand/icons, EN/ES/FR | Native accessibility/language review and store asset/publication checks |

AI requests share a 100-request UTC-day service budget. Account plan limits require fresh server-verified entitlements, and administrator caps may lower allowances. A downgrade preserves readable projects but blocks creation beyond the current cap. Reminder scheduling does not imply an agreed delivery time.

## Trust rules retained

1. A private baseline and a client name do not establish anyone else's acceptance.
2. A proposal cannot silently replace the current plan. Every required participant must confirm every changed item of that exact immutable revision; stale proposals cannot publish.
3. Link possession is explicitly unverified identity. Opening a page is not confirmation. Scoped links cannot expose unrelated items or unscoped evidence.
4. Corrections/declines close the revision and clear its prior confirmations. Identical committed response retries return their receipt even after later link expiry/revocation; source access remains closed.
5. Cloud state comes only from server RPC snapshots. Editable JSON backups cannot forge authenticated account history; local projects are not silently uploaded.
6. AI produces drafts and machine transcripts for human review. It cannot publish, identify a speaker or confirm an agreement. Device paths never become cloud evidence.
7. SDK purchase success alone never grants paid access. Server verification, expiry/freshness, plan limits and service budgets remain authoritative.
8. Reminders are opt-in/local, contain generic text, and are rebuilt or cancelled when the active workspace changes.

## Current evidence

- Full Flutter suite: **142/142 pass**, including **21 billing** and **11 reminder** tests; full Dart analysis has zero issues. Root log: `/private/tmp/recall-v02-flutter-tests-final.log`.
- PostgreSQL: **89 passing security/workflow assertions**, including real separate-session races for CAS, competing publication, project caps and combined quota reservation.
- Edge handlers: **47 mock tests pass**. Deno 2.9.6 checks all **five** actual entrypoints with real Supabase SDK imports. Tests make no live paid/provider/store calls.
- Legacy Python/SQLite foundation: **29 tests**, retained as a separate development reference rather than the primary cloud gateway.
- 0.2 web release passed in 31.2s, including its Wasm dry run; 10 browser captures reported `errors: []`. Android debug APK and release AAB builds passed; APK signature verifies, while the AAB is **unsigned**. iOS simulator build/signature checks and a fresh isolated iPhone 17 / iOS 26.5 first launch passed. See exact bytes/hashes and scope in [release acceptance](RELEASE.md#verified-02-artifacts).
- Samsung's last installation performed by this work remains **0.1**; no 0.2 physical-device installation is claimed. The iOS check was first-launch rendering, not microphone/reminder/store feature QA. The owned temporary simulator was shut down/deleted without touching another simulator.

## Selected deployment direction

The implemented Supabase backend is unprovisioned. Firebase Hosting and a Firebase-only backend are selected; the backend port remains to be implemented. No cloud deployment has occurred. The existing Supabase deployment path is retained as implementation reference: apply migrations 001–005, deploy the five Edge Functions, configure public URLs/Auth redirects, and verify controlled account and recipient flows. The selected Firebase-only direction requires porting and retesting the equivalent authorization, immutable review, quota and trusted-billing behavior. See [full status](FULL_VERSION_STATUS.md) and [cloud contract](CLOUD_CONTRACT.md).

Complete secure OpenAI provisioning and RevenueCat/store configuration without putting server secrets in Flutter. Then evaluate source/transcription accuracy and real purchase/restore/expiry/transfer behavior using a deliberate test choice. Keep free/manual workflows usable when optional services are unavailable.

## Next stage: device and publication review

Verify the 0.2 artifact on physical Android/iOS: first launch, restart/recovery, text sharing, recording permission/export/removal, app lifecycle, notification opt-in/delivery, account switching and recipient review. Confirm final package identities/signing, accessibility/large text, privacy/deletion/support resources, subscription disclosures and store reviewer access against that exact artifact.

The original application and its data remain preserved. This rebuild uses separate identities; no migration of existing users, production data or signing identities is claimed. Source target [locatelankaltd/recall](https://github.com/locatelankaltd/recall.git) is connected as `origin`, and the initial local snapshot is being prepared. Remote upload is unverified because the authenticated GitHub account has read-only access; no commit/push success is claimed. Follow [release acceptance](RELEASE.md) before publication.
