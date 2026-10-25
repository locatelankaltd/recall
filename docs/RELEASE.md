# Recall 0.3 release acceptance

Package **0.3.0+3**, updated **25 October 2026**. The active implementation uses Firebase Auth, Firestore, Cloud Functions and Hosting in `recall-f1d1e`. Provider/store configuration and live service verification remain separate from compilation and local tests.

## Current evidence

| Gate | Current result |
| --- | --- |
| Flutter / analysis | Final 157/157 tests pass; analysis zero issues |
| Backend | Final build plus 70 tests pass with Admin 14.5 / Functions 7.4 |
| Production dependency audit | Zero reported vulnerabilities |
| Web release | Publish build passed in 32.1s with Wasm dry run; later static loader/icon polish leaves compiled Dart unchanged |
| Firebase infrastructure | Auth/database/apps/runtime IAM configured in the selected project |
| Firestore rules | Deployed; source match verified; anonymous read returns 403 |
| Functions / Hosting release | Core API ACTIVE; 82-file Hosting release live; home/sign-in rendering verified |
| Controlled live API helper | 18/18 direct and 18/18 Hosting-proxy checks pass; all synthetic fixture cleanup verified |
| Android 0.3 | Retry running after earlier disk-space failure; **no completed 0.3 APK verified yet** |
| iOS 0.3 | SwiftPM dependency prefetch running; no build/launch result yet |
| Phone install | Last verified Samsung installation is **0.1**; latest ADB listing has no connected device |
| Signed store release/submission/approval | Not performed |
| Source upload | Selected repository verified; initial uploaded baseline `e6f5c30`; consult source history for the delivery revision |

The candidate is not store-production-ready. The core app is deployed at [recall-f1d1e.web.app](https://recall-f1d1e.web.app). Controlled tests used synthetic Admin-verified accounts; actual email delivery and physical-device features need separate acceptance. OpenAI/RevenueCat secrets and store keys/products remain unset; no live AI or store transaction is claimed.

## Historical 0.2 evidence

The following results belong to **0.2.0+2 on 24 October 2026**, before the Firebase port. Earlier backend sources are archived in `legacy/supabase` and `legacy/service`. They are historical records, not current artifact checks:

| Historical result | Recorded evidence |
| --- | --- |
| Flutter | 142 tests passed; analysis clean |
| Supabase reference | 89 PostgreSQL assertions; 47 Edge mocks; five Deno entrypoints checked |
| Python reference | 29 foundation tests |
| Web | 31.2s release build; Wasm dry run; 10 captures with no reported browser errors |
| Android APK | 166,581,181 bytes; debug signature verified; package `com.recharge.recall_next`, min 26 / target 36 |
| Android AAB | 62,331,476 bytes; R8/bundle and ZIP CRC passed; unsigned |
| iOS simulator | Build/signature and fresh iPhone 17 / iOS 26.5 first launch passed; feature/device QA not implied |

Historical fingerprints:

```text
0.2 APK  782a08675867d81d67b8b4099f0fb7425a0c504adcf2ac9bd7e0dedce5bfbc44
0.2 AAB  2ee71cb70cafab25683f98023b38a116e589ebf435e3452ff84bc5fdfada1860
```

**The generated 0.2 native outputs were removed for disk space.** These fingerprints must not be attributed to current build paths or to 0.3. Historical screenshots/logs remain; `ios-v02-first-launch.png` is first-launch evidence only, while `ios-first-launch.png` and `samsung-first-launch.png` refer to 0.1. Private QA files remain Git-ignored.

## Candidate build commands

```sh
flutter build web --release --dart-define-from-file=config/firebase/web.json
flutter build apk --debug --dart-define-from-file=config/firebase/android.json
flutter build appbundle --release --dart-define-from-file=config/firebase/android.json
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer flutter build ios --simulator --debug --dart-define-from-file=config/firebase/ios.json
```

Run native builds serially and retain enough disk space. For each completed artifact, record version, package identity, hash, signature and installed version. A path alone is not build evidence. Debug APKs and simulator bundles are not store distribution artifacts.

Current development storage bounds are 6 MiB across an account and 5 MiB per-project reserved charge. Review headroom is reserved, but a large partial confirmation may safely fail until the owner frees capacity. These are content limits, not unlimited Pro storage.

Current separate development identities are Android `com.recharge.recall_next` and iOS `com.recharge.recallNext`. Permanent store identities, signing ownership and migration decisions remain outstanding. The original app/source/data is preserved; no existing-user or production-data migration is claimed.

## Remaining service acceptance

- [x] Final backend and Flutter checks passed; `recallApi` and Hosting are deployed to `recall-f1d1e`.
- [x] Controlled owner/outsider isolation, exact scope, unverified identity wording, stale/revoked links, receipt replay, correction and recent-auth deletion passed at direct and Hosting-proxy endpoints. Fixture Auth/project/link records were removed; minimal hashed deletion fences intentionally remain.
- [ ] Test actual email verification/recovery delivery separately.
- [ ] Configure server provider secrets, enable optional AI deliberately, and evaluate source/transcription quality with explicit consent.
- [ ] Configure store app keys, products/SKUs, offerings and the `pro` entitlement. Verify localized prices/periods, cancellation/pending/error, purchase, restore, expiry/refund and trusted server state. Keep production sandbox access disabled.

## Remaining device and publication acceptance

- [ ] Build and install the identified 0.3 candidate on controlled Android/iOS devices. Exercise recording permission/denial/lifecycle, source import/share, private audio export/removal, account transitions and restart/recovery. Android receives text; an iOS Share extension is not implemented.
- [ ] Verify reminder opt-in, generic notification content, IANA-zone timing, actual delivery, reboot and workspace cancellation under device battery restrictions.
- [ ] Review TalkBack/VoiceOver, large text, contrast, keyboard/safe areas, reduced motion and EN/ES/FR wording. Do not infer universal RTL or language quality.
- [ ] Confirm final package IDs, distribution signing and native compatibility; validate the actual Android bundle and iOS archive.
- [ ] Supply working privacy/support/deletion resources, accurate SDK/data disclosures, subscription terms and reviewer access. Account deletion must explain that store subscriptions are cancelled separately in the store.
- [ ] Review the exact release artifacts and connected/device evidence before submission; store approval and production operation are separate outcomes.

See [Firebase deployment](FIREBASE_DEPLOYMENT.md), [full status](FULL_VERSION_STATUS.md) and the [backend contract](CLOUD_CONTRACT.md). Official publication references: [Android signing](https://developer.android.com/studio/publish/app-signing), [Apple distribution](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases), [Google account deletion](https://support.google.com/googleplay/android-developer/answer/13327111).
