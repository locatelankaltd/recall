# Recall 0.2

Recall helps independent professionals and small client teams keep one clear plan when conversations change the work. Add the current scope, owner, deadline and fee; preserve the message or your recollection behind a request; compare proposed changes with the current plan; and keep them proposed until the required people review that exact version. Delivery progress stays separate from agreement and payment.

**Version 0.2.0+2 is implemented.** Flutter uses the implemented Supabase Auth/RPC gateway for account projects, recipient review and server verification; that backend remains unprovisioned. Firebase Hosting and a Firebase-only backend are selected; the backend port is not yet complete. No cloud deployment has occurred. Optional AI and real store subscriptions require external configuration. The original app and its data remain separate and preserved. This is a tested development candidate, with hosted integration and publication still to verify.

## Current features

- Private device workspaces plus authenticated account workspaces in the configured build. Account writes return canonical server snapshots; queued work and responses are guarded against account changes.
- Immutable proposals, original-text/recollection provenance, current/proposed comparison, correction/history, and expiring/revocable recipient links scoped to selected changes. A link response explicitly has unverified identity. Publication requires all required participants to confirm every changed item of the same version.
- Text entry, paste, UTF-8 source-file import, Android incoming plain-text sharing, and consent-led microphone recording. Mobile recording files remain app-private; JSON exports exclude audio binaries. Browser recording copies must be saved before leaving the session. iOS incoming Share-extension capture is not implemented.
- Optional consent-gated source analysis and whole-recording transcription through authenticated Edge Functions. Results remain drafts; exact source quotes, uncertainty and machine-transcript provenance require review. No AI result publishes a plan or confirms a person.
- Real native RevenueCat offerings, localized store prices, purchase/restore, safe store-management links and server-verified entitlements. Free accounts support 3 cloud projects and up to 5 combined AI requests/day; verified Pro supports 100 projects and up to 20. AI also has a shared 100-request UTC-day service budget and administrator upper caps. No price or successful payment is invented when configuration is missing.
- Default-off local deadline reminders on Android/iOS. Permission is requested only when enabled. A device IANA time zone plans up to 32 reminders for unfinished current-plan items around 09:00 before a deadline, with a due-day fallback when still ahead. Notifications contain generic text and are cleared/rebuilt across workspace changes.
- Local secure-plugin text storage, bounded export/restore, recovery, recording export/deletion and separate cloud account deletion. Deleting a Recall account does not cancel store subscriptions. Light/dark themes, original brand/icons and English/Spanish/French interface text are included; original source content keeps its own language.

See the [architecture decision](docs/ADR-001-cloud.md), [cloud contract](docs/CLOUD_CONTRACT.md), [transcription contract](docs/TRANSCRIPTION.md) and [full delivery status](docs/FULL_VERSION_STATUS.md).

## Run

Use Flutter with Dart 3.12+; this workspace's inspected SDK reports Flutter 3.44.0. Android development uses API 26+ and iOS development uses iOS 15+. The rebuild lives in `recall_next`, with Android `com.recharge.recall_next` and iOS `com.recharge.recallNext`; permanent store identities/signing still need a deliberate release decision.

The unconfigured build runs the private device workflow:

```sh
flutter pub get
flutter run -d chrome --web-port 8787
```

After provisioning the selected Recall backend, replace these **public configuration placeholders** for a connected native run:

```sh
flutter run -d DEVICE_ID \
  --dart-define=SUPABASE_URL=https://PROJECT_REF.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=PUBLIC_SUPABASE_KEY \
  --dart-define=PUBLIC_APP_URL=https://RECALL_WEB_HOST \
  --dart-define=AUTH_REDIRECT_URL=io.recall.app://login-callback \
  --dart-define=REVENUECAT_ANDROID_KEY=goog_PUBLIC_SDK_KEY \
  --dart-define=REVENUECAT_IOS_KEY=appl_PUBLIC_SDK_KEY
```

For web, use the intended web origin as `AUTH_REDIRECT_URL`, including `http://localhost:8787` during that local run, and register it in Supabase's allowed redirects. `PUBLIC_APP_URL` is the recipient-facing web app URL. The native callback `io.recall.app://login-callback` is registered in Android and iOS. Public RevenueCat keys are optional until real store offerings are configured. The `SUPABASE_ANON_KEY` define accepts a modern publishable key or a legacy anon key. Public review calls use only the `apikey` header and cannot inherit an owner session. Provider and service-role credentials stay on the server and never belong in these defines.

## Verification

| Check | Current evidence |
| --- | --- |
| Full Flutter suite | **142/142 pass**, including 21 billing and 11 reminder tests |
| Full Dart analysis | Zero issues |
| PostgreSQL security/workflows | **89 assertions pass**, including owner/RLS isolation, concurrent CAS/publication/plan caps, AI budgets and receipt replay |
| Edge handlers | **47 mock tests pass**; no Auth/provider calls or store transactions |
| Deno 2.9.6 | All **five Edge entrypoints** type-check with actual Supabase SDK imports |
| 0.2 web release build | Passed in 31.2s; `build/web`; Wasm dry run passed; 10 browser captures with `errors: []` |
| 0.2 Android debug APK | Passed; version 0.2.0+2, debug signature verified; artifact/hash in [release record](docs/RELEASE.md#verified-02-artifacts) |
| 0.2 Android release AAB | R8/bundle and ZIP CRC checks passed; **unsigned**, not upload-ready |
| 0.2 iOS simulator | Build and deep/strict signature verification passed; fresh iPhone 17 / iOS 26.5 first launch rendered cleanly |
| Samsung installed app | Earlier **0.1** development install; 0.2 installation/device QA is pending |
| Live cloud, email, provider accuracy and store purchase/restore | Not run; external setup pending |

The iOS simulator check covered first-launch rendering only, with no notification
permission prompt. Its isolated simulator was shut down and deleted; physical
recording/reminder/billing flows remain unverified. The root Flutter test log is `/private/tmp/recall-v02-flutter-tests-final.log`. Reproduce local verification with:

```sh
dart analyze lib test
flutter test
supabase/tests/run_local.sh
node --test supabase/tests/edge_functions.test.mjs supabase/tests/billing_functions.test.mjs supabase/tests/transcription_functions.test.mjs
npx --yes deno check supabase/functions/account-delete/index.ts supabase/functions/analyze-source/index.ts supabase/functions/billing-webhook/index.ts supabase/functions/refresh-entitlement/index.ts supabase/functions/transcribe-recording/index.ts
```

Native/web build and publication status is tracked in [release acceptance](docs/RELEASE.md). A generated build, installed package, store submission and store approval are separate results.

## Legacy development reference

The Python/SQLite service in [service](service/README.md) is the earlier loopback-only review/AI foundation, with **29 passing foundation tests**. It is retained for reference and does not power the new Supabase account gateway. Run it separately with `python3 service/run.py --port 8765`; its private administrative token must never enter a client build. Run its isolated tests with `python3 -m unittest discover -s service -v`.

The original application and its data remain separate; no existing-user migration is claimed. Source repository target: [locatelankaltd/recall](https://github.com/locatelankaltd/recall.git), connected as `origin`. The initial local snapshot is being prepared. Remote upload is not verified because the authenticated GitHub account has read-only access; no successful commit/push is claimed here. Design provenance and reference studies remain in [design notes](docs/DESIGN.md) and [brand provenance](assets/brand/PROVENANCE.md). Commercial viability still needs validation with real client teams.
