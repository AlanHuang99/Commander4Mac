#!/usr/bin/env python3
"""Run the documented preparation entrypoint in a checkout without .build."""
import io
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile

root = Path(__file__).resolve().parent.parent
log_path = root / ".build/logs/release-fresh-cache.log"
with tempfile.TemporaryDirectory(dir=root / ".build", prefix="release-fresh-") as directory:
    checkout = Path(directory)
    data = subprocess.check_output(["git", "-C", str(root), "archive", "HEAD"])
    with tarfile.open(fileobj=io.BytesIO(data)) as archive:
        archive.extractall(checkout, filter="data")
    # Include the current correction pass before it is committed.
    changed = subprocess.check_output(["git", "-C", str(root), "diff", "--name-only", "HEAD", "-z"])
    added = subprocess.check_output(["git", "-C", str(root), "ls-files", "--others", "--exclude-standard", "-z"])
    for name in set((changed + added).decode().split("\0")) - {""}:
        source = root / name; destination = checkout / name
        if source.is_file():
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
        elif destination.is_file():
            destination.unlink()
    if (checkout / ".build").exists():
        raise RuntimeError("Fresh-cache fixture unexpectedly contains build artifacts")
    with log_path.open("w") as log:
        result = subprocess.run(["./script/build_release.sh", "--prepare-only"], cwd=checkout, stdout=log, stderr=log)
    if result.returncode:
        print("\n".join(log_path.read_text().splitlines()[-25:]))
        raise SystemExit(result.returncode)
    if (checkout / "Resources/OpenSource/LGPL-Sources.tar.gz").read_bytes() != (root / "Resources/OpenSource/LGPL-Sources.tar.gz").read_bytes():
        raise RuntimeError("Fresh pinned resolution produced a different source kit")
print("Fresh checkout resolved locked dependencies/submodules and prepared the identical LGPL source kit without an existing project cache.")
