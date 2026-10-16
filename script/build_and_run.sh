#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
MODE="${1:-run}"
case "$MODE" in run|--verify|--debug|--logs|--telemetry) ;; *) echo "usage: $0 [--verify|--debug|--logs|--telemetry]" >&2; exit 2;; esac
APP_NAME="Commander4MacDev"
BUNDLE_ID="com.alanhuang.Commander4Mac.dev"
APP_BUNDLE="/Applications/Commander4Mac Dev.app"
export COMMANDER_APP_BUNDLE="$APP_BUNDLE"
python3 - <<'CHECK'
from pathlib import Path
import json,os
p=Path.home()/'Library/Application Support/com.alanhuang.Commander4Mac.dev/active-operation.json'
try:
    m=json.loads(p.read_text())
    if m.get('activeJobs',0)>0:
        os.kill(int(m['pid']),0)
        raise SystemExit('A development file operation is active. Wait for it to finish before rebuilding.')
except (FileNotFoundError,ProcessLookupError,ValueError,KeyError,json.JSONDecodeError):
    pass
CHECK
mkdir -p .build/logs
xcodegen generate >/dev/null
LOG="$ROOT_DIR/.build/logs/build.log"
if ! /usr/bin/xcodebuild -project Commander4Mac.xcodeproj -scheme Commander4Mac -configuration Debug -derivedDataPath .build/xcode build >"$LOG" 2>&1; then tail -n 90 "$LOG"; exit 1; fi
BUILT="$ROOT_DIR/.build/xcode/Build/Products/Debug/$APP_NAME.app"
/usr/bin/codesign --verify --deep --strict "$BUILT"
# Stop only this development executable after a successful build.
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
export COMMANDER_BUILT_APP="$BUILT"
python3 - <<'INSTALL'
from pathlib import Path
import os,plistlib,shutil,uuid
source=Path(os.environ['COMMANDER_BUILT_APP']); destination=Path(os.environ['COMMANDER_APP_BUNDLE'])
expected='com.alanhuang.Commander4Mac.dev'
def identifier(app):
    with (app/'Contents/Info.plist').open('rb') as f:return plistlib.load(f).get('CFBundleIdentifier')
if identifier(source)!=expected:raise SystemExit('Unexpected development build identity')
if destination.exists() and identifier(destination)!=expected:raise SystemExit('Refusing to replace an unrelated installed app')
staging=destination.parent/('.Commander4Mac-'+uuid.uuid4().hex+'.app')
backup=source.parent/'previous-development-app.app'
if backup.exists():
    if identifier(backup)!=expected:raise SystemExit('Unexpected backup identity')
    shutil.rmtree(backup)
shutil.copytree(source,staging,symlinks=True,copy_function=shutil.copy2)
try:
    if destination.exists():destination.rename(backup)
    staging.rename(destination)
except BaseException:
    if backup.exists() and not destination.exists():backup.rename(destination)
    if staging.exists():shutil.rmtree(staging)
    raise
if backup.exists():shutil.rmtree(backup)
INSTALL
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
/usr/bin/open -n "$APP_BUNDLE"
case "$MODE" in
 --verify) sleep 1; pgrep -x "$APP_NAME" >/dev/null; echo "Launched $APP_BUNDLE";;
 --debug) /usr/bin/lldb -n "$APP_NAME";;
 --logs) /usr/bin/log stream --info --style compact --predicate 'process == "Commander4MacDev"';;
 --telemetry) /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.alanhuang.Commander4Mac.dev"';;
esac
