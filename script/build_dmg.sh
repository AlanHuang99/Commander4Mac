#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TASK_ROOT"
APP_PATH="${1:-/Applications/Commander4Mac Dev.app}"
DMG_PATH="${2:-$TASK_ROOT/.build/distribution/Commander4Mac-Dev.dmg}"
if [[ ! -x .build/packaging-venv/bin/dmgbuild ]]; then
  echo 'Create .build/packaging-venv and install Packaging/requirements.txt first.' >&2; exit 1
fi
mkdir -p "$(dirname "$DMG_PATH")"
STAGING="$(mktemp -d "$(dirname "$DMG_PATH")/.commander-package.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
STAGED_DMG="$STAGING/Commander4Mac.dmg"
/usr/bin/codesign --verify --deep --strict "$APP_PATH"
xcrun swift Packaging/render_background.swift Packaging
/usr/bin/tiffutil -cathidpicheck Packaging/background.png Packaging/background@2x.png -out Packaging/background.tiff >/dev/null
.build/packaging-venv/bin/dmgbuild -s Packaging/dmg_settings.py -D "app=$APP_PATH" -D "assets=$TASK_ROOT/Packaging" 'Commander4Mac Install' "$STAGED_DMG"
python3 script/verify_dmg.py "$APP_PATH" "$STAGED_DMG"
APP_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP_PATH/Contents/Info.plist")"
/usr/bin/codesign --force --sign 'Developer ID Application' --identifier "$APP_ID.dmg" "$STAGED_DMG"
/usr/bin/codesign --verify --strict "$STAGED_DMG"
/usr/bin/hdiutil verify "$STAGED_DMG" >/dev/null
mv -f "$STAGED_DMG" "$DMG_PATH"
echo "Created signed local preview: $DMG_PATH"
echo 'Image creation does not notarize it. Use script/notarize.sh for production validation.'
