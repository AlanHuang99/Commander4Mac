"""Offscreen AppKit regressions using production classes and injected boundaries."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class NativeAppTests(unittest.TestCase):
    def probe(self, source, probe, extra=()):
        with tempfile.TemporaryDirectory(prefix="c4m-native-probe-") as directory:
            root = Path(directory); implementation = root / "Implementation.swift"
            implementation.write_text(source)
            binary = root / "probe"
            built = subprocess.run(["xcrun", "swiftc", "-swift-version", "6", str(implementation),
                                    str(ROOT / "Tests/NativeProbes" / probe), *map(str, extra), "-o", str(binary)], capture_output=True, text=True)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_last_visible_column_is_reachable_at_every_size(self):
        path = ROOT / "Sources/Commander4Mac/Views/FileTable/CommanderScrollView.swift"
        self.probe(path.read_text(), "NativeTableGeometryProbe.swift")

    def test_actual_app_delegate_reports_failed_quit_and_allows_retry(self):
        source = (ROOT / "Sources/Commander4Mac/App/AppDelegate.swift").read_text()
        # CommanderCore's worker is replaced at this boundary; the AppDelegate
        # implementation itself is compiled unchanged with failure-injected services.
        self.probe(source.replace("import CommanderCore\n", ""), "TerminationFailureProbe.swift",
                   [ROOT / "Sources/CommanderCore/Services/UpdateRelaunchCoordinator.swift"])


if __name__ == "__main__": unittest.main()
