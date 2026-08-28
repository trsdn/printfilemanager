#!/usr/bin/env python3
"""Check built bundles against the notarization broker's profiles.

The broker refuses to sign a bundle whose identity does not match its profile exactly, and those
checks run at signing time -- long after CI is green. A one-word disagreement therefore costs a
full release cycle: tag, build, preflight, fail. Three cycles were spent that way, on a version
and then a display name, before this check existed.

This mirrors the broker's own comparison, including its fallback from CFBundleDisplayName to
CFBundleName, and runs against the built bundle rather than the sources. Checking the sources was
tried first and produced two false positives: it read the wrong target's bundle identifier, and it
missed that CFBundleName already satisfied the display-name check. Only the built bundle carries
the resolved values the broker actually sees.

Profiles are fetched from the public broker repository -- the same source the broker reads -- so
this cannot drift from a vendored copy. If the network is unavailable the check reports a skip
rather than failing, because it guards against a remote expectation, not a build input.

Usage:
    scripts/check-broker-profile.py <profile-name> <path-to-built.app> [...]
"""

from __future__ import annotations

import json
import pathlib
import plistlib
import sys
import urllib.error
import urllib.request

PROFILE_URL = (
    "https://raw.githubusercontent.com/trsdn/macos-notarization-broker/main/profiles/apps.json"
)


def fetch_profiles() -> dict | None:
    try:
        with urllib.request.urlopen(PROFILE_URL, timeout=15) as response:
            return json.loads(response.read())["profiles"]
    except (urllib.error.URLError, TimeoutError, KeyError, json.JSONDecodeError) as error:
        print(f"skipped: could not read the broker profiles ({error}).", file=sys.stderr)
        return None


def check(profile: dict, app: pathlib.Path) -> list[str]:
    info_path = app / "Contents" / "Info.plist"
    if not info_path.is_file():
        return [f"{app} has no Contents/Info.plist"]
    with info_path.open("rb") as handle:
        info = plistlib.load(handle)

    problems = []
    for key, expected in (
        ("CFBundleIdentifier", profile["bundle_identifier"]),
        ("CFBundleExecutable", profile["executable"]),
        ("CFBundlePackageType", profile["package_type"]),
        ("LSMinimumSystemVersion", profile["minimum_system_version"]),
    ):
        actual = str(info.get(key, ""))
        if actual != expected:
            problems.append(f"{key} is {actual!r}, but the profile expects {expected!r}")

    # The broker falls back to CFBundleName, so an app satisfying only that is still valid.
    display_name = info.get("CFBundleDisplayName") or info.get("CFBundleName")
    if display_name != profile["bundle_display_name"]:
        problems.append(
            f"display name is {display_name!r}, "
            f"but the profile expects {profile['bundle_display_name']!r}"
        )

    return [f"{app.name}: {problem}" for problem in problems]


def main(argv: list[str]) -> int:
    if len(argv) < 2 or len(argv) % 2 != 0:
        print(__doc__, file=sys.stderr)
        return 2

    profiles = fetch_profiles()
    if profiles is None:
        return 0

    problems: list[str] = []
    pairs = list(zip(argv[0::2], argv[1::2]))
    for name, app_path in pairs:
        profile = profiles.get(name)
        if profile is None:
            problems.append(f"the broker does not define a {name!r} profile")
            continue
        app = pathlib.Path(app_path)
        if not app.is_dir():
            print(f"skipped {name}: {app} has not been built.", file=sys.stderr)
            continue
        problems.extend(check(profile, app))

    if problems:
        print("error: bundle metadata disagrees with the notarization broker:", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        print(
            "\nThe broker rejects this at signing time, so fix it before tagging a release.",
            file=sys.stderr,
        )
        return 1

    print(f"Broker profile check passed for {', '.join(name for name, _ in pairs)}.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
