"""Verify actual Sparkle signatures and release-feed publication gates."""
import base64
import hashlib
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "script"))
from update_feed import SPARKLE_NS, sparkle_tools, verify_feed, preflight_signing_key


class UpdateFeedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture = tempfile.TemporaryDirectory(prefix="c4m-update-keys-")
        cls.tools = sparkle_tools()
        cls.keys = []
        for index in range(2):
            key = Path(cls.fixture.name) / f"test-{index}.key"
            key.write_bytes(base64.b64encode(secrets.token_bytes(32))); key.chmod(0o600)
            source = ('import Foundation; import CryptoKit; '
                      'let text = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8); '
                      'let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(base64Encoded: text)!); '
                      'print(key.publicKey.rawRepresentation.base64EncodedString())')
            public = subprocess.check_output(["xcrun", "swift", "-e", source, str(key)], text=True).strip()
            cls.keys.append((key, public))

    @classmethod
    def tearDownClass(cls):
        cls.fixture.cleanup()

    def setUp(self):
        self.fixture_dir = tempfile.TemporaryDirectory(prefix="c4m-feed-")
        self.addCleanup(self.fixture_dir.cleanup)
        self.directory = Path(self.fixture_dir.name)
        self.archive = self.directory / "Commander4Mac-1.1.dmg"
        self.archive.write_bytes(b"Owned archive bytes for signature regression tests")
        self.feed = self.directory / "appcast.xml"
        self.metadata = {"version": "1.1", "build": "2", "tag": "v1.1"}

    def signed_feed(self, changes=None, key_index=0):
        key, _ = self.keys[key_index]
        signature = subprocess.check_output([str(self.tools / "sign_update"), "--ed-key-file", str(key), "-p", str(self.archive)], text=True).strip()
        values = {"version": "1.1", "build": "2", "minimum": "15.0", "length": str(self.archive.stat().st_size),
                  "url": "https://github.com/AlanHuang99/Commander4Mac/releases/download/v1.1/Commander4Mac-1.1.dmg"}
        values.update(changes or {})
        rss = ET.Element("rss", version="2.0"); channel = ET.SubElement(rss, "channel")
        ET.SubElement(channel, "title").text = "Owned update test"
        item = ET.SubElement(channel, "item")
        ET.SubElement(item, SPARKLE_NS + "version").text = values["build"]
        ET.SubElement(item, SPARKLE_NS + "shortVersionString").text = values["version"]
        ET.SubElement(item, SPARKLE_NS + "minimumSystemVersion").text = values["minimum"]
        ET.SubElement(item, "enclosure", {"url": values["url"], "length": values["length"], "type": "application/octet-stream", SPARKLE_NS + "edSignature": signature})
        ET.ElementTree(rss).write(self.feed, encoding="UTF-8", xml_declaration=True)
        subprocess.run([str(self.tools / "sign_update"), "--ed-key-file", str(key), str(self.feed)], check=True, capture_output=True)

    def verify(self):
        return verify_feed(self.feed, self.archive, self.metadata, self.keys[0][1])

    def test_valid_feed_matches_release_and_final_archive_bytes(self):
        self.signed_feed(); receipt = self.verify()
        self.assertEqual(receipt["version"], "1.1"); self.assertEqual(receipt["build"], "2")
        self.assertEqual(receipt["archiveSHA256"], hashlib.sha256(self.archive.read_bytes()).hexdigest())
        self.assertEqual(receipt["length"], self.archive.stat().st_size)

    def test_correctly_signed_but_wrong_release_metadata_is_rejected(self):
        for changes in [{"version": "1.2"}, {"build": "3"}, {"minimum": "14.0"}, {"length": "1"}, {"url": "https://example.test/update.dmg"}]:
            with self.subTest(changes=changes):
                self.signed_feed(changes)
                with self.assertRaises(ValueError): self.verify()

    def test_archive_tampering_fails_even_when_length_is_unchanged(self):
        self.signed_feed()
        data = self.archive.read_bytes(); self.archive.write_bytes(b"X" + data[1:])
        with self.assertRaisesRegex(ValueError, "signature"): self.verify()

    def test_feed_tampering_and_unsigned_trailing_content_are_rejected(self):
        self.signed_feed(); original = self.feed.read_bytes()
        self.feed.write_bytes(original.replace(b"Owned update test", b"Other update test"))
        with self.assertRaisesRegex(ValueError, "signature"): self.verify()
        self.feed.write_bytes(original + b"<!-- unsigned -->")
        with self.assertRaises(ValueError): self.verify()

    def test_wrong_key_and_missing_key_cannot_publish(self):
        self.signed_feed(key_index=1)
        with self.assertRaisesRegex(ValueError, "signature"): self.verify()
        with self.assertRaises(ValueError): preflight_signing_key(self.directory / "absent.key", self.keys[0][1], self.tools)
        with self.assertRaises(ValueError): preflight_signing_key(self.keys[1][0], self.keys[0][1], self.tools)
        preflight_signing_key(self.keys[0][0], self.keys[0][1], self.tools)

    def test_unsigned_feed_and_malformed_metadata_are_rejected(self):
        self.feed.write_text("<rss><channel/></rss>")
        with self.assertRaises(ValueError): self.verify()
        self.signed_feed(); self.metadata["build"] = "0"
        with self.assertRaises(ValueError): self.verify()


