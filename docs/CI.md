# Continuous integration

[CI](../.github/workflows/ci.yml) runs for pull requests targeting `main` and
pushes to `main`. Both jobs use Ubuntu 24.04 and a 20-minute timeout. New runs
cancel older runs on the same branch or pull request.

| Job | Toolchain | Checks |
| --- | --- | --- |
| Flutter analysis and tests | Flutter 3.44.0, bundled Dart 3.12 | Enforced dependency lockfile, analyzer, full Flutter tests with concurrency 2 |
| Backend build and emulator tests | Node 22, Temurin Java 21, Firebase CLI 15.32.0 | `npm ci`, TypeScript build, Auth/Firestore HTTP and transaction tests, mocked provider tests |

The backend command is `npm --prefix functions run test:emulator`. Its existing
runner creates a temporary configuration for `demo-recall-backend`, starts only
Auth and Firestore on isolated ports, and cleans up its emulator processes and
temporary files. The tests refuse to run against unexpected emulator hosts.
The current suite contains 70 checks; new tests run automatically without changing
the workflow. Provider calls are mocked, and synthetic Auth users stay inside the
Auth emulator. The workflow supplies no Firebase account, service-account key,
provider secret or deployment credential and contains no deployment step.

The GitHub token has only `contents:read`; checkout does not persist credentials.
The workflow uses `pull_request`, avoiding privileged execution of fork code.
Direct Action references are pinned to full commit hashes with release comments.
Review upstream changes and update both the hash and comment when updating an
Action. Flutter is pinned exactly; Node and Java retain their requested major
versions so hosted runners can receive compatible security patches.

Local equivalent commands are `flutter pub get --enforce-lockfile`,
`flutter analyze --no-pub --fatal-infos`, `flutter test --no-pub --concurrency=2`,
and `npm --prefix functions run test:emulator` after installing the listed backend
tools and running `npm --prefix functions ci`. Local results and workflow syntax
validation do not establish a GitHub CI pass. Inspect both job results on the
actual commit after pushing; native/store builds and controlled live verification
remain separate release checks.

Configuration references: [GitHub workflow security](https://docs.github.com/en/actions/reference/security/secure-use),
[checkout](https://github.com/actions/checkout),
[setup-node](https://github.com/actions/setup-node),
[setup-java](https://github.com/actions/setup-java),
[Flutter Action](https://github.com/subosito/flutter-action),
and [Firebase emulator project selection](https://firebase.google.com/docs/emulator-suite/connect_firestore#choose_a_firebase_project).
