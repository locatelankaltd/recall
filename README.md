# Recall 0.3

Recall helps independent professionals and small client teams keep one clear plan when conversations change the work. Preserve a request's source, compare the old and proposed scope, owner, deadline or fee, and keep the change proposed until the required people review that exact version. Delivery progress stays separate from agreement and payment.

**Version 0.3.0+3 uses Firebase Auth, Firestore, Cloud Functions and Hosting.** The selected project is `recall-f1d1e`. Its Auth, database, registered apps, runtime identity and restrictive client rules are configured. The server and web app are deployed at [recall-f1d1e.web.app](https://recall-f1d1e.web.app). Controlled live checks pass at both the direct API and Hosting proxy. AI credentials and native store configuration remain unset.

## Implemented

- Private device workspaces and separate authenticated workspaces, with verified email, account-bound requests, recovery and account deletion.
- Immutable proposals, canonical server snapshots, version checks, retry-safe writes, correction/history and scoped expiring or revocable client-review links. Link-holder identity is explicitly unverified; every changed item needs the required confirmations before publication.
- Typing, paste, UTF-8 source import, Android plain-text sharing and consent-led recording. Recordings stay private to the device; cloud evidence excludes local file paths. An iOS Share extension is not implemented.
- Optional source-analysis drafts and whole-recording machine transcription, requiring explicit consent and human review. AI cannot publish a plan or confirm a person.
- Native store offerings, purchase/restore and RevenueCat server verification in code. SDK purchase success alone cannot unlock paid access. Free accounts allow 3 cloud projects and 5 AI requests/day; verified Pro allows 100 and 20. AI also has a shared 100-request UTC-day service budget. Optional AI and billing are unavailable until configured.
- Default-off local reminders, up to 32 generic notifications using the device's IANA time zone, with workspace/account cancellation.
- Bounded export/restore, recovery, private recording export/removal, original branding, light/dark themes and English, Spanish and French interface text. Original source text retains its own language.

Account workspaces currently have a 6 MiB aggregate server budget and a 5 MiB per-project reserved-charge limit. Admission reserves review headroom, but a large partial review can still return a safe capacity error; the owner may need to export or delete content before continuing. Project-count allowances do not imply unlimited storage. Server-managed Firestore collections deny direct client reads and writes.

## Run and verify

Use Flutter with Dart 3.12+ and Node.js 22 for the backend. The public Firebase build files contain SDK configuration, not administrative or AI credentials:

```sh
flutter pub get
flutter run -d chrome --dart-define-from-file=config/firebase/web.json
flutter build web --release --dart-define-from-file=config/firebase/web.json
flutter build apk --debug --dart-define-from-file=config/firebase/android.json
```

The unconfigured build (`flutter run` without defines) keeps the private device workflow available. Android and iOS use the separate development identities `com.recharge.recall_next` and `com.recharge.recallNext`. Native iOS builds use `config/firebase/ios.json`.

```sh
dart analyze lib test
flutter test
npm --prefix functions ci
npm --prefix functions run build
npm --prefix functions run test:emulator
```

The backend emulator runner uses an isolated demo project and loopback ports, not the live database. Deploy commands and account selection are in [Firebase deployment](docs/FIREBASE_DEPLOYMENT.md).

## Current verification

| Check | Latest completed evidence |
| --- | --- |
| Flutter suite / Dart analysis | Final 157/157 pass; zero issues |
| Backend | Final build and 70 tests pass on Admin 14.5 / Functions 7.4 |
| Production dependency audit | Zero reported vulnerabilities |
| Web release | 32.1s publish build; Wasm dry run passed; later static loader/icon polish does not change compiled Dart |
| Firebase infrastructure | Auth/database/apps/runtime IAM configured; deny-all rules deployed and verified; anonymous read returns 403 |
| Functions / Hosting app release | Live API and 82-file Hosting release; 18/18 direct and 18/18 proxy checks pass with fixture cleanup |
| Native 0.3 | Android retry and iOS dependency prefetch in progress; no completed 0.3 native artifact verified yet |
| Phone / stores | Last verified Samsung install was 0.1; latest ADB check found no device. No store submission |

Live tests used synthetic accounts marked verified by Admin SDK; actual email delivery, AI quality and purchases remain unverified. Earlier 0.2 native artifacts are historical evidence; their generated outputs were removed for disk space. Do not treat those hashes or screenshots as a current 0.3 build.

## Source and delivery status

The initial source snapshot [`e6f5c30`](https://github.com/locatelankaltd/recall/commit/e6f5c30c2acc05c9abb0d539f4df75e136565da0) was pushed to [locatelankaltd/recall](https://github.com/locatelankaltd/recall), with the remote commit verified. Use the repository history to identify subsequent release commits. No existing-user, production-data or signing migration is claimed; the original application and source remain separate and preserved.

See [full status](docs/FULL_VERSION_STATUS.md), [release acceptance](docs/RELEASE.md), [Firebase architecture](docs/ADR-002-firebase.md), [backend contract](docs/CLOUD_CONTRACT.md), [transcription](docs/TRANSCRIPTION.md) and [design provenance](assets/brand/PROVENANCE.md). The earlier backends are preserved under [legacy](legacy/README.md): `legacy/supabase` and `legacy/service`. They do not power the Firebase runtime. Commercial viability still needs validation with real client teams.