class UpdateCredentialCleanupTests(unittest.TestCase):
    def test_release_key_is_required_before_security_commands_and_removed_on_cleanup(self):
        with tempfile.TemporaryDirectory(prefix="c4m-signing-shell-") as directory:
            root = Path(directory); tools = root / "bin"; tools.mkdir()
            marker = root / "security-called"
            for command in ["security", "xcrun"]:
                path = tools / command
                path.write_text('#!' + sys.executable + '\nfrom pathlib import Path\nimport os\n'
                                'Path(os.environ["SECURITY_MARKER"]).touch()\n')
                path.chmod(0o755)
            environment = {**os.environ, "RUNNER_TEMP": str(root), "SECURITY_MARKER": str(marker),
                           "PATH": str(tools) + os.pathsep + os.environ["PATH"],
                           "MACOS_CERT_P12_BASE64": base64.b64encode(b"owned certificate fixture").decode(),
                           "MACOS_NOTARY_API_KEY_P8_BASE64": base64.b64encode(b"owned notary fixture").decode(),
                           "MACOS_TEAM_ID": "66LBY954DT"}
            for name in ["MACOS_CERT_P12_PASSWORD", "MACOS_KEYCHAIN_PASSWORD", "MACOS_NOTARY_API_KEY_ID", "MACOS_NOTARY_ISSUER_ID"]:
                environment[name] = "owned-fixture"
            environment.pop("SPARKLE_ED_PRIVATE_KEY", None)
            command = ["/bin/bash", str(ROOT / "script/ci_signing.sh")]
            missing = subprocess.run(command + ["setup"], env=environment, capture_output=True, text=True)
            self.assertNotEqual(missing.returncode, 0); self.assertIn("SPARKLE_ED_PRIVATE_KEY", missing.stderr)
            self.assertFalse(marker.exists())
            environment["SPARKLE_ED_PRIVATE_KEY"] = base64.b64encode(secrets.token_bytes(32)).decode()
            ready = subprocess.run(command + ["setup"], env=environment, capture_output=True, text=True)
            self.assertEqual(ready.returncode, 0, ready.stderr)
            key = root / "commander-signing/sparkle.key"
            self.assertTrue(key.is_file()); self.assertEqual(key.stat().st_mode & 0o077, 0)
            self.assertNotIn(environment["SPARKLE_ED_PRIVATE_KEY"], ready.stdout + ready.stderr)
            cleaned = subprocess.run(command + ["cleanup"], env=environment, capture_output=True, text=True)
            self.assertEqual(cleaned.returncode, 0, cleaned.stderr)
            self.assertFalse(key.parent.exists())


if __name__ == "__main__":
    unittest.main()
