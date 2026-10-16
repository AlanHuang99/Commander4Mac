"""Exercise publication inputs and the actual bounded notary command."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PublicationTests(unittest.TestCase):
    def metadata(self, project, *arguments):
        return subprocess.run([sys.executable, str(ROOT / "script/release_metadata.py"),
                               "--project", str(project), *arguments], capture_output=True, text=True)

    def test_current_tag_produces_matching_metadata(self):
        result = self.metadata(ROOT / "project.yml", "--tag", "v1.0")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {"version": "1.0", "build": "1", "tag": "v1.0"})

    def test_other_tag_is_rejected_before_building(self):
        for tag in ["v1.0.1", "main", "v1.0; touch bad", "v1.0\nextra"]:
            with self.subTest(tag=tag):
                result = self.metadata(ROOT / "project.yml", "--tag", tag)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Tag does not match", result.stderr)

    def test_missing_duplicate_or_unsafe_metadata_is_rejected(self):
        for contents in ["CURRENT_PROJECT_VERSION: '1'\n",
                         'MARKETING_VERSION: "1.0"\nMARKETING_VERSION: "1.1"\nCURRENT_PROJECT_VERSION: "1"\n',
                         'MARKETING_VERSION: "../../bad"\nCURRENT_PROJECT_VERSION: "1"\n',
                         'MARKETING_VERSION: "1.0"\nCURRENT_PROJECT_VERSION: "bad"\n']:
            with self.subTest(contents=contents), tempfile.TemporaryDirectory() as directory:
                project = Path(directory) / "project.yml"
                project.write_text(contents)
                result = self.metadata(project)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Invalid release metadata", result.stderr)

    def run_wait(self, status):
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory)
            output = fixture / "release"
            records = output / "notarization"
            records.mkdir(parents=True)
            identifier = "f2be2ce1-7e33-43ab-b606-3ea52b12751f"
            (records / "app-submission.json").write_text(json.dumps({"id": identifier}))
            fake = fixture / "xcrun"
            fake.write_text('#!' + sys.executable + '\nimport json,os,sys\n'
                            'from pathlib import Path\n'
                            'Path(os.environ["WAIT_ARGS"]).write_text(json.dumps(sys.argv[1:]))\n'
                            'print(json.dumps({"status": os.environ["WAIT_STATUS"]}))\n')
            fake.chmod(0o755)
            arguments = fixture / "arguments.json"
            result = subprocess.run([str(ROOT / "script/notarize.sh"), "app-wait", "fixture-profile"],
                env={**os.environ, "PATH": str(fixture) + os.pathsep + os.environ["PATH"],
                     "COMMANDER_DISTRIBUTION_DIR": str(output), "WAIT_ARGS": str(arguments), "WAIT_STATUS": status},
                capture_output=True, text=True)
            self.assertTrue(arguments.exists(), result.stdout + result.stderr)
            invocation = json.loads(arguments.read_text())
            self.assertEqual(invocation[:3], ["notarytool", "wait", identifier])
            self.assertEqual(invocation[invocation.index("--timeout") + 1], "25m")
            self.assertEqual(invocation[invocation.index("--keychain-profile") + 1], "fixture-profile")
            self.assertEqual(json.loads((records / "app-wait.json").read_text())["status"], status)
            return result

    def test_notary_wait_uses_saved_id_and_deadline(self):
        result = self.run_wait("Accepted")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_notary_wait_rejects_invalid_submission(self):
        result = self.run_wait("Invalid")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Notarization was not accepted", result.stderr)


if __name__ == "__main__":
    unittest.main()
