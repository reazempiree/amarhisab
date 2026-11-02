# Development handoff — not a verified release

## Repository and scope

- Destination supplied by the user: `/workspace/amarhisab`, remote
  `https://github.com/reazempiree/amarhisab.git`.
- Branch `feat/fresh-flutter-app`; original main was the one-file README commit
  `89fb2c54e686265db13f8fbe938272355da0fc44`. No prior app or financial database was
  found or overwritten. The master specification is preserved in MASTER_PROMPT.md.
- Fresh package `com.reazempire.amarhisab.fresh`, debug certificate for debug APKs.
  No production signing material, real financial data or secrets were added.

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

These Flutter commands have NOT yet executed successfully. Dependencies have not
been resolved, so no pubspec.lock exists. Review and commit the genuine resolved
lockfile. Fix any formatter/analyzer/type/plugin/test errors before claiming
readiness. The Android host was rendered from this Flutter revision's official
Kotlin templates, with FlutterFragmentActivity for local_auth, API 24 minimum,
automatic Android backup disabled, secure-window flag and no release signing key.
Verify AGP 9.1.0/Kotlin 2.4.0/plugin compatibility on the actual build.

## Validation evidence

- Six Python checks exercise SQL DDL extracted from lib/data/schema.dart. All
  passed: FK rejection, integer/nonzero values, duplicate operation keys,
  transaction rollback and cascaded removal, dependency restriction, unique reversal.
- All 13 Dart files passed a supplemental tree-sitter grammar parse. This does not
  validate imports, types, packages, Flutter APIs, lints or runtime behavior.
- Dart/Flutter formatting, analysis, tests and APK build are all UNRUN because the
  official SDK cannot initialize. Device startup is UNRUN; no device is attached.
- Unit/SQLite/backup/widget test sources were authored, not reported as passing.
  They may expose defects once executable and must be run and fixed honestly.
- The Actions workflow checks analysis/tests before uploading a debug APK and SHA256.
  Do not invent a run URL or artifact URL; inspect actual outcomes after push.

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
3. More mandatory coverage for failure injection at native persistence boundaries,
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
