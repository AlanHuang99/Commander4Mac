#!/usr/bin/env bash
set -euo pipefail
SOURCE_ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_ROOT="${1:?usage: rebuild_smb.sh /absolute/build-directory [arm64|x86_64]}"
ARCH="${2:-$(uname -m)}"
case "$BUILD_ROOT" in /*) ;; *) echo 'Use an absolute build directory.' >&2; exit 2;; esac
case "$ARCH" in arm64|x86_64) ;; *) exit 2;; esac
mkdir -p "$BUILD_ROOT"
test ! -e "$BUILD_ROOT/Sources" || { echo 'Choose a fresh build directory.' >&2; exit 2; }
mkdir "$BUILD_ROOT/Sources"
for package in AMSMB2 swift-system swift-atomics; do
  /usr/bin/ditto "$SOURCE_ROOT/$package" "$BUILD_ROOT/Sources/$package"
done
python3 - "$BUILD_ROOT/Sources/AMSMB2/Package.swift" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1]); s = p.read_text()
s = s.replace('.package(url: "https://github.com/apple/swift-system.git", .upToNextMajor(from: "1.6.4"))', '.package(path: "../swift-system")')
s = s.replace('.package(url: "https://github.com/apple/swift-atomics.git", .upToNextMajor(from: "1.2.0"))', '.package(path: "../swift-atomics")')
p.write_text(s)
PY
swift build --package-path "$BUILD_ROOT/Sources/AMSMB2" --scratch-path "$BUILD_ROOT/Build" -c release --product AMSMB2 --arch "$ARCH"
LIBRARY="$(swift build --package-path "$BUILD_ROOT/Sources/AMSMB2" --scratch-path "$BUILD_ROOT/Build" -c release --product AMSMB2 --arch "$ARCH" --show-bin-path)/libAMSMB2.dylib"
test -n "$LIBRARY"
cp "$LIBRARY" "$BUILD_ROOT/AMSMB2"
/usr/bin/install_name_tool -id '@rpath/AMSMB2.framework/Versions/A/AMSMB2' "$BUILD_ROOT/AMSMB2"
echo "Replacement library: $BUILD_ROOT/AMSMB2 ($ARCH)"
