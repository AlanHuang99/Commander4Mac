"""Exercise the real release gate with damaged distribution resources."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import json

ROOT = Path(__file__).resolve().parents[1]


class ReleaseValidationTests(unittest.TestCase):
    def test_development_certificate_is_not_a_distribution_signature(self):
        sys.path.insert(0, str(ROOT / "script"))
        from release_checks import verify_signature_policy
        details = "Authority=Apple Development: Example (66LBY954DT)\nTeamIdentifier=66LBY954DT\nTimestamp=valid timestamp\nCodeDirectory v=20500 flags=0x10000(runtime)\n"
        with self.assertRaises(ValueError):
            verify_signature_policy(details, {}, main=True)

    def test_main_runtime_and_entitlements_are_enforced(self):
        sys.path.insert(0, str(ROOT / "script"))
        from release_checks import verify_signature_policy
        details = "Authority=Developer ID Application: Example (66LBY954DT)\nTeamIdentifier=66LBY954DT\nTimestamp=valid timestamp\nCodeDirectory v=20500 flags=0x0(none)\n"
        with self.assertRaises(ValueError):
            verify_signature_policy(details, {}, main=True)
        verify_signature_policy(details, {}, main=False)
        details = details.replace("0x0(none)", "0x10000(runtime)")
        with self.assertRaises(ValueError):
            verify_signature_policy(details, {"com.apple.security.get-task-allow": True}, main=True)
        verify_signature_policy(details, {}, main=True)

    def test_optimized_python_rejects_invalid_notary_log(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "notary.json"
            path.write_text(json.dumps({"status": "Invalid", "issues": [{"severity": "error"}]}))
            result = subprocess.run([sys.executable, "-O", str(ROOT / "script/verify_notary_log.py"), str(path)], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Notarization was not accepted", result.stderr)

    def test_untracked_and_ignored_swift_inputs_are_rejected(self):
        sys.path.insert(0, str(ROOT / "script"))
        from prepare_licenses import check_checkout
        with tempfile.TemporaryDirectory() as directory:
            checkout = Path(directory)
            (checkout / "Sources").mkdir()
            (checkout / "Sources/Base.swift").write_text("public let base = 1\n")
            (checkout / ".gitignore").write_text("*.ignored.swift\n")
            subprocess.run(["git", "init", "-q", str(checkout)], check=True, capture_output=True)
            subprocess.run(["git", "-C", str(checkout), "add", "."], check=True)
            subprocess.run(["git", "-C", str(checkout), "-c", "user.name=Release Test", "-c", "user.email=test@example.com", "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", "commit", "-qm", "Owned validation fixture"], check=True)
            check_checkout(checkout)
            for filename in ["Extra.swift", "Extra.ignored.swift"]:
                with self.subTest(filename=filename):
                    probe = checkout / "Sources" / filename
                    probe.write_text("public let extra = 1\n")
                    try:
                        with self.assertRaises(RuntimeError):
                            check_checkout(checkout)
                    finally:
                        probe.unlink()

    def test_optimized_python_cannot_skip_missing_attribution(self):
        with tempfile.TemporaryDirectory() as directory:
            resources = Path(directory)
            shutil.copytree(ROOT / "Resources/OpenSource", resources / "OpenSource")
            shutil.copyfile(ROOT / "Resources/ThirdPartyNotices.txt", resources / "ThirdPartyNotices.txt")
            for path in [resources / "ThirdPartyNotices.txt", resources / "OpenSource/ThirdPartyNotices.txt"]:
                path.write_text(path.read_text().replace("This product includes software developed by Niels Provos.", ""))
            result = subprocess.run([sys.executable, str(ROOT / "script/verify_licenses.py"), str(resources)],
                                    env={**os.environ, "PYTHONOPTIMIZE": "1"}, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0, "Optimized Python silently bypassed a release requirement")

    def test_corrupted_source_archive_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            resources = Path(directory)
            shutil.copytree(ROOT / "Resources/OpenSource", resources / "OpenSource")
            shutil.copyfile(ROOT / "Resources/ThirdPartyNotices.txt", resources / "ThirdPartyNotices.txt")
            archive = resources / "OpenSource/LGPL-Sources.tar.gz"
            data = bytearray(archive.read_bytes()); data[len(data) // 2] ^= 1; archive.write_bytes(data)
            result = subprocess.run([sys.executable, str(ROOT / "script/verify_licenses.py"), str(resources)], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Source archive hash mismatch", result.stderr)


if __name__ == "__main__":
    unittest.main()
