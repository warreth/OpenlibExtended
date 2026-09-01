#!/usr/bin/env python3
"""Regenerates bucket/openlibextended.json from a GitHub release tag.

Downloads the release's Windows installer, computes its SHA-256, and
rewrites the manifest with the new version, URL and hash. Used by the
release workflow (and manually when a release is edited outside CI).

Usage:
    python3 tool/update_scoop_manifest.py TAG [REPO] [--dry-run]

TAG is like 'v1.5.2'; REPO defaults to warreth/OpenlibExtended.
"""

import argparse
import hashlib
import json
import re
import sys
import urllib.request

MANIFEST_PATH = "bucket/openlibextended.json"
ASSET_PATTERN = re.compile(r"openlib-windows-x64-(?P<version>[0-9][^/]*)\.exe$")


def api_json(repo: str, tag: str) -> dict:
    url = f"https://api.github.com/repos/{repo}/releases/tags/{tag}"
    request = urllib.request.Request(url, headers={"User-Agent": "scoop-manifest-updater"})
    with urllib.request.urlopen(request) as response:
        return json.load(response)


def sha256_of(url: str) -> str:
    request = urllib.request.Request(url, headers={"User-Agent": "scoop-manifest-updater"})
    digest = hashlib.sha256()
    with urllib.request.urlopen(request) as response:
        while chunk := response.read(1 << 16):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tag", help="release tag, e.g. v1.5.2")
    parser.add_argument("repo", nargs="?", default="warreth/OpenlibExtended")
    parser.add_argument("--dry-run", action="store_true",
                        help="print the new manifest instead of writing it")
    args = parser.parse_args()

    tag = args.tag.lstrip("v")
    release = api_json(args.repo, f"v{tag}" if not args.tag.startswith("v") else args.tag)
    if "message" in release and "not_found" in str(release.get("message", "")).lower():
        print(f"release {args.tag} not found in {args.repo}", file=sys.stderr)
        return 1

    asset = next(
        (a for a in release["assets"] if ASSET_PATTERN.search(a["name"])), None)
    if asset is None:
        print(f"no 'openlib-windows-x64-*.exe' asset on release {args.tag}",
              file=sys.stderr)
        return 1

    url = asset["browser_download_url"]
    print(f"hashing {url}")
    digest = sha256_of(url)
    print(f"sha256: {digest}")

    with open(MANIFEST_PATH, encoding="utf-8") as handle:
        manifest = json.load(handle)

    manifest["version"] = tag
    arch = manifest["architecture"]["64bit"]
    arch["url"] = url
    arch["hash"] = digest
    manifest["autoupdate"]["architecture"]["64bit"]["url"] = (
        f"https://github.com/{args.repo}/releases/download/"
        f"v$version/openlib-windows-x64-$version.exe"
    )

    rendered = json.dumps(manifest, indent=4, ensure_ascii=False) + "\n"
    if args.dry_run:
        print(rendered)
        return 0
    with open(MANIFEST_PATH, "w", encoding="utf-8") as handle:
        handle.write(rendered)
    print(f"updated {MANIFEST_PATH} for {tag}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
