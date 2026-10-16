#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TASK_ROOT"
if [[ ! -x .build/network-fixture-venv/bin/python ]]; then
  echo 'Create .build/network-fixture-venv and install test dependency impacket from PyPI.' >&2; exit 1
fi
FIXTURE_ROOT="$(mktemp -d "$TASK_ROOT/.build/smb-fixture.XXXXXX")"
SERVER_PID=''
cleanup() {
  if [[ -n "$SERVER_PID" ]]; then kill "$SERVER_PID" 2>/dev/null || true; wait "$SERVER_PID" 2>/dev/null || true; fi
  if mount | rg -F "$FIXTURE_ROOT/mounts/" >/dev/null; then
    echo "Mounted fixture retained for safe manual disconnect: $FIXTURE_ROOT" >&2
  elif [[ "${COMMANDER_KEEP_SMB_FIXTURE:-0}" != 1 ]]; then rm -rf "$FIXTURE_ROOT"; fi
}
trap cleanup EXIT
.build/network-fixture-venv/bin/python Tests/Support/Network/smb_fixture.py "$FIXTURE_ROOT" > "$FIXTURE_ROOT/server.log" 2>&1 &
SERVER_PID=$!
python3 - "$FIXTURE_ROOT" "$SERVER_PID" <<'PY'
from pathlib import Path
import json,os,socket,sys,time
root=Path(sys.argv[1])
for _ in range(100):
    try:
        c=json.loads((root/'fixture.json').read_text())
        with socket.create_connection(('127.0.0.1',c['port']),timeout=.1): break
    except (OSError,ValueError):
        try: os.kill(int(sys.argv[2]),0)
        except ProcessLookupError: raise SystemExit((root/'server.log').read_text())
        time.sleep(.05)
else: raise SystemExit('Owned SMB fixture did not start')
PY
if [[ "${COMMANDER_SMB_SERVE_ONLY:-0}" == 1 ]]; then
  echo "Owned SMB fixture: $FIXTURE_ROOT"
  wait "$SERVER_PID"
else
  COMMANDER_SMB_FIXTURE="$FIXTURE_ROOT" ./script/test.sh SMBIntegrationTests
fi
