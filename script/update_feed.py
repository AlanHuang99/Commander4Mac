#!/usr/bin/env python3
"""Generate with pinned Sparkle tools and verify a GitHub release appcast."""
import argparse
import base64
import hashlib
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

from release_metadata import release_metadata

ROOT = Path(__file__).resolve().parents[1]
SPARKLE_NS = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
RELEASES = "https://github.com/AlanHuang99/Commander4Mac/releases"
ET.register_namespace("sparkle", SPARKLE_NS[1:-1])


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sparkle_tools():
    tools = ROOT / ".build/xcode/SourcePackages/artifacts/sparkle/Sparkle/bin"
    require(all((tools / name).is_file() for name in ["sign_update", "generate_appcast"]),
            "Pinned Sparkle tools are missing. Run script/resolve_dependencies.sh first.")
    return tools


def public_key():
    return plistlib.loads((ROOT / "Configuration/Info.plist").read_bytes())["SUPublicEDKey"]


def signature_verifier():
    source = ROOT / "script/verify_update_signature.swift"
    output = ROOT / ".build/tools" / ("verify-update-" + hashlib.sha256(source.read_bytes()).hexdigest()[:16])
    if not output.is_file():
        output.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="verify-update-", dir=output.parent) as directory:
            temporary = Path(directory) / "verify"
            result = subprocess.run(["xcrun", "swiftc", "-O", str(source), "-o", str(temporary)], capture_output=True)
            require(result.returncode == 0, "Could not build the CryptoKit public-signature verifier")
            temporary.replace(output)
    return output


def verify_signature(data, signature, key):
    try:
        require(len(base64.b64decode(key, validate=True)) == 32, "Invalid public signature key")
        require(len(base64.b64decode(signature, validate=True)) == 64, "Invalid Ed25519 signature")
    except (ValueError, TypeError) as error:
        raise ValueError("Invalid signature or public key encoding") from error
    verifier = signature_verifier()
    with tempfile.TemporaryDirectory(prefix="c4m-signature-") as directory:
        content = Path(directory) / "content"
        content.write_bytes(data)
        result = subprocess.run([str(verifier), key, str(content), signature], capture_output=True)
    require(result.returncode == 0, "Ed25519 signature verification failed")


def preflight_signing_key(key_file, key, tools):
    key_file = Path(key_file)
    require(key_file.is_file() and key_file.stat().st_mode & 0o077 == 0, "A private signing-key file readable only by its owner is required")
    with tempfile.TemporaryDirectory(prefix="c4m-key-check-") as directory:
        challenge = Path(directory) / "challenge"
        data = os.urandom(64); challenge.write_bytes(data)
        result = subprocess.run([str(tools / "sign_update"), "--ed-key-file", str(key_file), "-p", str(challenge)], capture_output=True, text=True)
        require(result.returncode == 0, "The private update signing key could not sign the verification challenge")
        verify_signature(data, result.stdout.strip(), key)


def validated_metadata(metadata):
    require(re.fullmatch(r"[0-9]+\.[0-9]+(?:\.[0-9]+)?", metadata.get("version", "")) is not None, "Invalid release version")
    require(re.fullmatch(r"[1-9][0-9]*", metadata.get("build", "")) is not None, "Invalid release build")
    require(metadata.get("tag") == "v" + metadata["version"], "Release tag/version mismatch")


def verify_feed(feed, archive, metadata, key):
    validated_metadata(metadata)
    archive = Path(archive); feed = Path(feed)
    expected_name = "Commander4Mac-" + metadata["version"] + ".dmg"
    require(archive.is_file() and archive.name == expected_name, "Archive filename does not match release version")
    require(feed.is_file() and feed.stat().st_size <= 2 * 1024 * 1024, "Update feed is absent or too large")
    signed = feed.read_bytes()
    block = re.search(rb"<!-- sparkle-signatures:\nedSignature: ([A-Za-z0-9+/=]+)\nlength: ([0-9]+)\n-->\n\Z", signed)
    require(block is not None, "Missing signed feed signature block")
    length = int(block[2]); require(length == block.start(), "Invalid signed feed content length")
    content = signed[:length]
    verify_signature(content, block[1].decode("ascii"), key)
    require(b"<!DOCTYPE" not in content.upper() and b"<!ENTITY" not in content.upper(), "DTD/entity declarations are not allowed in the release feed")
    try:
        document = ET.fromstring(content)
    except ET.ParseError as error:
        raise ValueError("Malformed update feed XML") from error
    items = document.findall("./channel/item")
    require(document.tag == "rss" and len(items) == 1, "Release feed must contain exactly one update")
    item = items[0]
    require(item.findtext(SPARKLE_NS + "version") == metadata["build"], "Feed build does not match release")
    require(item.findtext(SPARKLE_NS + "shortVersionString") == metadata["version"], "Feed version does not match release")
    require(item.findtext(SPARKLE_NS + "minimumSystemVersion") == "15.0", "Feed minimum macOS does not match release")
    enclosures = item.findall("enclosure")
    require(len(enclosures) == 1, "Feed must have one full archive enclosure")
    enclosure = enclosures[0]
    expected_url = RELEASES + "/download/" + metadata["tag"] + "/" + expected_name
    require(enclosure.get("url") == expected_url, "Archive URL does not match GitHub release")
    data = archive.read_bytes()
    require(enclosure.get("length") == str(len(data)), "Feed archive length does not match final bytes")
    require(enclosure.get("type") == "application/octet-stream", "Unexpected archive content type")
    verify_signature(data, enclosure.get(SPARKLE_NS + "edSignature"), key)
    return {**metadata, "length": len(data), "archiveSHA256": hashlib.sha256(data).hexdigest(), "url": expected_url}


