#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
BUNDLE="CommanderCoreTests"
SCHEME="CommanderCore"
ACTION="build-for-testing"
if [[ "${1:-}" == "--ui" ]]; then BUNDLE="Commander4MacUITests"; SCHEME="Commander4Mac"; ACTION="test"; shift; fi
CONFIGURATION="${COMMANDER_TEST_CONFIGURATION:-Debug}"
if [[ "$BUNDLE" == "Commander4MacUITests" ]]; then CONFIGURATION="UITest"; fi
FILTER="$BUNDLE"
CLASS="${1:-}"
if [[ -n "$CLASS" ]]; then FILTER="$BUNDLE/$CLASS"; fi
mkdir -p .build/logs
xcodegen generate >/dev/null
LOG="$ROOT_DIR/.build/logs/test-$(date +%Y%m%d-%H%M%S).log"
report_failure() {
  python3 - "$LOG" <<'ERRORS'
import sys
from pathlib import Path
lines=Path(sys.argv[1]).read_text().splitlines()
errors=[line for line in lines if "error:" in line or "failed" in line.lower() or "Executed " in line]
print("\n".join(errors[-35:] if errors else lines[-25:]))
ERRORS
  echo "Full log: $LOG" >&2
}
BUILD_COMMAND=(/usr/bin/xcodebuild)
if [[ "$BUNDLE" == "Commander4MacUITests" ]]; then BUILD_COMMAND=(python3 "$ROOT_DIR/script/run_ui_tests.py"); fi
BUILD_COMMAND+=(-project Commander4Mac.xcodeproj -scheme "$SCHEME" -configuration "$CONFIGURATION" -destination 'platform=macOS' -derivedDataPath .build/xcode -onlyUsePackageVersionsFromResolvedFile -only-testing:"$FILTER")
if [[ "${COMMANDER_CI:-0}" == 1 ]]; then BUILD_COMMAND+=(CODE_SIGNING_ALLOWED=NO); fi
BUILD_COMMAND+=("$ACTION")
if ! "${BUILD_COMMAND[@]}" >"$LOG" 2>&1; then
  report_failure; exit 1
fi
if [[ "$BUNDLE" == "CommanderCoreTests" ]]; then
  export DYLD_FRAMEWORK_PATH="$ROOT_DIR/.build/xcode/Build/Products/$CONFIGURATION"
  ARGS=("$ROOT_DIR/.build/xcode/Build/Products/$CONFIGURATION/CommanderCoreTests.xctest")
  if [[ -n "$CLASS" ]]; then ARGS=(-XCTest "CommanderCoreTests.$CLASS" "${ARGS[@]}"); fi
  if ! xcrun xctest "${ARGS[@]}" >>"$LOG" 2>&1; then report_failure; exit 1; fi
fi
tail -n 20 "$LOG"
