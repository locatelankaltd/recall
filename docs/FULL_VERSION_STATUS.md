# Recall 0.2 implementation and deployment status

Deployment update: 2026-10-25; build/test evidence: 2026-10-24. This describes the full-version implementation target and
verified artifacts. It is not a claim that a public cloud service or store release
is live. Package version is **0.2.0+2**. The full Flutter suite and analysis pass;
web/native build and installed-version results are tracked separately below.

## Implemented

| Area | Concrete behavior |
| --- | --- |
| Accounts | Supabase Auth integration, account-scoped projects, session guards, recovery and account deletion |
| Agreements | Canonical server snapshots, immutable proposals, CAS, replay-safe project writes, all-participant/item acceptance, stale/correction handling |
| Recipient review | Expiring/revocable scoped hash-only bearer links; selected old/new items; explicit unverified link-holder identity |
| Device sources | Written sources and local/private recording attachments; device file paths are excluded from cloud evidence |
| Optional AI | Explicit consent; source-analysis drafts with exact quotes; whole-recording machine transcription requiring review; shared per-user daily quota |
| Subscriptions | Real native store offerings/prices, purchase/restore, account-bound SDK operations, trusted server entitlements; enforced Free 3 projects / 5 daily AI requests and Pro 100 projects / 20 daily AI requests |
| Local reminders | Default off; Android/iOS notification permission; IANA device time zone; up to 32 generic reminders for unfinished current-plan items; workspace/account cancellation |
| Interface | English, Spanish and French UI text, store billing-period labels, source language/provenance kept separately from interface language |

The shared service AI budget is 100 combined requests per UTC day; account
fanout cannot exceed it, and administrator caps may lower plan allowances.
Committed review responses can retrieve their minimal receipt after later link
expiry/revocation without reopening source access.

Manual project/source workflows remain available when cloud, AI or store
configuration is missing. There is no fabricated purchase plan, successful AI
result, recipient identity verification or provider acceptance.

## Verification completed

| Check | Result |
| --- | --- |
| Isolated PostgreSQL | 89 security/workflow assertions pass, including separate-session CAS, publication, plan-cap and combined-budget races |
| Edge handler mocks | 47 pass: 29 account/analysis/billing tests plus 18 transcription tests; no external Auth/provider calls |
| Full Flutter suite | **142/142 pass**, including 21 billing, 11 reminder and four AI-consent widget tests; no store transaction |
| Full Dart analysis | Zero issues in `lib` and `test` |
| Deno 2.9.6 | All five actual Edge entrypoints type-check with real Supabase JavaScript SDK 2.118.0 import resolution |
| 0.2 web release | Passed in 31.2s; Wasm dry run passed; 10 browser captures reported `errors: []` |
| 0.2 Android debug APK | Passed; 0.2.0+2, package `com.recharge.recall_next`, minimum 26/target 36; debug signature verified |
| 0.2 Android release AAB | R8/bundle and ZIP CRC checks passed; unsigned and not upload-ready |
| 0.2 iOS simulator | Build/deep-strict signature verification passed; fresh iPhone 17 / iOS 26.5 first launch rendered without error or permission prompt |
| Samsung installed version | Last installation by this work was 0.1; no device in the final ADB listing; no 0.2 physical-device install claim |
| Legacy Python foundation | 29 tests; separate local service reference, not the primary cloud gateway |

