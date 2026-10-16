#!/usr/bin/env python3
"""Bound UI runner startup so a broken macOS automation service cannot hang CI."""
import os
import signal
import subprocess
import sys

process = subprocess.Popen(["/usr/bin/xcodebuild", *sys.argv[1:]], start_new_session=True)
try:
    sys.exit(process.wait(timeout=180))
except subprocess.TimeoutExpired:
    print("UI test runner exceeded 180 seconds, including startup. No passing result is inferred.", flush=True)
    os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()
    sys.exit(124)
