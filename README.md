# আমার হিসাব · Amar Hisab Fresh

Offline Bengali Flutter/SQLite Android remittance accounting application.

**Debug build verified in GitHub Actions. This remains a development checkpoint:**
Pakistan Save awaits the user's agent commission rule, native Android behavior
needs device testing, and legacy backups are not declared compatible. Do not
replace the old application or use this checkpoint for real funds yet.

## Download and verification

- [Debug APK artifact, checksum, test results and dependency lockfile](https://github.com/reazempiree/amarhisab/actions/runs/41512534715/artifacts/13174112324)
- [Successful verification workflow](https://github.com/reazempiree/amarhisab/actions/runs/41512534715)
- [Formatted source and diagnostic evidence](https://github.com/reazempiree/amarhisab/actions/runs/41512534715/artifacts/13175445152)
- Built source commit: `2b6d685ff3b82fcd2e9f67e53c1920e13d754712`
- Branch: `feat/fresh-flutter-app`, repository `reazempiree/amarhisab`.

Artifacts require appropriate GitHub access and expire after 14 days. The APK is
inside the artifact archive under `build/app/outputs/flutter-apk/app-debug.apk`.
`SHA256SUMS` verifies the APK; the GitHub artifact digest verifies the archive,
which is a different file. No GitHub Release or store publication was performed.

CI used Flutter **3.47.9** and Java 21. These checks passed for the built commit:

- `flutter pub get` and `dart format lib test`
- `flutter analyze`
- 5 exact financial calculation tests, 21 SQLite/backup tests, 3 widget cases
- `flutter build apk --debug` and APK checksum creation

The 29 test cases include funded-on-save, cent reconciliation, duplicate keys,
wallet separation, funding totals, repeated bank corrections, agent overpayments,
advance application/refund, period closure, cross-account deletion/dependencies,
native SQL failure rollback, backup round trips and reopen persistence. Widget
coverage includes Bengali labels, outlined cards, light/dark dashboard variants
and a large-text amount card. This does not replace full Android device validation.
Six additional Python checks against the actual SQLite schema also passed.

## Accounting and interface

The app contains an exact integer-minor-unit ledger, Bengali outlined-card UI,
Bangladesh remittances, deposits, wallet expenses/withdrawals, internal transfers,
audited bank corrections, agent settlement/advance/refund accounting, period and
agent cycles, general obligations, allocation-based histories, reports, encrypted
manual backups, pristine-install restore, PIN/biometrics and backup-gated account
clearing. See [accounting rules](docs/ACCOUNTING.md) for formulas and boundaries.

The Pakistan engine accepts an explicit AED commission result; the form deliberately
cannot save until the user's actual business rule is confirmed and implemented.
Test commission values do not select a commercial policy.

## Development and signing

With Flutter on PATH and Android SDK configured, run:

```sh
./tool/validate.sh
```

Java 21, Android SDK 36, build-tools 36.0.0 and min Android API 24 are used. The
Gradle 9.3.1 distribution checksum is pinned. The bundled Noto Serif Bengali font
uses the SIL Open Font License.

Package: `com.reazempire.amarhisab.fresh`. Debug APKs use temporary development
signing; different CI runs can generate different debug keys. Upgrades require
the same package and certificate. No stable production signing key is configured
or committed. The old app's package ID is unknown, so side-by-side compatibility
has not been checked against an installed copy. Never uninstall it or clear its
financial data without verified backup and migration.

CI resolved dependencies successfully and retains the genuine `pubspec.lock` and
formatted source in its artifacts. The lockfile has not yet been retrieved into
this checkout because GitHub API/artifact access is blocked in the cloud machine.
Do not invent a lockfile; retrieve the verified one or resolve and revalidate it.

The current cloud machine retains SDK source and Android tools, but initializing
Flutter locally is blocked by the proxy at `storage.googleapis.com`. Automatic
review rejected the attempted domain addition. Add that domain in environment
settings for local Flutter work; `api.github.com` is also needed for authenticated
CI log/artifact retrieval. Existing GitHub authentication already works for Git.
Reusable install/start instructions were saved in the environment draft; saving
that draft did not publish or apply it.

Remaining work: confirm Pakistan commission policy; run real Android startup,
file export/read-back, secure storage, biometrics, lock/resume and full-app text
scaling checks; validate future schema migrations when introduced; inspect a real
legacy backup format before importing it. Automatic Drive backup, update installs
and optional calendar analytics are not implemented. See [handoff](docs/HANDOFF.md).
