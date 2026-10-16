#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TASK_ROOT"
mkdir -p .build/distribution .build/logs
python3 script/prepare_licenses.py
python3 script/verify_licenses.py
xcodegen generate >.build/logs/release-project.log
xcodebuild -project Commander4Mac.xcodeproj -scheme Commander4Mac -configuration Release -destination 'generic/platform=macOS' -derivedDataPath .build/xcode -archivePath .build/distribution/Commander4Mac.xcarchive archive >.build/logs/release-archive.log 2>&1
APP="$TASK_ROOT/.build/distribution/Commander4Mac.xcarchive/Products/Applications/Commander4Mac.app"
python3 script/verify_release.py "$APP"
echo "Verified release archive: $APP"
echo 'Next: notarize and staple the app, then build and notarize the final DMG.'
