# Recall 0.2 release acceptance

Version **0.2.0+2** is a development candidate with the Supabase account gateway,
recipient review, optional AI, native billing and local reminders implemented in
code. The Recall cloud environment has not been provisioned, and provider/store
configuration remains pending. This record separates automated verification,
builds, installed versions, hosted behavior and publication.

## Current evidence

| Gate | Current result |
| --- | --- |
| Full Dart analysis | Passed with zero issues |
| Full Flutter suite | **142/142 pass**, including 21 billing and 11 reminder tests; `/private/tmp/recall-v02-flutter-tests-final.log` |
| PostgreSQL | **89 passing assertions** for owner/RLS isolation, immutable versions, CAS/publication, plan limits, atomic budgets and receipt replay |
| Edge mocks | **47 passing tests**; no external Auth/provider calls or store transactions |
| Deno | All **five** real Edge entrypoints pass Deno 2.9.6 type/import checks |
| 0.2 web release build | Passed in 31.2s; Wasm dry run passed; 10 browser captures with `errors: []` |
| 0.2 Android debug build | Passed; version/package/manifest inspected and debug signature verified |
| 0.2 Android release AAB | R8/bundle and ZIP CRC passed; **unsigned**, not upload-ready |
| 0.2 iOS simulator debug build | Build and `codesign --verify --deep --strict` passed; first-launch smoke passed |
| 0.2 physical-device install/QA | Pending; last verified Samsung development install is **0.1** |
| Hosted Auth/review/AI/billing | Supabase implementation unprovisioned; Firebase Hosting selected; Firebase-only backend selected; port pending; no deployment |
| Store-signed artifacts/submission/approval | Not performed |

The retained Python/SQLite service has **29 foundation tests** and historical local
recipient-browser evidence. It is a separate legacy development reference, not
the primary Supabase account backend. Historical `artifacts/qa/ios-first-launch.png` and
`artifacts/qa/samsung-first-launch.png` refer to **0.1**. The canonical build output
paths now contain the **0.2** artifacts below and must not be treated as old 0.1
files. Private QA evidence is Git-ignored. The original app/package and its data remain separate
and preserved.

## Verified 0.2 artifacts

| Artifact | Exact current result |
| --- | --- |
| Web | `build/web`; release compile 31.2s; Wasm **dry run** succeeded (no separate Wasm release claim) |
| Android debug APK | `build/app/outputs/flutter-apk/app-debug.apk`; **166,581,181 bytes**; version **0.2.0+2**; package `com.recharge.recall_next`; min API 26 / target 36; optional microphone; billing and notification permissions present; `apksigner verify` exit 0 |
| Android release AAB | `build/app/outputs/bundle/release/app-release.aab`; **62,331,476 bytes**; R8/bundle build and ZIP CRC valid; **no signature entries**, therefore unsigned and not ready for upload |
| iOS simulator bundle | `build/ios/iphonesimulator/Runner.app`; version **0.2.0+2**; bundle `com.recharge.recallNext`; minimum iOS 15; deep/strict signature verification passed |

SHA-256 fingerprints:

```text
APK  782a08675867d81d67b8b4099f0fb7425a0c504adcf2ac9bd7e0dedce5bfbc44
AAB  2ee71cb70cafab25683f98023b38a116e589ebf435e3452ff84bc5fdfada1860
```

A fresh isolated iPhone 17 simulator on iOS 26.5 rendered the welcome screen with
no error, overflow or notification permission prompt. Evidence:
`artifacts/qa/ios-v02-first-launch.png` and
`artifacts/qa/ios-v02-first-launch-status.json`. This was a first-launch rendering
check; no feature interaction or physical iOS device is claimed. The owned
temporary simulator was shut down/deleted and cleanup verified; no other simulator
was changed. Ten web-browser captures reported an empty error list.

Disk filled during release AAB packaging. Cleanup was limited to the owned
simulator/caches and generated build intermediates; the retry passed. The final
APK/AAB sizes and fingerprints above were read back from the existing files.
Samsung's last installation performed by this work remains 0.1. The final ADB
listing contains no connected device. No 0.2 physical installation or live
provider/Auth/store transaction has occurred.

