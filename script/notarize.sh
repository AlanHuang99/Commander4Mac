#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TASK_ROOT"
ACTION="${1:?usage: notarize.sh app-submit|app-wait|app-finish|dmg-submit|dmg-wait|dmg-finish [keychain-profile]}"
PROFILE="${2:-Commander4Mac-notary}"
KEYCHAIN_OPTIONS=()
if [[ -n "${COMMANDER_NOTARY_KEYCHAIN:-}" ]]; then KEYCHAIN_OPTIONS=(--keychain "$COMMANDER_NOTARY_KEYCHAIN"); fi
OUT="${COMMANDER_DISTRIBUTION_DIR:-$TASK_ROOT/.build/distribution}"
VERSION="$(python3 script/release_metadata.py --field version)"
APP="$OUT/Commander4Mac.xcarchive/Products/Applications/Commander4Mac.app"
DMG="$OUT/Commander4Mac-$VERSION.dmg"
mkdir -p "$OUT/notarization"
case "$ACTION" in
 app-wait|dmg-wait)
  KIND="${ACTION%-wait}"
  ID="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["id"])' "$OUT/notarization/$KIND-submission.json")"
  xcrun notarytool wait "$ID" --keychain-profile "$PROFILE" "${KEYCHAIN_OPTIONS[@]}" --timeout 25m --output-format json > "$OUT/notarization/$KIND-wait.json"
  python3 script/verify_notary_log.py "$OUT/notarization/$KIND-wait.json";;
 app-submit)
  xcrun notarytool history --keychain-profile "$PROFILE" "${KEYCHAIN_OPTIONS[@]}" --output-format json >/dev/null
  python3 script/verify_release.py "$APP"
  test ! -e "$OUT/notarization/app-submission.json" && test ! -e "$OUT/notarization/app-submission.pending" || { echo 'Existing/uncertain submission: inspect its saved ID before retrying.' >&2; exit 2; }
  codesign -dv --verbose=4 "$APP" 2>&1 | sed -n 's/^CDHash=//p' > "$OUT/notarization/app-cdhash.txt"
  test -s "$OUT/notarization/app-cdhash.txt"
  ditto -c -k --keepParent "$APP" "$OUT/Commander4Mac-notarization.zip"
  shasum -a 256 "$OUT/Commander4Mac-notarization.zip" > "$OUT/notarization/app-upload.sha256"
  xcrun notarytool submit "$OUT/Commander4Mac-notarization.zip" --keychain-profile "$PROFILE" "${KEYCHAIN_OPTIONS[@]}" --output-format json > "$OUT/notarization/app-submission.pending"
  mv "$OUT/notarization/app-submission.pending" "$OUT/notarization/app-submission.json"
  cat "$OUT/notarization/app-submission.json";;
 dmg-submit)
  xcrun notarytool history --keychain-profile "$PROFILE" "${KEYCHAIN_OPTIONS[@]}" --output-format json >/dev/null
  xcrun stapler validate "$APP"
  python3 script/verify_release.py "$APP"
  test ! -e "$OUT/notarization/dmg-submission.json" && test ! -e "$OUT/notarization/dmg-submission.pending" || { echo 'Existing/uncertain submission: inspect its saved ID before retrying.' >&2; exit 2; }
  ./script/build_dmg.sh "$APP" "$DMG"
  shasum -a 256 "$DMG" > "$OUT/notarization/dmg-upload.sha256"
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" "${KEYCHAIN_OPTIONS[@]}" --output-format json > "$OUT/notarization/dmg-submission.pending"
  mv "$OUT/notarization/dmg-submission.pending" "$OUT/notarization/dmg-submission.json"
  cat "$OUT/notarization/dmg-submission.json";;
 app-finish|dmg-finish)
  KIND="${ACTION%-finish}"
  ID="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["id"])' "$OUT/notarization/$KIND-submission.json")"
  xcrun notarytool info "$ID" --keychain-profile "$PROFILE" "${KEYCHAIN_OPTIONS[@]}" --output-format json > "$OUT/notarization/$KIND-status.json"
  STATUS="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["status"])' "$OUT/notarization/$KIND-status.json")"
  echo "$STATUS"
  case "$STATUS" in Accepted|Invalid|Rejected) ;; *) echo 'Submission is not finished. Run this finish action again later.'; exit 2;; esac
  xcrun notarytool log "$ID" --keychain-profile "$PROFILE" "${KEYCHAIN_OPTIONS[@]}" "$OUT/notarization/$KIND-log.json"
  python3 script/verify_notary_log.py "$OUT/notarization/$KIND-log.json"
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
    (cd "$OUT" && shasum -a 256 "Commander4Mac-$VERSION.dmg" > "Commander4Mac-$VERSION.dmg.sha256")
  fi;;
 *) echo "Unknown action: $ACTION" >&2; exit 2;;
esac
