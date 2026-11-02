# আমার হিসাব · Amar Hisab Fresh

Fresh offline Bengali Flutter/SQLite Android application in
`reazempiree/amarhisab`, branch `feat/fresh-flutter-app`.

**Development checkpoint — not a verified production release. No APK has been
built or tested yet. Pakistan Save is deliberately blocked until the agent
commission business rule is supplied. Do not use this checkpoint for real funds.**

The source includes an exact integer ledger, Bengali outlined-card interface,
Bangladesh remittances, deposits, wallet expenses, transfers, bank corrections,
agent advance/payment/refund accounting, cycle/period closure, general obligations,
allocation-based histories, reports, encrypted manual backups, fresh-install restore,
PIN/biometrics, and backup-gated account clearing. These features need execution
and device validation; source presence is not a claim of verified behavior.

## Development

- Flutter source pinned to **3.47.9**, commit
  `c197ca5199e9ee5661e865596c9c07294dfab51c` (SDK execution not yet available).
- Java 21, Android SDK 36 / build-tools 36.0.0, min Android API 24.
- Gradle 9.3.1 distribution checksum is pinned in the wrapper configuration.
- Package `com.reazempire.amarhisab.fresh`; debug signing only. Production signing
  needs a persistent private key supplied securely outside this repository.
- Bundled Noto Serif Bengali variable font under the SIL Open Font License.

From this checkout, with Flutter on PATH and ANDROID_HOME configured:

```sh
./tool/validate.sh
```

This runs dependency resolution, formatting, analysis, application tests and the
debug APK build. After the first successful dependency resolution, review and
commit `pubspec.lock` for reproducible application dependencies. No lockfile was
invented while the SDK was unavailable.

Run on an attached Android device using `flutter run`. Never uninstall or clear
the old app's data. This project does not know its package ID or backup format.

## Validation actually performed

- `python3 tool/verify_schema.py`: **6 schema checks passed** on Python SQLite.
- Supplemental tree-sitter grammar check: **13 Dart files parsed without grammar
  errors**. This is not Dart analysis, compilation or application testing.
- Android SDK packages installed; `adb devices`: no device/emulator attached.
- Flutter SDK bootstrap: **failed**, HTTP CONNECT 403 for required official Dart
  artifacts at `storage.googleapis.com`.
- `dart format`, `flutter analyze`, `flutter test`, `flutter build apk --debug`:
  **not run**, because the SDK cannot initialize. Flutter test results are unknown.
- GitHub API status inspection: blocked (`api.github.com` Forbidden).

GitHub Actions runs the required Flutter steps and uploads an APK plus checksum
**only if all preceding checks pass**. No successful run or artifact is claimed.

## Outstanding work

1. Allow `storage.googleapis.com` in cloud network settings. The attempted draft
   update was rejected by automatic approval review; no allowlist change was saved.
2. Initialize Flutter, resolve dependencies, commit the generated lockfile, run all
   required checks and fix any errors. Validate Gradle/plugin compatibility against
   the pinned Flutter release rather than assuming the manual host is correct.
3. Supply the Pakistan agent commission rule (a formula or worked example), then
   implement that rule in the form and test it. The engine accepts an explicit AED
   commission result; fixture amounts are not commercial policy.
4. Run Android functional/device tests, including platform file export/read-back,
   secure storage, biometrics, lock/resume and text scaling across the full UI.
5. Expand remaining mandatory coverage: actual future-version migrations, full
   account/agent destructive-flow widgets and recovery
   from platform/process failures. No real legacy migration can be validated until
   its schema/backup sample and password handling are provided securely.
6. Validate archived-period drill-down and improve agent destructive-dependency
   resolution UX and optional calendar analytics.

See [accounting and data-integrity rules](docs/ACCOUNTING.md) and the detailed
[handoff](docs/HANDOFF.md). Old encrypted backups are **not** declared compatible.
