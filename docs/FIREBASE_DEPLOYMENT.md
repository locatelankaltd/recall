# Recall 0.3 Firebase deployment

Package **0.3.0+3** uses Firebase Auth, Firestore, Cloud Functions and Hosting.
Recall's selected Firebase and Google Cloud project is **recall-f1d1e** (project
number `70254700826`). The project account is `locatelankaltd@gmail.com`; commands
must select that account and project explicitly.

## Verified configuration

On 25 October 2026, readback confirmed that the selected account has the project's
`roles/owner` IAM role. Cloud Billing was already enabled with a linked account
(the Firebase Blaze plan). This setup did not attach or change a billing account.
Blaze is pay as you go; its free quotas do not establish a fixed monthly total.

The default Firestore database was absent before setup and is now created in
`europe-west1`, using the Standard edition and native Firestore mode. Creation
returned `freeTier: true`; point-in-time recovery remains disabled. No production
project data or files were imported by this setup.

Email/password authentication is enabled, with a password required. The authorized
web domains are `recall-f1d1e.web.app` and `recall-f1d1e.firebaseapp.com`. Firebase
returned the authentication subtype `IDENTITY_PLATFORM`. No provider keys or
administrative credentials are embedded in the client configuration.

The registered apps match the separate development identities:

| Platform | Registered app ID | Package/bundle |
| --- | --- | --- |
| Web | `1:70254700826:web:f414842e076344237824a3` | Recall Web |
| Android | `1:70254700826:android:8d42c904df72aa527824a3` | `com.recharge.recall_next` |
| iOS | `1:70254700826:ios:0673a03790536bf77824a3` | `com.recharge.recallNext` |

Public Flutter build definitions are in `config/firebase/{web,android,ios}.json`.
These contain Firebase's public SDK API keys, not server secrets. Their
`storageBucket` value is SDK metadata; a Cloud Storage bucket or audio-upload
feature has not been provisioned by this setup.

## Deployment state

The deny-all Firestore client rules and index configuration were deployed on
25 October 2026. Readback of the active `cloud.firestore` rules release exactly
matched the local `firestore.rules`, SHA-256
`ce937c4fac27c31b8351ff313168c1e6b5144d78258244b6c2ebf68ccb1f292a`.
Client reads and writes remain denied; the server Admin SDK is responsible for
authenticating and authorizing agreement operations.

A live anonymous REST read using the public client key returned HTTP 403,
`PERMISSION_DENIED`, with "Missing or insufficient permissions." No private
document was read or written by that check.

The web app is live at <https://recall-f1d1e.web.app>. The `recallApi` function is
ACTIVE at <https://europe-west1-recall-f1d1e.cloudfunctions.net/recallApi>, and Hosting
forwards `/api` requests to it. The 82-file Hosting release completed, and live
home/sign-in rendering was verified. The public Cloud Run invocation policy
remains the original unconditional `allUsers` mode; no manual IAM-disable or
revision update is attributed to this release. A seven-day Artifact Registry
cleanup policy is configured.

The source-controlled `firebase.json` serves `build/web`, forwards `/api/**` to
`recallApi` in `europe-west1`, and sends remaining application routes to
`index.html`. Its headers prevent framing, disable unused camera/location access,
allow this app's microphone, and suppress referrer information. Application
entrypoints revalidate rather than staying cached across releases.

The Cloud Functions source is `functions`, codebase `recall`, Node.js 22. Its
dedicated runtime service account is
`recall-api@recall-f1d1e.iam.gserviceaccount.com`. Project IAM readback confirms
`roles/datastore.user` and `roles/firebaseauth.admin`; no user-managed keys were
created, and no broad Editor or Secret Manager role was granted by this setup.
Firestore client rules must remain restrictive; agreement writes are validated by
the server. Review the actual backend test results before deploying it.

The final backend run built successfully with Firebase Admin 14.5 and Functions
7.4, passed 70 tests and reported zero production dependency vulnerabilities.
Final Flutter verification passed 157 tests with zero analysis issues. The publish
web build completed in 32.1s with a successful Wasm dry run; later static loader
and PWA-icon polish leaves compiled Dart unchanged.

Current development content bounds are 6 MiB per account and 5 MiB reserved charge
per project. Admission reserves review headroom, but large partial confirmations
can still fail safely at the limit until the owner frees capacity.

Controlled live checks passed **18/18 at the direct function URL and 18/18 through
the Hosting `/api` proxy**, with no automatic transport retries. Synthetic Auth
users, projects and link records were cleaned up for both runs; minimal hashed
deletion fences remain intentionally. An earlier interrupted attempt was also
recovered through the actual account-deletion API. The fixtures were marked
verified by Admin SDK; actual email delivery was not tested. No AI provider call
or store transaction was used.

## Build and release commands

```sh
flutter build web --release --dart-define-from-file=config/firebase/web.json
firebase deploy --only firestore:rules,firestore:indexes,functions \
  --project recall-f1d1e --account locatelankaltd@gmail.com
firebase deploy --only hosting --project recall-f1d1e \
  --account locatelankaltd@gmail.com
```

These commands reproduce the release sequence; the completed evidence is recorded
above and in [release acceptance](RELEASE.md). Always pass both project and account. Global CLI defaults can refer
to other accounts and projects and are not changed by this setup.

Local emulators bind only to loopback: Auth `9099`, Firestore `8080`, Functions
`5001`, Hosting `5000`, and emulator UI `4000`. Live verification covered owner isolation, exact-version review, anonymous link
responses, stale/revoked links and account deletion. Actual inbox recovery and
physical-device acceptance remain separate. Provider/store features remain
unavailable until their server secrets and merchant configuration are supplied.

Official references: [Hosting configuration](https://firebase.google.com/docs/hosting/full-config),
[Firebase pricing plans](https://firebase.google.com/docs/projects/billing/firebase-pricing-plans),
[Functions deployment](https://firebase.google.com/docs/functions/get-started?platform=flutter),
[Public Firebase configuration](https://firebase.google.com/docs/projects/learn-more#config-files-objects).
