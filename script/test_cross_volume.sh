#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
mkdir -p .build
TASK_FIXTURE_DIR="$(mktemp -d "$ROOT_DIR/.build/cross-volume.XXXXXX")"
MOUNT_PATH="$TASK_FIXTURE_DIR/mount"
mkdir -p "$MOUNT_PATH"
cleanup() {
  if hdiutil detach "$MOUNT_PATH" >"$TASK_FIXTURE_DIR/detach.log" 2>&1; then
    rm -rf "$TASK_FIXTURE_DIR"
  else
    echo "Fixture retained for inspection: $TASK_FIXTURE_DIR" >&2
  fi
}
trap cleanup EXIT
hdiutil create -size 64m -type UDIF -fs APFS -volname Commander4MacFixture "$TASK_FIXTURE_DIR/volume.dmg" >"$TASK_FIXTURE_DIR/create.log" 2>&1 || { cat "$TASK_FIXTURE_DIR/create.log"; exit 1; }
hdiutil attach -nobrowse -mountpoint "$MOUNT_PATH" "$TASK_FIXTURE_DIR/volume.dmg" >"$TASK_FIXTURE_DIR/attach.log" 2>&1 || { cat "$TASK_FIXTURE_DIR/attach.log"; exit 1; }
COMMANDER_TEST_SECOND_VOLUME="$MOUNT_PATH" ./script/test.sh CrossVolumeTests