def generate_feed(app, archive, output, key_file, notes=None):
    metadata = release_metadata()
    info = plistlib.loads((Path(app) / "Contents/Info.plist").read_bytes())
    require(info.get("CFBundleIdentifier") == "com.alanhuang.Commander4Mac", "Expected a production release bundle")
    for field, expected in [("CFBundleShortVersionString", metadata["version"]), ("CFBundleVersion", metadata["build"]),
                            ("LSMinimumSystemVersion", "15.0"), ("SUPublicEDKey", public_key())]:
        require(info.get(field) == expected, "App metadata does not match release: " + field)
    require(info.get("SURequireSignedFeed") is True and info.get("SUVerifyUpdateBeforeExtraction") is True,
            "App must require signed feeds and verify updates before extraction")
    tools = sparkle_tools(); preflight_signing_key(key_file, public_key(), tools)
    archive = Path(archive).resolve(); output = Path(output).resolve(); output.parent.mkdir(parents=True, exist_ok=True)
    require(archive.name == "Commander4Mac-" + metadata["version"] + ".dmg", "Archive filename does not match release")
    with tempfile.TemporaryDirectory(prefix=".c4m-appcast-", dir=output.parent) as directory:
        stage = Path(directory); staged_archive = stage / archive.name
        # Only the final DMG enters the generator, never notarization zips or source kits.
        shutil.copy2(archive, staged_archive)
        if notes: (stage / (archive.stem + ".md")).write_text(Path(notes).read_text())
        generated = stage / "appcast.xml"
        command = [str(tools / "generate_appcast"), "--ed-key-file", str(Path(key_file).resolve()),
                   "--download-url-prefix", RELEASES + "/download/" + metadata["tag"] + "/",
                   "--link", RELEASES + "/tag/" + metadata["tag"], "--versions", metadata["build"],
                   "--maximum-versions", "1", "--maximum-deltas", "0", "--embed-release-notes", "-o", str(generated), str(stage)]
        result = subprocess.run(command, capture_output=True, text=True)
        require(result.returncode == 0, "Sparkle appcast generation failed: " + (result.stderr + result.stdout)[-1800:])
        receipt = verify_feed(generated, archive, metadata, public_key())
        # Independently ask Sparkle's official tool to validate its signed XML too.
        result = subprocess.run([str(tools / "sign_update"), "--verify", "--ed-key-file", str(Path(key_file).resolve()), str(generated)], capture_output=True)
        require(result.returncode == 0, "Sparkle rejected its signed update feed")
        generated.replace(output)
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["check-key", "generate", "verify"])
    parser.add_argument("--app", type=Path); parser.add_argument("--archive", type=Path)
    parser.add_argument("--feed", type=Path); parser.add_argument("--key-file", type=Path); parser.add_argument("--notes", type=Path)
    args = parser.parse_args()
    try:
        if args.action == "check-key":
            require(args.key_file is not None, "--key-file is required")
            preflight_signing_key(args.key_file, public_key(), sparkle_tools())
            print("Update signing key matches the release public key.")
        elif args.action == "generate":
            require(all([args.app, args.archive, args.feed, args.key_file]), "--app, --archive, --feed and --key-file are required")
            receipt = generate_feed(args.app, args.archive, args.feed, args.key_file, args.notes)
            print(f"Verified signed update feed: {receipt['version']} build{receipt['build']}, {receipt['length']} archive bytes.")
        else:
            require(args.feed is not None and args.archive is not None, "--feed and --archive are required")
            receipt = verify_feed(args.feed, args.archive, release_metadata(), public_key())
            print(f"Verified public feed and archive signature: {receipt['archiveSHA256']}")
    except (ValueError, OSError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
