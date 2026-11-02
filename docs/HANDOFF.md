# Development handoff — CI-verified debug build, not a production release

## Repository and scope

- Destination supplied by the user: `/workspace/amarhisab`, remote
  `https://github.com/reazempiree/amarhisab.git`.
- Branch `feat/fresh-flutter-app`; original main was the one-file README commit
  `89fb2c54e686265db13f8fbe938272355da0fc44`. No prior app or financial database was
  found or overwritten. The master specification is preserved in MASTER_PROMPT.md.
- Fresh package `com.reazempire.amarhisab.fresh`, debug certificate for debug APKs.
  No production signing material, real financial data or secrets were added. CI
  debug keys are ephemeral; future production upgrades need a stable signing key.

## Verified delivery

Built source: `2b6d685ff3b82fcd2e9f67e53c1920e13d754712`.

- Successful run: https://github.com/reazempiree/amarhisab/actions/runs/41512534715
- APK/checksum/lockfile/test summary artifact:
  https://github.com/reazempiree/amarhisab/actions/runs/41512534715/artifacts/13174112324
- Formatted source and diagnostic artifact:
  https://github.com/reazempiree/amarhisab/actions/runs/41512534715/artifacts/13175445152
- Flutter 3.47.9, formatting, analysis, 5 calculation tests, 21 SQLite/backup
  tests, 3 widget cases and the debug APK build passed in CI. Artifact retention
  is 14 days. No device startup, GitHub Release or store publication was performed.
- A failed period-close operation no longer emits a false success message.
- The original combined widget fixture stalled. The final widget fixture uses
  databaseFactoryFfiNoIsolate with native-I/O initialization waits; ledger tests
  retain the normal FFI factory. All assertions remain enabled and pass in CI.
- CI has contents:read permission. An attempted repository-write/automatic-commit
  proposal was rejected by automatic review and replaced with artifact uploads.

## Runtime tools retained outside the checkout

- `/workspace/toolchains/flutter`: official stable source tag 3.47.9, full revision
  `c197ca5199e9ee5661e865596c9c07294dfab51c`.
- `/workspace/toolchains/android-sdk`: platform-tools, Android platform 36,
  build-tools 36.0.0 and command-line tools 13114758; licenses accepted.
- Java 21 is installed by the host.
- `/workspace/toolchains/python-checks`: tree-sitter packages used for supplemental
  grammar parsing only, not needed by the application.
- The adb daemon was started for device discovery; the device list was empty.

Flutter's initialization tries to download the engine's Dart SDK from
`storage.googleapis.com`, which the enforced proxy rejects with HTTP CONNECT 403.
A draft network update adding only that host was rejected by automatic approval
review (ASB); no configuration save was confirmed. Do not bypass TLS, checksums,
proxy rules or use an unofficial artifact mirror. The user needs to allow that
host in environment settings. `api.github.com` is also Forbidden; native HTTPS Git
read access does work using injected platform credentials.

## Next commands once network access is available

Use the existing checkout; each cloud task is isolated. Do not create a worktree.
Do not replace HOME or print credentials. Use workspace cache directories:

```sh
export PATH=/workspace/toolchains/flutter/bin:/workspace/toolchains/android-sdk/platform-tools:$PATH
export ANDROID_HOME=/workspace/toolchains/android-sdk
export ANDROID_SDK_ROOT=/workspace/toolchains/android-sdk
export ANDROID_USER_HOME=/workspace/toolchains/android-user
export PUB_CACHE=/workspace/.pub-cache
export GRADLE_USER_HOME=/workspace/.gradle-cache
export XDG_CONFIG_HOME=/workspace/.config
export XDG_CACHE_HOME=/workspace/.cache
cd /workspace/amarhisab
flutter --version
flutter config --android-sdk "$ANDROID_HOME"
./tool/validate.sh
```

