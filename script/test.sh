#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
BUNDLE="CommanderCoreTests"
if [[ "${1:-}" == "--ui" ]]; then BUNDLE="Commander4MacUITests"; shift; fi
FILTER="$BUNDLE"
if [[ -n "${1:-}" ]]; then FILTER="$BUNDLE/$1"; fi
mkdir -p .build/logs
xcodegen generate >/dev/null
LOG="$ROOT_DIR/.build/logs/test-$(date +%Y%m%d-%H%M%S).log"
if /usr/bin/xcodebuild -project Commander4Mac.xcodeproj -scheme Commander4Mac -configuration UITest -destination 'platform=macOS' -derivedDataPath .build/xcode -only-testing:"$FILTER" test >"$LOG" 2>&1; then
  tail -n 24 "$LOG"
else
  python3 - "$LOG" <<'ERRORS'
import sys
from pathlib import Path
lines=Path(sys.argv[1]).read_text().splitlines()
selected=[line for line in lines if "error:" in line or "failed" in line.lower() or "Executed " in line]
print("\n".join(selected[-35:] if selected else lines[-25:]))
ERRORS
  echo "Full log: $LOG" >&2
  exit 1
fi
