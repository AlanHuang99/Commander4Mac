#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TASK_ROOT"
TAG="${GITHUB_REF_NAME:?Release tag required}"
python3 script/release_metadata.py --tag "$TAG"
VERSION="$(python3 script/release_metadata.py --field version)"
OUT="${COMMANDER_DISTRIBUTION_DIR:-$TASK_ROOT/.build/distribution}"
export COMMANDER_DISTRIBUTION_DIR="$OUT"
if [[ -n "${RUNNER_TEMP:-}" ]]; then export COMMANDER_NOTARY_KEYCHAIN="$RUNNER_TEMP/commander-signing/release.keychain-db"; fi
mkdir -p .build/logs
python3 -m venv .build/packaging-venv
.build/packaging-venv/bin/python -m pip install --disable-pip-version-check -r Packaging/requirements.txt >.build/logs/packaging-install.log 2>&1
./script/build_release.sh
git diff --exit-code -- Resources/OpenSource Resources/ThirdPartyNotices.txt
./script/notarize.sh app-submit
./script/notarize.sh app-wait
./script/notarize.sh app-finish
./script/notarize.sh dmg-submit
./script/notarize.sh dmg-wait
./script/notarize.sh dmg-finish
cp Resources/OpenSource/LGPL-Sources.tar.gz "$OUT/LGPL-Sources.tar.gz"
cp Resources/ThirdPartyNotices.txt "$OUT/ThirdPartyNotices.txt"
python3 - "$OUT" "$VERSION" <<'PY'
from pathlib import Path
import sys
out,version=Path(sys.argv[1]),sys.argv[2]
notes=f'''## Commander4Mac {version}

A native two-pane file manager for macOS 15 or later, universal for Apple Silicon and Intel.

### Install

1. Download `Commander4Mac-{version}.dmg`, open it, and drag Commander4Mac to Applications.
2. Eject the image and open Commander4Mac from Applications.
3. Enable `/Applications/Commander4Mac.app` in System Settings → Privacy & Security → Full Disk Access. Restart if requested.
4. Allow Local Network access when connecting to a local file server.

The app and DMG are signed with Developer ID, notarized by Apple and stapled. The actual packaged app passed signature, license/source, ticket, Gatekeeper and distribution checks before publication. The `.sha256` file verifies the downloaded image.

See the repository README and CHANGELOG for features and current transfer limitations. This is a new file manager; clean-machine onboarding remains a manual acceptance check.

### Source and licenses

Commander4Mac's original code is GPLv3. Dependencies retain their own licenses. The app includes corresponding LGPL source and rebuild/replacement instructions under Commander4Mac → Open Source Components…. The same LGPL source kit and third-party notices are attached to this release. The tagged repository supplies Commander4Mac's source and build instructions.

This product includes software developed by Niels Provos.
'''
(out/'release-notes.md').write_text(notes)
PY
echo "Validated release artifacts: Commander4Mac-$VERSION.dmg and checksum."
