#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter --version
flutter pub get
dart format lib test
flutter analyze
flutter test --reporter expanded
flutter build apk --debug
test -s build/app/outputs/flutter-apk/app-debug.apk
sha256sum build/app/outputs/flutter-apk/app-debug.apk
