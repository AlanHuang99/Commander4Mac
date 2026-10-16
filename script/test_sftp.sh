#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TASK_ROOT"
mkdir -p .build
FIXTURE_ROOT="$(mktemp -d "$TASK_ROOT/.build/sftp-fixture.XXXXXX")"
SERVER_PID=""
cleanup() {
  if [[ -n "$SERVER_PID" ]]; then kill "$SERVER_PID" 2>/dev/null || true; wait "$SERVER_PID" 2>/dev/null || true; fi
  if [[ "${COMMANDER_KEEP_SFTP_FIXTURE:-0}" != 1 ]]; then rm -rf "$FIXTURE_ROOT"; fi
}
trap cleanup EXIT
/usr/bin/ssh-keygen -q -t ed25519 -N '' -f "$FIXTURE_ROOT/host_key"
/usr/bin/ssh-keygen -q -t ed25519 -N '' -f "$FIXTURE_ROOT/user_key"
mkdir "$FIXTURE_ROOT/data"
printf 'SFTP fixture' > "$FIXTURE_ROOT/data/hello.txt"
python3 - "$FIXTURE_ROOT" <<'PY'
from pathlib import Path
import socket,json,getpass,sys,shlex
root=Path(sys.argv[1])
with socket.socket() as s:
    s.bind(('127.0.0.1',0)); port=s.getsockname()[1]
(root/'fixture.json').write_text(json.dumps({'port':port,'username':getpass.getuser()}))
oversized=Path('Tests/Support/Network/sftp_oversized.py').resolve()
(root/'sftp-wrapper').write_text('#!/bin/sh\nif [ -f ' + shlex.quote(str(root/'oversize-packets')) + ' ]; then\n exec ' + shlex.quote(sys.executable) + ' ' + shlex.quote(str(oversized)) + '\nfi\nexec /usr/libexec/sftp-server -e -l DEBUG3 2>>' + shlex.quote(str(root/'sftp-events.log')) + '\n')
(root/'sftp-wrapper').chmod(0o700)
(root/'sshd_config').write_text(f'''Port {port}
ListenAddress 127.0.0.1
HostKey "{root}/host_key"
PidFile "{root}/sshd.pid"
AuthorizedKeysFile "{root}/user_key.pub"
StrictModes no
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM no
UseDNS no
PermitRootLogin no
AllowUsers {getpass.getuser()}
Subsystem sftp "{root}/sftp-wrapper"
LogLevel ERROR
''')
PY
/usr/sbin/sshd -D -e -f "$FIXTURE_ROOT/sshd_config" > "$FIXTURE_ROOT/server.log" 2>&1 &
SERVER_PID=$!
python3 - "$FIXTURE_ROOT" "$SERVER_PID" <<'PY'
import json,socket,time,sys,os
from pathlib import Path
root=Path(sys.argv[1]); port=json.loads((root/'fixture.json').read_text())['port']
for _ in range(100):
    try:
        with socket.create_connection(('127.0.0.1',port),timeout=.1):break
    except OSError:
        try:os.kill(int(sys.argv[2]),0)
        except ProcessLookupError:raise SystemExit((root/'server.log').read_text())
        time.sleep(.05)
else:raise SystemExit('Loopback SSH fixture did not start')
PY
if [[ "${COMMANDER_SFTP_SERVE_ONLY:-0}" == 1 ]]; then
  echo "Loopback SFTP fixture: $FIXTURE_ROOT"
  wait "$SERVER_PID"
else
  COMMANDER_SFTP_FIXTURE="$FIXTURE_ROOT" ./script/test.sh SFTPIntegrationTests
fi
