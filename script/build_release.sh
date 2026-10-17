#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TASK_ROOT"
OUT="${COMMANDER_DISTRIBUTION_DIR:-$TASK_ROOT/.build/distribution}"
mkdir -p "$OUT" .build/logs
case "${1:-}" in ''|--prepare-only) ;; *) echo 'usage: build_release.sh [--prepare-only]' >&2; exit 2;; esac
./script/resolve_dependencies.sh
python3 script/prepare_licenses.py
python3 script/verify_licenses.py
if [[ "${1:-}" == --prepare-only ]]; then echo 'Release dependencies and source resources prepared.'; exit 0; fi
xcodebuild -project Commander4Mac.xcodeproj -scheme Commander4Mac -configuration Release -destination 'generic/platform=macOS' -derivedDataPath .build/xcode -archivePath "$OUT/Commander4Mac.xcarchive" -onlyUsePackageVersionsFromResolvedFile archive >.build/logs/release-archive.log 2>&1
# Xcode's Developer ID export re-signs Sparkle's nested helpers while preserving
# their required sandbox entitlements. Validate/export before notarizing bytes.
xcodebuild -exportArchive -archivePath "$OUT/Commander4Mac.xcarchive" -exportPath "$OUT/export" -exportOptionsPlist Configuration/ExportOptions.plist >.build/logs/release-export.log 2>&1
APP="$OUT/export/Commander4Mac.app"
python3 script/verify_release.py "$APP"
echo "Verified Developer ID export: $APP"
echo 'Next: notarize and staple the app, then build and notarize the final DMG.'
