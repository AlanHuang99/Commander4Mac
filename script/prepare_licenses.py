#!/usr/bin/env python3
"""Prepare exact third-party notices and an offline LGPL source kit."""
import gzip
import hashlib
import io
import json
from pathlib import Path
import re
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parent.parent
CHECKOUTS = ROOT / ".build/xcode/SourcePackages/checkouts"
OUTPUT = ROOT / "Resources/OpenSource"


def revision(path):
    return subprocess.check_output(["git", "-C", str(path), "rev-parse", "HEAD"], text=True).strip()


def tracked(path):
    names = subprocess.check_output(["git", "-C", str(path), "ls-files", "-z"]).decode().split("\0")
    for name in names:
        p = path / name
        if p.is_file():
            if not p.resolve().is_relative_to(path.resolve()):
                raise RuntimeError(f"Source symlink escapes package: {name}")
            yield p, name


def check_checkout(path):
    if subprocess.check_output(["git", "-C", str(path), "status", "--porcelain", "--untracked-files=all"]):
        raise RuntimeError(f"Modified or untracked dependency inputs: {path.name}")
    ignored = subprocess.check_output(["git", "-C", str(path), "ls-files", "--others", "--ignored", "--exclude-standard", "-z"]).decode().split("\0")
    extensions = {".swift", ".c", ".cc", ".cpp", ".cxx", ".h", ".hh", ".hpp", ".hxx", ".m", ".mm", ".s", ".asm", ".inc", ".modulemap"}
    for name in ignored:
        p = Path(name)
        if name and not any(part in {".build", ".swiftpm", ".git"} for part in p.parts) and p.suffix.lower() in extensions:
            raise RuntimeError(f"Ignored build input omitted from pinned source: {path.name}/{name}")


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    pins = json.loads((ROOT / "Commander4Mac.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved").read_text())["pins"]
    components = []
    for pin in pins:
        matches = [p for p in CHECKOUTS.iterdir() if p.name.lower() == pin["identity"]]
        if len(matches) != 1:
            raise RuntimeError(f"Missing checkout: {pin['identity']}")
        path = matches[0]
        if revision(path) != pin["state"]["revision"]:
            raise RuntimeError(f"Unexpected revision: {path.name}")
        check_checkout(path)
        components.append((path.name, path, pin["location"], pin["state"]))
    components.append(("Citadel", ROOT / "Vendor/Citadel", "https://github.com/orlandos-nl/Citadel", {"revision": "ae8562f895de06ccb86fdb1cbb65fd99c8976e12", "patches": "COMMANDER_PATCHES.md"}))
    smb = CHECKOUTS / "AMSMB2/Dependencies/libsmb2"
    expected_smb = subprocess.check_output(["git", "-C", str(CHECKOUTS / "AMSMB2"), "ls-tree", "HEAD", "Dependencies/libsmb2"], text=True).split()[2]
    if revision(smb) != expected_smb:
        raise RuntimeError("Modified or mismatched libsmb2 submodule")
    check_checkout(smb)
    components.append(("libsmb2", smb, "https://github.com/sahlberg/libsmb2", {"revision": expected_smb}))
    sections = ["Commander4Mac third-party software\n\nThis product includes software developed by Niels Provos.\n\nAMSMB2 and libsmb2 are distributed under LGPL 2.1 or later. Complete corresponding source, licenses, and rebuild/replacement instructions accompany this app in Contents/Resources/OpenSource. Open this folder using the app's Open Source Components menu. Personal modification and reverse engineering for debugging modifications to these libraries are permitted. No app terms restrict the rights granted by the third-party licenses.\n"]
    manifest = []
    prefix = re.compile(r"\A(?:\s*(?://[^\n]*(?:\n|$)|/\*[\s\S]*?\*/))+")
    for name, path, url, state in components:
        sections.append(f"\n{name}\nSource: {url}\nRevision: {state['revision']}\n")
        seen = set()
        files = sorted(p for p in path.rglob("*") if p.is_file() and ".git" not in p.parts)
        for p in files:
            title = p.name.lower()
            full_license = title.startswith(("license", "licence", "copying", "notice")) and not title.startswith(("license_header", "licenseheader"))
            if not full_license and p.suffix.lower() not in (".c", ".h", ".cc", ".cpp", ".swift", ".s", ".inc"):
                continue
            value = p.read_text(errors="replace")
            if not full_license:
                m = prefix.match(value)
                value = m.group(0).strip() if m else ""
                if not re.search(r"copyright|redistribution|permission to|licen[cs]e|public domain", value, re.I):
                    continue
            value = value.strip()
            if value and value not in seen:
                sections.append(f"\n{name} / {p.relative_to(path)}\n\n{value}\n")
                seen.add(value)
        manifest.append({"name": name, "source": url, **state})
    notices = "\n".join(sections)
    (ROOT / "Resources/ThirdPartyNotices.txt").write_text(notices)
    (OUTPUT / "ThirdPartyNotices.txt").write_text(notices)
    entries = {}
    for name in ["AMSMB2", "swift-system", "swift-atomics"]:
        for p, relative in tracked(CHECKOUTS / name):
            entries[f"LGPL-Sources/{name}/{relative}"] = p
    for p, relative in tracked(smb):
        entries[f"LGPL-Sources/AMSMB2/Dependencies/libsmb2/{relative}"] = p
    for name in ["rebuild_smb.sh", "replace_smb.sh", "README.txt"]:
        entries[f"LGPL-Sources/{name}"] = ROOT / "Packaging/LGPL" / name
    source_manifest = {name: hashlib.sha256(p.read_bytes()).hexdigest() for name, p in sorted(entries.items())}
    buffer = io.BytesIO()
    with gzip.GzipFile(fileobj=buffer, mode="wb", filename="", mtime=0) as zipped:
        with tarfile.open(fileobj=zipped, mode="w") as archive:
            for name, p in sorted(entries.items()):
                data = p.read_bytes(); info = tarfile.TarInfo(name)
                info.size = len(data); info.mode = 0o755 if p.suffix == ".sh" else 0o644
                archive.addfile(info, io.BytesIO(data))
    data = buffer.getvalue()
    (OUTPUT / "LGPL-Sources.tar.gz").write_bytes(data)
    (OUTPUT / "SourceManifest.json").write_text(json.dumps({"archiveSHA256": hashlib.sha256(data).hexdigest(), "files": source_manifest}, indent=2) + "\n")
    (OUTPUT / "Dependencies.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (OUTPUT / "README.txt").write_text((ROOT / "Packaging/LGPL/README.txt").read_text())
    print(f"Prepared {len(manifest)} component records, {len(entries)} LGPL source files, {len(data)} source archive bytes.")


if __name__ == "__main__":
    main()
