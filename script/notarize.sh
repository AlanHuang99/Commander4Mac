#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TASK_ROOT"
ACTION="${1:?usage: notarize.sh app-submit|app-finish|dmg-submit|dmg-finish [keychain-profile]}"
PROFILE="${2:-Commander4Mac-notary}"
OUT="$TASK_ROOT/.build/distribution"
APP="$OUT/Commander4Mac.xcarchive/Products/Applications/Commander4Mac.app"
DMG="$OUT/Commander4Mac-1.0.dmg"
mkdir -p "$OUT/notarization"
case "$ACTION" in
 app-submit)
  xcrun notarytool history --keychain-profile "$PROFILE" --output-format json >/dev/null
  python3 script/verify_release.py "$APP"
  test ! -e "$OUT/notarization/app-submission.json" && test ! -e "$OUT/notarization/app-submission.pending" || { echo 'Existing/uncertain submission: inspect its saved ID before retrying.' >&2; exit 2; }
  codesign -dv --verbose=4 "$APP" 2>&1 | sed -n 's/^CDHash=//p' > "$OUT/notarization/app-cdhash.txt"
  test -s "$OUT/notarization/app-cdhash.txt"
  ditto -c -k --keepParent "$APP" "$OUT/Commander4Mac-notarization.zip"
  shasum -a 256 "$OUT/Commander4Mac-notarization.zip" > "$OUT/notarization/app-upload.sha256"
  xcrun notarytool submit "$OUT/Commander4Mac-notarization.zip" --keychain-profile "$PROFILE" --output-format json > "$OUT/notarization/app-submission.pending"
  mv "$OUT/notarization/app-submission.pending" "$OUT/notarization/app-submission.json"
  cat "$OUT/notarization/app-submission.json";;
 dmg-submit)
  xcrun notarytool history --keychain-profile "$PROFILE" --output-format json >/dev/null
  xcrun stapler validate "$APP"
  python3 script/verify_release.py "$APP"
  test ! -e "$OUT/notarization/dmg-submission.json" && test ! -e "$OUT/notarization/dmg-submission.pending" || { echo 'Existing/uncertain submission: inspect its saved ID before retrying.' >&2; exit 2; }
  ./script/build_dmg.sh "$APP" "$DMG"
  shasum -a 256 "$DMG" > "$OUT/notarization/dmg-upload.sha256"
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --output-format json > "$OUT/notarization/dmg-submission.pending"
  mv "$OUT/notarization/dmg-submission.pending" "$OUT/notarization/dmg-submission.json"
  cat "$OUT/notarization/dmg-submission.json";;
 app-finish|dmg-finish)
  KIND="${ACTION%-finish}"
  ID="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["id"])' "$OUT/notarization/$KIND-submission.json")"
  xcrun notarytool info "$ID" --keychain-profile "$PROFILE" --output-format json > "$OUT/notarization/$KIND-status.json"
  STATUS="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["status"])' "$OUT/notarization/$KIND-status.json")"
  echo "$STATUS"
  case "$STATUS" in Accepted|Invalid|Rejected) ;; *) echo 'Submission is not finished. Run this finish action again later.'; exit 2;; esac
  xcrun notarytool log "$ID" --keychain-profile "$PROFILE" "$OUT/notarization/$KIND-log.json"
  python3 -c 'import json,sys;s=json.load(open(sys.argv[1]));assert s["status"]=="Accepted" and not s.get("issues"),s.get("issues")' "$OUT/notarization/$KIND-log.json"
  if [[ "$KIND" == app ]]; then ARTIFACT="$APP"; else ARTIFACT="$DMG"; fi
  if [[ "$KIND" == app ]]; then
    shasum -a 256 -c "$OUT/notarization/app-upload.sha256"
    codesign -dv --verbose=4 "$APP" 2>&1 | sed -n 's/^CDHash=//p' > "$OUT/notarization/app-current-cdhash.txt"
    cmp "$OUT/notarization/app-cdhash.txt" "$OUT/notarization/app-current-cdhash.txt"
    xcrun stapler staple "$ARTIFACT"
  elif [[ -f "$OUT/notarization/dmg-stapled.sha256" ]]; then
    shasum -a 256 -c "$OUT/notarization/dmg-stapled.sha256"
  else
    shasum -a 256 -c "$OUT/notarization/dmg-upload.sha256"
    xcrun stapler staple "$ARTIFACT"
    shasum -a 256 "$DMG" > "$OUT/notarization/dmg-stapled.sha256"
  fi
  xcrun stapler validate "$ARTIFACT"
  if [[ "$KIND" == app ]]; then
    python3 script/verify_release.py "$APP"
    spctl --assess --type execute --verbose=4 "$APP"
    syspolicy_check distribution "$APP"
  else
    codesign --verify --strict "$DMG"
    hdiutil verify "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG"
    python3 script/verify_dmg.py "$APP" "$DMG" --notarized
    shasum -a 256 "$DMG" > "$OUT/Commander4Mac-1.0.dmg.sha256"
  fi;;
 *) echo "Unknown action: $ACTION" >&2; exit 2;;
esac
