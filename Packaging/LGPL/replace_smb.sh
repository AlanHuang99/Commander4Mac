#!/usr/bin/env bash
set -euo pipefail
APP="${1:?usage: replace_smb.sh /path/to/personal-copy.app /path/to/rebuilt/AMSMB2}"
LIBRARY="${2:?missing rebuilt library}"
python3 - "$APP" "$LIBRARY" <<'PYTHON'
from pathlib import Path
import plistlib,subprocess,sys
app=Path(sys.argv[1]).resolve(strict=True); library=Path(sys.argv[2]).resolve(strict=True)
for installed in [Path('/Applications'),Path.home()/'Applications']:
    if app.is_relative_to(installed):raise SystemExit('Work on a separate personal copy outside Applications.')
info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
if info.get('CFBundleIdentifier') != 'com.alanhuang.Commander4Mac':raise SystemExit('Expected a personal copy of Commander4Mac.')
for item in (app/'Contents/Frameworks').iterdir():
    if not item.resolve().is_relative_to(app):raise SystemExit('Framework path escapes the personal app copy.')
executable=str(app/'Contents/MacOS'/info['CFBundleExecutable'])
for pid in subprocess.run(['pgrep','-x','Commander4Mac'],capture_output=True,text=True).stdout.split():
    running=subprocess.check_output(['ps','-p',pid,'-o','comm='],text=True).strip()
    if running==executable:raise SystemExit('Quit this personal copy before replacing its library.')
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
subprocess.run(['lipo','-verify_arch',subprocess.check_output(['uname','-m'],text=True).strip(),str(library)],check=True)
if '_smb2_init_context' not in subprocess.check_output(['nm','-gU',str(library)],text=True):raise SystemExit('Not an AMSMB2 replacement library.')
PYTHON
APP="$(cd "$APP" && pwd -P)"
cp "$LIBRARY" "$APP/Contents/Frameworks/AMSMB2.framework/Versions/A/AMSMB2"
# Sign only the personal modified copy. The distributed app is never changed.
while IFS= read -r -d '' item; do
  /usr/bin/codesign --force --sign - --timestamp=none "$item"
done < <(find "$APP/Contents/Frameworks" -maxdepth 1 \( -name '*.framework' -o -name '*.dylib' \) -print0)
/usr/bin/codesign --force --sign - --timestamp=none "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"
echo 'Personal copy re-signed. Original Developer ID notarization no longer applies to this modified copy.'
