#!/usr/bin/env python3
"""Opt-in real Sparkle probe/install using disposable, separately identified apps."""
import argparse
import functools
import http.server
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import threading
import uuid

from update_feed import ROOT, public_key, sparkle_tools, preflight_signing_key


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--key-file", type=Path, required=True)
    parser.add_argument("--signed-framework", type=Path, required=True,
                        help="Sparkle.framework from the verified Developer ID export")
    parser.add_argument("--identity", default="Developer ID Application: Ao Huang (66LBY954DT)")
    args = parser.parse_args()
    tools = sparkle_tools(); preflight_signing_key(args.key_file, public_key(), tools)
    fixture = Path(tempfile.mkdtemp(prefix="update-install-", dir=ROOT / ".build"))
    log_path = ROOT / ".build/logs/update-install.log"
    identifier = "com.alanhuang.Commander4Mac.updatefixture." + uuid.uuid4().hex
    receipt = {"fixtureIdentifier": identifier, "usesUserApplications": False, "productionNotarizationTest": False}
    server = None
    with log_path.open("w+") as log:
        def run(command, timeout=90, expected=0):
            result = subprocess.run([str(x) for x in command], stdout=log, stderr=log, timeout=timeout)
            log.flush()
            if expected is not None and result.returncode != expected:
                raise RuntimeError(f"Owned update fixture command failed ({Path(str(command[0])).name}, exit{result.returncode}); see {log_path}")
            return result.returncode

        def sign(app):
            run(["codesign", "--force", "--options", "runtime", "--timestamp", "--sign", args.identity, app])
            run(["codesign", "--verify", "--deep", "--strict", app])

        try:
            print("Building pinned upstream sparkle-cli for owned fixture…", flush=True)
            cli_app = fixture / "sparkle.app"; cli_contents = cli_app / "Contents"
            (cli_contents / "MacOS").mkdir(parents=True); (cli_contents / "Frameworks").mkdir()
            run(["ditto", args.signed_framework.resolve(), cli_contents / "Frameworks/Sparkle.framework"])
            headers = ROOT / ".build/xcode/SourcePackages/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64"
            source = ROOT / ".build/xcode/SourcePackages/checkouts/Sparkle/sparkle-cli"
            run(["xcrun", "clang", "-fobjc-arc", "-mmacosx-version-min=15.0", "-F", headers,
                 "-DSPU_OBJC_DIRECT=__attribute__((objc_direct))", "-DSPU_OBJC_DIRECT_MEMBERS=__attribute__((objc_direct_members))",
                 source / "main.m", source / "SPUCommandLineDriver.m", source / "SPUCommandLineUserDriver.m",
                 "-framework", "Cocoa", "-framework", "Sparkle", "-Wl,-rpath,@executable_path/../Frameworks",
                 "-o", cli_contents / "MacOS/sparkle"])
            cli_info = {"CFBundleIdentifier": identifier + ".tool", "CFBundleExecutable": "sparkle", "CFBundleName": "Owned C4M Updater Test",
                        "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0", "CFBundlePackageType": "APPL", "LSMinimumSystemVersion": "15.0"}
            (cli_contents / "Info.plist").write_bytes(plistlib.dumps(cli_info)); sign(cli_app)
            web = fixture / "web"; web.mkdir(); install = fixture / "installed"; install.mkdir(); build = fixture / "new"; build.mkdir()

            class QuietHandler(http.server.SimpleHTTPRequestHandler):
                def log_message(self, *_): pass
            server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(QuietHandler, directory=str(web)))
            thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
            feed_url = f"http://127.0.0.1:{server.server_port}/appcast.xml"

            def make_host(parent, version):
                app = parent / "OwnedUpdateFixture.app"; contents = app / "Contents"; (contents / "MacOS").mkdir(parents=True)
                code = parent / "fixture.c"; code.write_text(f'#include <stdio.h>\nint main(void) {{ puts("owned-fixture-{version}"); return 0; }}\n')
                run(["xcrun", "clang", "-mmacosx-version-min=15.0", code, "-o", contents / "MacOS/Fixture"])
                info = {"CFBundleIdentifier": identifier, "CFBundleExecutable": "Fixture", "CFBundleName": "Owned C4M Update Fixture",
                        "CFBundlePackageType": "APPL", "CFBundleVersion": str(version), "CFBundleShortVersionString": "1." + str(version - 1),
                        "LSMinimumSystemVersion": "15.0", "SUPublicEDKey": public_key(), "SUFeedURL": feed_url,
                        "SUEnableAutomaticChecks": False, "SURequireSignedFeed": True, "SUVerifyUpdateBeforeExtraction": True,
                        "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True}}
                (contents / "Info.plist").write_bytes(plistlib.dumps(info)); sign(app); return app

            old = make_host(install, 1); new = make_host(build, 2)
            archive = web / "OwnedUpdateFixture-2.zip"
            run(["ditto", "-c", "-k", "--keepParent", new, archive])
            run([tools / "generate_appcast", "--ed-key-file", args.key_file.resolve(), "--maximum-deltas", "0", "--versions", "2",
                 "--download-url-prefix", f"http://127.0.0.1:{server.server_port}/", web])
            feed = web / "appcast.xml"; signed_feed = feed.read_bytes()
            cli = cli_contents / "MacOS/sparkle"
            common = [cli, old, "--feed-url", feed_url, "--user-agent-name", "Commander4MacOwnedAcceptance", "--verbose"]
            print("Checking that Sparkle rejects a modified signed feed…", flush=True)
            feed.write_bytes(signed_feed.replace(b"<rss", b" <rss", 1))
            position = log.tell()
            receipt["tamperedFeedExit"] = run(common + ["--probe"], expected=None)
            log.seek(position); rejection = log.read(); log.seek(0, 2)
            if receipt["tamperedFeedExit"] == 0: raise RuntimeError("Sparkle accepted the modified signed feed")
            if not any(word in rejection.lower() for word in ["signature", "signed feed", "validation", "improperly signed"]):
                raise RuntimeError("Negative probe failed for a reason other than signature validation")
            feed.write_bytes(signed_feed)
            print("Probing the signed update…", flush=True)
            receipt["probeExit"] = run(common + ["--probe"])
            print("Installing into the owned fixture path…", flush=True)
            receipt["installExit"] = run(common + ["--application", old, "--check-immediately"])
            installed_info = plistlib.loads((old / "Contents/Info.plist").read_bytes())
            if installed_info["CFBundleVersion"] != "2": raise RuntimeError("Sparkle did not replace the owned old bundle")
            marker = subprocess.check_output([str(old / "Contents/MacOS/Fixture")], text=True).strip()
            if marker != "owned-fixture-2": raise RuntimeError("Installed fixture executable is not the update")
            run(["codesign", "--verify", "--deep", "--strict", old])
            receipt.update({"beforeBuild": "1", "afterBuild": installed_info["CFBundleVersion"], "installedExecutable": marker, "signatureVerified": True})
            (ROOT / ".build/logs/update-install.json").write_text(json.dumps(receipt, indent=2) + "\n")
            print("Owned Sparkle probe/install passed; installed build2 and executable verified.", flush=True)
            register = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
            for app in [old, new, cli_app]: subprocess.run([register, "-u", str(app)], stdout=log, stderr=log)
            shutil.rmtree(fixture)
        except Exception:
            print(f"Owned fixture retained for diagnosis: {fixture}", flush=True)
            raise
        finally:
            if server: server.shutdown(); server.server_close()


if __name__ == "__main__":
    main()
