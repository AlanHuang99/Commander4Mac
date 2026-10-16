#!/usr/bin/env python3
"""Fail closed when a source kit or required attribution is absent/corrupt."""
import hashlib
import json
from pathlib import Path, PurePosixPath
import sys
import tarfile

resources = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "Resources"
folder = resources / "OpenSource"
notices = (resources / "ThirdPartyNotices.txt").read_text()
assert "This product includes software developed by Niels Provos." in notices, "Missing BSD advertising attribution"
assert "All advertising materials mentioning features or use of this software" in notices, "Missing embedded Blowfish license"
assert "GNU LESSER GENERAL PUBLIC LICENSE" in notices and "Version 2.1" in notices
assert notices == (folder / "ThirdPartyNotices.txt").read_text()
manifest = json.loads((folder / "SourceManifest.json").read_text())
archive = folder / "LGPL-Sources.tar.gz"
assert hashlib.sha256(archive.read_bytes()).hexdigest() == manifest["archiveSHA256"], "Source archive hash mismatch"
with tarfile.open(archive) as source:
    members = source.getmembers()
    assert len({m.name for m in members}) == len(members), "Duplicate source paths"
    assert {m.name for m in members} == set(manifest["files"]), "Source manifest mismatch"
    for m in members:
        path = PurePosixPath(m.name)
        assert m.isfile() and not path.is_absolute() and ".." not in path.parts
        assert hashlib.sha256(source.extractfile(m).read()).hexdigest() == manifest["files"][m.name], m.name
    for name in ["AMSMB2/Package.swift", "AMSMB2/LICENSE", "AMSMB2/Dependencies/libsmb2/LICENCE-LGPL-2.1.txt", "AMSMB2/Dependencies/libsmb2/lib/init.c", "swift-system/Package.swift", "swift-atomics/Package.swift", "README.txt", "rebuild_smb.sh", "replace_smb.sh"]:
        assert "LGPL-Sources/" + name in manifest["files"], name
components = json.loads((folder / "Dependencies.json").read_text())
assert any(c["name"] == "libsmb2" and c["revision"] == "aedafb2c8742c83188e27841e270fdaad6035d41" for c in components)
assert any(c["name"] == "AMSMB2" and c["revision"] == "90737c486c9d1a6ed1c1d4307060587c7bb0dfec" for c in components)
print(f"Verified licenses, attribution, {len(components)} dependency records and {len(members)} hashed LGPL source files.")