The full Flutter run is recorded in `/private/tmp/recall-v02-flutter-tests-final.log`.
Exact build sizes/hashes are recorded in [release acceptance](RELEASE.md#verified-02-artifacts).
The iOS smoke scope was first-launch rendering only; its isolated simulator was
shut down and deleted. Physical-device 0.2 feature flows and hosted integration
remain pending in this snapshot. Local SQL tests use a minimal Auth
harness; mocks and Deno checking do not prove deployed authentication, emails,
purchase/restore, transcription quality or provider account access.

Commands already used:

```sh
dart analyze lib test
flutter test
supabase/tests/run_local.sh
node --test supabase/tests/edge_functions.test.mjs supabase/tests/billing_functions.test.mjs supabase/tests/transcription_functions.test.mjs
npx --yes deno check supabase/functions/account-delete/index.ts supabase/functions/analyze-source/index.ts supabase/functions/billing-webhook/index.ts supabase/functions/refresh-entitlement/index.ts supabase/functions/transcribe-recording/index.ts
```

## External state

The implemented Supabase backend remains unprovisioned. Firebase Hosting is
selected for the web app; a Firebase-only backend is selected and its port is pending.
No cloud deployment has occurred. The implemented contracts and local test/build
results are unchanged.

AI provider credentials, RevenueCat/store keys, products/SKUs,
offering/entitlement mapping and final store identities remain unset. Public SDK
keys belong in native build configuration; provider and service-role secrets
belong only on the server. No paid model or actual store transaction has been
used for QA.

Source target [locatelankaltd/recall](https://github.com/locatelankaltd/recall.git)
is connected as `origin`. The initial local snapshot is being prepared. Remote
upload is unverified because the authenticated GitHub account has read-only
access; no successful commit/push is claimed. Private `artifacts/qa` evidence is
Git-ignored.

## Reviewable deployment sequence

1. **Complete the Firebase-only backend port.** Firebase Hosting and a
   Firebase-only backend are selected. The existing Supabase implementation is
   unprovisioned and retained as a reference. Its existing migration sequence is `202610240001_recall_cloud.sql`,
   `202610240002_analysis_quota.sql`, `202610240003_verified_billing.sql`,
   `202610240004_plan_limits.sql` and `202610240005_review_receipt_replay.sql`.
   Inspect RLS/grants and advisories before connecting a client build. The
   Firebase backend requires equivalent authorization, transaction and isolation
   tests before this reference deployment sequence is replaced.
2. **Configure Auth and public client values.** Build with `SUPABASE_URL`, a
   publishable/anon key in `SUPABASE_ANON_KEY`, recipient-facing `PUBLIC_APP_URL`,
   and the intended `AUTH_REDIRECT_URL`. Set Supabase's site URL to the actual web deployment and
   allow that exact callback. The native callback is
   `io.recall.app://login-callback`; its Android intent filter and iOS URL scheme are present. Verify
   both callbacks on the candidate and confirm the final bundle/application identity.
   Local config currently uses `http://localhost:3000` and that native callback.
3. **Deploy the actual functions.** Deploy `account-delete`, `analyze-source`,
   `transcribe-recording`, `billing-webhook` and `refresh-entitlement`, including
   their shared modules. Their gateway JWT checks are disabled because each
   verifies Auth with `auth.getUser` or verifies the RevenueCat webhook secret.
   Set the final `APP_ORIGIN`. Keep optional provider features unavailable until
   their secure configuration and controlled verification are complete.
4. **Complete secure provider/store configuration.** Finish the existing secure
   key workflow without placing a secret in chat or Flutter configuration.
   Configure server AI enablement/model/quota and the RevenueCat server key plus
   matching long webhook Authorization value. Configure native public
   `REVENUECAT_ANDROID_KEY` / `REVENUECAT_IOS_KEY`, real store products, offerings
   and the `pro` entitlement. Production keeps sandbox billing access disabled.
5. **Verify the connected agreement flow.** Use controlled accounts to exercise
   `recall_list_projects`, `recall_create_project`, `recall_mutate_project`,
   `recall_create_review_link`, `recall_list_review_links`,
   `recall_revoke_review_link`, `recall_review_link` and
   `recall_respond_review`. Confirm outsider isolation, exact scope, stale/conflict
   handling, recipient identity wording and publication only after all required
   item confirmations. Test recovery/deletion on controlled records.
6. **Verify optional features on the release build.** Check recording permission,
   local retention/removal, explicit transcription consent and default-off reminder
   permission/delivery. Confirm IANA-zone timing, generic notification text and
   cancellation when the active workspace changes. Review transcript
   and analysis quality in intended source languages. Test purchase, cancellation,
   pending approval, restore, account switching, safe store management links and
   `recall_entitlement` against trusted server reconciliation. Verify Free/Pro
   project and AI caps, expiry/downgrade behavior and the shared daily budget. Live paid checks
   require a deliberate test choice; none have occurred so far.
7. **Review publication artifacts.** Confirm final package identities, signing,
   build/version, store product mapping, privacy/support links, auth redirects,
   permissions and subscription disclosures. Review the exact deployed version
   and device/store evidence before submitting or publishing it.

Detailed behavior: [cloud contract](CLOUD_CONTRACT.md),
[recording transcription](TRANSCRIPTION.md), [architecture decision](ADR-001-cloud.md).
Primary references: [Supabase functions](https://supabase.com/docs/guides/database/functions),
[RLS](https://supabase.com/docs/guides/database/postgres/row-level-security),
[RevenueCat purchases](https://www.revenuecat.com/docs/getting-started/making-purchases),
[customer identity](https://www.revenuecat.com/docs/customers/identifying-customers),
[webhooks](https://www.revenuecat.com/docs/integrations/webhooks),
[OpenAI structured outputs](https://developers.openai.com/api/docs/guides/structured-outputs),
[speech to text](https://developers.openai.com/api/docs/guides/speech-to-text).
