#!/usr/bin/env python3
"""Validate the actual production bundle, including every nested Mach-O."""
from pathlib import Path
import plistlib
import re
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
app = Path(sys.argv[1]).resolve()
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
assert info["CFBundleIdentifier"] == "com.alanhuang.Commander4Mac", "Not a production app"
assert info["CFBundleExecutable"] == "Commander4Mac"
assert info["CFBundleShortVersionString"] == "1.0" and info["CFBundleVersion"] == "1"
assert info["LSMinimumSystemVersion"] == "15.0"
subprocess.run([sys.executable, str(root / "script/verify_licenses.py"), str(app / "Contents/Resources")], check=True)
subprocess.run(["codesign", "--verify", "--deep", "--strict", "--all-architectures", str(app)], check=True)
main = app / "Contents/MacOS" / info["CFBundleExecutable"]
magic = {bytes.fromhex(v) for v in ["cffaedfe", "cefaedfe", "cafebabe", "bebafeca", "cafebabf"]}
seen = set()
for candidate in (app / "Contents").rglob("*"):
    if not candidate.is_file() or candidate.is_symlink():
        continue
    with candidate.open("rb") as stream:
        if stream.read(4) not in magic:
            continue
    binary = candidate.resolve()
    if binary in seen:
        continue
    seen.add(binary)
    details = subprocess.check_output(["codesign", "-dv", "--verbose=4", str(binary)], stderr=subprocess.STDOUT, text=True)
    assert "TeamIdentifier=66LBY954DT" in details, binary
    assert re.search(r"^Timestamp=.+", details, re.M), f"Missing secure timestamp: {binary}"
    architectures = subprocess.check_output(["lipo", "-archs", str(binary)], text=True).split()
    assert {"arm64", "x86_64"}.issubset(architectures), (binary, architectures)
    uuids = subprocess.check_output(["dwarfdump", "--uuid", str(binary)], text=True)
    identifiers = re.findall(r"UUID: ([0-9A-F-]{36})", uuids)
    assert len(identifiers) == len(architectures) and len(set(identifiers)) == len(identifiers), binary
    assert "00000000-0000-0000-0000-000000000000" not in identifiers, binary
details = subprocess.check_output(["codesign", "-dv", "--verbose=4", str(app)], stderr=subprocess.STDOUT, text=True)
assert "runtime" in details, "Hardened runtime disabled"
entitlements = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(app)], capture_output=True, check=True).stdout
values = plistlib.loads(entitlements) if entitlements.strip() else {}
for key in ["com.apple.security.get-task-allow", "com.apple.security.cs.disable-library-validation", "com.apple.security.cs.allow-dyld-environment-variables", "com.apple.security.cs.allow-unsigned-executable-memory"]:
    assert not values.get(key), key
core = app / "Contents/Frameworks/CommanderCore.framework/CommanderCore"
library = app / "Contents/Frameworks/AMSMB2.framework/AMSMB2"
linked = subprocess.check_output(["otool", "-L", str(core)], text=True)
assert "@rpath/AMSMB2.framework/Versions/A/AMSMB2" in linked
assert "_smb2_init_context" not in subprocess.check_output(["nm", "-gU", str(core)], text=True)
assert "_smb2_init_context" in subprocess.check_output(["nm", "-gU", str(library)], text=True)
print(f"Verified production identity, universal architectures, timestamps, {len(seen)} signed Mach-O files, runtime protections, licenses and dynamic LGPL linkage.")