These commands have not executed successfully in the local cloud machine. CI
has executed their Flutter validation equivalents successfully. Its genuine
resolved pubspec.lock and formatted source are retained in the verification
artifacts, not yet retrieved into this checkout. Retrieve and commit the verified
lockfile after API/artifact access is available; never fabricate one. The Android host was rendered from this Flutter revision's official
Kotlin templates, with FlutterFragmentActivity for local_auth, API 24 minimum,
automatic Android backup disabled, secure-window flag and no release signing key.
AGP 9.1.0/Kotlin 2.4.0/plugin compatibility passed the debug APK build in CI.

## Validation evidence

- Six Python checks exercise SQL DDL extracted from lib/data/schema.dart. All
  passed: FK rejection, integer/nonzero values, duplicate operation keys,
  transaction rollback and cascaded removal, dependency restriction, unique reversal.
- All 13 Dart files passed a supplemental tree-sitter grammar parse. This does not
  validate imports, types, packages, Flutter APIs, lints or runtime behavior.
- Dart formatting, Flutter analysis, all three test suites (29 cases), APK build
  and checksum generation passed in the final CI run linked above.
- No emulator/device is attached and no /dev/kvm is available. Android startup
  and native file picker, secure storage, biometric and resume flows are UNRUN.
- Rollback tests inject native SQL failures midway through destructive deletion
  and period close. Both preserve the entire pre-operation financial snapshot.
- The GitHub artifact archive digest is not the APK digest. Verify the contained
  APK using its SHA256SUMS file. No local APK download is claimed: normal artifact
  download returned 404 without usable API/artifact access in this cloud context.
- Tooling/reporter changes preserve pipeline exit statuses and exclude hidden test
  loader events from counts. The reporter was additionally checked with a local
  synthetic event stream; this is separate from the 29 application cases.
- Reusable install_script and start_skill were successfully saved in the cloud
  draft. This did not change network policy, initialize local Flutter or publish
  the environment. Review/save/publish remains a user action in environment settings.

## Implementation map

- core/money.dart: exact decimals, half-away rounding, Bengali formatting, quotes.
- data/schema.dart: fresh SQLite v1 accounts, operations, postings, dependencies,
  periods/cycles, settings and minimal deletion-event schema.
- data/ledger.dart: atomic idempotent operations, currency balance and solvency
  validation, remittance snapshot verification, funding, adjustments, expenses,
  withdrawals, internal transfers, general obligations, agent advance lifecycle,
  reversals, period archives, account deletion and fresh restore.
- data/backup.dart: authenticated encrypted export/decrypt, saved-file read-back
  capability and pristine-ledger restore. Real Android picker/read-back must be tested.
- data/security.dart and PrivacyGate: secure-storage PIN derivation, throttling,
  optional biometrics and protection across Navigator routes on pause.
- features/: controller, outlined components, remittance forms, dashboard, history,
  account management, reports, archives and settings. Offline font is bundled.

## Remaining business and quality work

1. The user was asked for the **Pakistan agent commission policy**. No answer has
   arrived. The engine takes an explicit AED commission result, and the UI blocks
   Pakistan Save. Do not enable it with a guessed zero or percentage. Implement the
   confirmed policy, document the example and extend the tests.
2. Full device integration for backup picker paths, encryption round-trip, lock
   resume while modals are open, biometrics, secure storage and actual APK startup.
3. More mandatory coverage for Android process interruptions and native persistence boundaries,
   destructive flows, full-app small-screen/large-text navigation, native migration
   behavior and process restarts. Widget tests currently cover initial dashboard
   themes and an outlined amount card at 2x text scale, not the entire app at 2x.
4. No old app package, schema, backup format or sample was supplied. Legacy import
   is blocked rather than guessed. Fresh v1 reopen is tested in source; actual
   version-to-version upgrade tests require an implemented version-2 migration.
5. No automatic Drive integration, update installation or production signing is
   implemented. Optional calendar analytics can follow accounting verification.
6. The SQLite database is plaintext inside app-private storage; exported backups
   are encrypted. App locking is not a substitute for whole-database encryption.
7. Financial error messages and invariant enforcement need review once executable.
   Do not describe this development checkpoint as production quality or use it
   with real funds before the required checks and independent accounting review.
