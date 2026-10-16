#!/usr/bin/env python3
"""Validate the actual production bundle, including every nested Mach-O."""
from pathlib import Path
import plistlib
import re
import subprocess
import sys
from release_checks import require, verify_signature_policy
from release_metadata import release_metadata

root = Path(__file__).resolve().parent.parent
app = Path(sys.argv[1]).resolve()
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
metadata = release_metadata()
require(info["CFBundleIdentifier"] == "com.alanhuang.Commander4Mac", "Not a production app")
require(info["CFBundleExecutable"] == "Commander4Mac", 'Release verification failed: info["CFBundleExecutable"] == "Commander4Mac"')
require(info["CFBundleShortVersionString"] == metadata["version"] and info["CFBundleVersion"] == metadata["build"], "Bundle version/build does not match checked-in release metadata")
require(info["LSMinimumSystemVersion"] == "15.0", 'Release verification failed: info["LSMinimumSystemVersion"] == "15.0"')
subprocess.run([sys.executable, str(root / "script/verify_licenses.py"), str(app / "Contents/Resources")], check=True)
require((app / "Contents/Resources/Commander4MacLicense.txt").read_bytes() == (root / "LICENSE").read_bytes(), "App must include its GPL license")
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
    architectures = subprocess.check_output(["lipo", "-archs", str(binary)], text=True).split()
    require({"arm64", "x86_64"}.issubset(architectures), (binary, architectures))
    for architecture in architectures:
        details = subprocess.check_output(["codesign", "-dv", "--verbose=4", "--arch", architecture, str(binary)], stderr=subprocess.STDOUT, text=True)
        entitlement_data = subprocess.run(["codesign", "-d", "--arch", architecture, "--entitlements", ":-", str(binary)], capture_output=True, check=True).stdout
        entitlements = plistlib.loads(entitlement_data) if entitlement_data.strip() else {}
        verify_signature_policy(details, entitlements, main=binary == main.resolve())
    uuids = subprocess.check_output(["dwarfdump", "--uuid", str(binary)], text=True)
    identifiers = re.findall(r"UUID: ([0-9A-F-]{36})", uuids)
    require(len(identifiers) == len(architectures) and len(set(identifiers)) == len(identifiers), binary)
    require("00000000-0000-0000-0000-000000000000" not in identifiers, binary)
core = app / "Contents/Frameworks/CommanderCore.framework/CommanderCore"
library = app / "Contents/Frameworks/AMSMB2.framework/AMSMB2"
linked = subprocess.check_output(["otool", "-L", str(core)], text=True)
require("@rpath/AMSMB2.framework/Versions/A/AMSMB2" in linked, 'Release verification failed: "@rpath/AMSMB2.framework/Versions/A/AMSMB2" in linked')
require("_smb2_init_context" not in subprocess.check_output(["nm", "-gU", str(core)], text=True), 'Release verification failed: "_smb2_init_context" not in subprocess.check_output(["nm", "-gU", str(core)], text=True)')
require("_smb2_init_context" in subprocess.check_output(["nm", "-gU", str(library)], text=True), 'Release verification failed: "_smb2_init_context" in subprocess.check_output(["nm", "-gU", str(library)], text=True)')
print(f"Verified production identity, universal architectures, timestamps, {len(seen)} signed Mach-O files, runtime protections, licenses and dynamic LGPL linkage.")