Source target [locatelankaltd/recall](https://github.com/locatelankaltd/recall.git)
is connected as `origin`. The initial local snapshot is being prepared; remote
upload is unverified because the authenticated account has read-only GitHub access.
No successful commit/push is claimed. Private QA artifacts remain ignored.

## Candidate build commands

The root task runs Flutter/native builds serially to avoid toolchain/cache races.
Use the public configuration described in the [README](../README.md#run) when a
selected backend/store environment is available. An unconfigured build still
exercises private device workflows.

```sh
flutter build web --release
flutter build apk --debug
flutter build appbundle --release
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer flutter build ios --simulator --debug
```

Expected output locations are `build/web`,
`build/app/outputs/flutter-apk/app-debug.apk`, and
`build/ios/iphonesimulator/Runner.app`. A path alone does not establish a completed
build. Record the result, version, package identity, hash/signature where
applicable, and exact installed version before attributing QA to it. Debug APKs
and simulator bundles are not store distribution artifacts.

Current development identities are Android `com.recharge.recall_next` and iOS
`com.recharge.recallNext`. The native callback is
`io.recall.app://login-callback` and is registered in both platforms. Permanent
identities, signing ownership and migration decisions still precede a store
submission. The original package must not be overwritten as part of that decision.

## Remaining connected-service review

- [ ] Complete and retest the selected Firebase-only backend port before deployment.
  Firebase Hosting is selected; the unprovisioned Supabase implementation remains
  a reference. Its existing migration/function sequence is migrations 001–005 and `account-delete`, `analyze-source`, `transcribe-recording`,
  `billing-webhook` and `refresh-entitlement` with their shared modules. Record the
  exact project/version and inspect grants/advisories.
- [ ] Configure the web origin, recipient `PUBLIC_APP_URL`, public client key,
  `AUTH_REDIRECT_URL` and Supabase allowed redirects. Verify controlled sign-up,
  email/recovery, sign-in/out and account deletion against the candidate.
- [ ] Verify real owner/outsider isolation and browser review: exact item scope,
  original/proposed values, identity wording, expiry/revocation, duplicate or
  interrupted responses, corrections and stale proposals. All required reviews
  must precede publication; closed links must not reopen source context.
- [ ] Complete the existing secure OpenAI credential workflow and server settings,
  then evaluate explicit text/audio consent and draft quality in representative
  languages. No paid/live accuracy check has happened so far.
- [ ] Configure RevenueCat/store app keys, products/offerings and `pro` entitlement.
  Verify actual localized price/period, cancellation/pending/error, purchase,
  restore, expiry/refund/transfer, server entitlement freshness and Free/Pro caps.
  SDK success alone must never unlock service. Production sandbox access stays off.

No cloud deployment has occurred. The implemented Supabase backend remains
unprovisioned and retained as a reference; Firebase Hosting and a Firebase-only
backend are selected, with the backend port pending. AI provider credentials and RevenueCat/store configuration are
not set. Server secrets never belong in Flutter public defines. See
[deployment status](FULL_VERSION_STATUS.md) for the sequence; the Oct 24 local
build/test evidence does not establish hosted operation.

## Remaining device and publication review

- [ ] Install and identify the **0.2** candidate on controlled Android/iOS devices.
  Exercise capture/import/share, recording permission/denial/lifecycle, private
  audio export/removal, restart/recovery, account transitions and review links.
  Android receives plain text; do not claim an iOS Share extension.
- [ ] Verify reminders remain off until enabled, request permission at that point,
  use the resolved IANA device zone, preserve 09:00 calendar-day behavior across
  DST, contain generic text, and cancel old workspace/account schedules. Check
  actual delivery, reboot, timezone changes and device battery restrictions.
- [ ] Verify TalkBack/VoiceOver, large text, keyboard/safe areas, contrast and
  reduced motion on supported screens; review EN/ES/FR wording and actual source
  language/date/currency workflows. Do not infer universal RTL/language quality.
- [ ] Confirm final package IDs, signing, store records, current platform/SDK and
  native-library compatibility using the actual Console/Xcode results. Validate
  Android App Bundle and iOS distribution archive separately from debug builds.
- [ ] Provide working privacy/support/deletion resources, accurate SDK/data
  disclosures, subscription terms/management and reviewer access. Account deletion
  must stay accessible and explain that store subscriptions are cancelled in the
  store. Review screenshots and metadata against implemented behavior.
- [ ] Review the exact artifacts and connected/device evidence, then obtain the
  intended publication decision. Submission, approval and production operation
  are separate recorded outcomes.

Official publication references to verify at submission:
[Google target API](https://support.google.com/googleplay/android-developer/answer/11926878),
[Android signing](https://developer.android.com/studio/publish/app-signing),
[Android page sizes](https://developer.android.com/guide/practices/page-sizes),
[Apple distribution](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases),
[Apple review guidelines](https://developer.apple.com/app-store/review/guidelines/),
[Apple subscriptions](https://developer.apple.com/app-store/subscriptions/),
[Google subscriptions](https://support.google.com/googleplay/android-developer/answer/9900533),
[Google deletion](https://support.google.com/googleplay/android-developer/answer/13327111).
