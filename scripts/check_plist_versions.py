#!/usr/bin/env python3
"""Reject Info.plist files that hardcode a version instead of referencing the build setting.

A literal here silently wins over MARKETING_VERSION, so the project and the shipped bundle can
disagree. That is how the Quick Look app was still stamped 0.1 after the release had moved on --
a mismatch the notarization broker only caught at signing time, well after CI had gone green.

Invoked by scripts/check-versions.sh. Uses plistlib rather than plutil so it runs on Linux too.
"""

from __future__ import annotations

import pathlib
import plistlib
import sys

EXPECTED = {
    "CFBundleShortVersionString": "$(MARKETING_VERSION)",
    "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
}
SOURCE_ROOTS = ("printfilemanager/Sources", "Quicklook/Sources")


def main() -> int:
    ok = True
    checked = 0
    for root in SOURCE_ROOTS:
        for plist in sorted(pathlib.Path(root).rglob("Info.plist")):
            with plist.open("rb") as handle:
                contents = plistlib.load(handle)
            checked += 1
            for key, placeholder in EXPECTED.items():
                value = contents.get(key)
                if value is not None and value != placeholder:
                    print(f"error: {plist} hardcodes {key} ({value}).", file=sys.stderr)
                    print(
                        f"       Use {placeholder} so the project stays the single source.",
                        file=sys.stderr,
                    )
                    ok = False
    if checked == 0:
        print("error: no Info.plist files found; the check would pass vacuously.", file=sys.stderr)
        return 1
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
