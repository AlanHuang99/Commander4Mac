#!/usr/bin/env python3
"""Check the actual signed app and installation shortcut in a finished image."""
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile

source, image = map(lambda value: Path(value).resolve(), sys.argv[1:3])
root = Path(__file__).resolve().parent.parent
mount = Path(tempfile.mkdtemp(prefix="dmg-check-", dir=root / ".build"))
device = None

def signature(bundle):
    subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(bundle)], check=True)
    details = subprocess.check_output(
        ["/usr/bin/codesign", "-dv", "--verbose=4", str(bundle)], stderr=subprocess.STDOUT, text=True
    )
    return re.search(r"^CDHash=(.+)$", details, re.M).group(1)

try:
    result = subprocess.check_output([
        "/usr/bin/hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", str(mount), "-plist", str(image)
    ])
    volumes = [entry for entry in plistlib.loads(result)["system-entities"] if "mount-point" in entry]
    assert len(volumes) == 1 and Path(volumes[0]["mount-point"]) == mount
    device = volumes[0]["dev-entry"]
    packaged = mount / source.name
    assert signature(packaged) == signature(source), "Packaged app differs from the signed source"
    assert os.readlink(mount / "Applications") == "/Applications"
    assert (mount / ".DS_Store").is_file(), "Missing Finder window layout"
    print("Verified packaged app signature, source identity, Applications shortcut, and Finder layout.")
finally:
    # Never remove a directory while it is still a mounted filesystem.
    if device is not None or os.path.ismount(mount):
        subprocess.run(["/usr/bin/hdiutil", "detach", device or str(mount)], check=True, stdout=subprocess.DEVNULL)
    mount.rmdir()
