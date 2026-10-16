#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TASK_ROOT"
export COMMANDER_CI=1
mkdir -p .build/logs
./script/resolve_dependencies.sh
python3 script/prepare_licenses.py
python3 script/verify_licenses.py
git diff --exit-code -- Resources/OpenSource Resources/ThirdPartyNotices.txt
python3 -m unittest discover -s Tests -p 'test_*.py' -v
PYTHONOPTIMIZE=1 python3 -m unittest discover -s Tests -p 'test_*.py' -v
./script/test.sh
python3 -m venv .build/network-fixture-venv
.build/network-fixture-venv/bin/python -m pip install --disable-pip-version-check -r Tests/Support/Network/requirements.txt >.build/logs/fixture-install.log 2>&1
./script/test_smb.sh
./script/test_webdav.sh
./script/test_sftp.sh
./script/test_cross_volume.sh
xcodebuild -project Commander4Mac.xcodeproj -scheme Commander4Mac -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath .build/xcode \
  -onlyUsePackageVersionsFromResolvedFile CODE_SIGNING_ALLOWED=NO build >.build/logs/ci-release-build.log 2>&1
APP=.build/xcode/Build/Products/Release/Commander4Mac.app
python3 script/verify_licenses.py "$APP/Contents/Resources"
cmp LICENSE "$APP/Contents/Resources/Commander4MacLicense.txt"
python3 - "$APP" <<'PY'
from pathlib import Path
import subprocess,sys
root=Path(sys.argv[1])
for relative in ['MacOS/Commander4Mac','Frameworks/CommanderCore.framework/CommanderCore','Frameworks/AMSMB2.framework/AMSMB2']:
    binary=root/'Contents'/relative
    architectures=subprocess.check_output(['lipo','-archs',str(binary)],text=True).split()
    if not {'arm64','x86_64'}.issubset(architectures):
        raise SystemExit(f'Missing universal slices: {relative}: {architectures}')
print('Unsigned universal build and native tests passed.')
PY
