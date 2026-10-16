#!/usr/bin/env python3
"""Read the release's canonical XcodeGen metadata and validate tag inputs."""
import argparse
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def release_metadata(project=ROOT / "project.yml", tag=None):
    text = Path(project).read_text()
    values = {}
    for key, name, pattern in [("MARKETING_VERSION", "version", r"[0-9]+\.[0-9]+(?:\.[0-9]+)?"),
                               ("CURRENT_PROJECT_VERSION", "build", r"[1-9][0-9]*")]:
        matches = re.findall(r"^\s*" + key + r":\s*[\"']([^\"'\n]+)[\"']\s*$", text, re.M)
        if len(matches) != 1 or not re.fullmatch(pattern, matches[0]):
            raise ValueError(f"Invalid release metadata: exactly one valid {key} is required")
        values[name] = matches[0]
    values["tag"] = "v" + values["version"]
    if tag is not None and tag != values["tag"]:
        raise ValueError("Tag does not match checked-in MARKETING_VERSION")
    return values


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=ROOT / "project.yml")
    parser.add_argument("--tag")
    parser.add_argument("--field", choices=["version", "build", "tag"])
    args = parser.parse_args()
    try:
        values = release_metadata(args.project, args.tag)
    except ValueError as error:
        parser.error(str(error))
    print(values[args.field] if args.field else json.dumps(values))


if __name__ == "__main__":
    main()
