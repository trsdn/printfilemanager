#!/usr/bin/env python3
"""Render the README's static badges from the sources they claim to report.

Two badges previously stated a licence and a minimum macOS version as hardcoded text, served from
a third-party image host. Both are problems the repository standard names directly: a hardcoded
value duplicating a manifest drifts silently (P08), and an externally hosted image observes every
reader of the README (Y02).

So the values are read from the authoritative files -- the licence from `LICENSE`, the minimum
system version from `printfilemanager/project.yml` -- and rendered into SVGs committed beside the
conformance badge. `--check` fails when a rendered badge no longer matches what is committed,
which is what makes drift impossible rather than merely unlikely.

    scripts/badges.py            # write the badges
    scripts/badges.py --check    # fail if they are out of date
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
BADGE_DIR = ROOT / ".github" / "badges"

LABEL_COLOUR = "#24292f"
LICENCE_COLOUR = "#0969da"
PLATFORM_COLOUR = "#1f2328"


def read_licence() -> str:
    text = (ROOT / "LICENSE").read_text(encoding="utf-8")
    first = text.strip().splitlines()[0]
    if "MIT" in first:
        return "MIT"
    raise SystemExit(f"badges: unrecognised licence heading: {first!r}")


def read_minimum_macos() -> str:
    project = (ROOT / "printfilemanager" / "project.yml").read_text(encoding="utf-8")
    match = re.search(r'^\s*MACOSX_DEPLOYMENT_TARGET:\s*"?([0-9.]+)"?\s*$', project, re.MULTILINE)
    if not match:
        raise SystemExit("badges: MACOSX_DEPLOYMENT_TARGET not found in printfilemanager/project.yml")
    # A deployment target of 15.0 is written as "15+" for a reader.
    return match.group(1).split(".")[0] + "+"


def render(label: str, value: str, colour: str) -> str:
    label_width = 7 * len(label) + 16
    value_width = 7 * len(value) + 16
    total = label_width + value_width
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{total}" height="20" \
role="img" aria-label="{label}: {value}">
  <title>{label}: {value}</title>
  <rect width="{label_width}" height="20" rx="3" fill="{LABEL_COLOUR}"/>
  <rect x="{label_width}" width="{value_width}" height="20" rx="3" fill="{colour}"/>
  <rect x="{label_width}" width="4" height="20" fill="{colour}"/>
  <g fill="#ffffff" font-family="DejaVu Sans,Verdana,sans-serif" font-size="11">
    <text x="{label_width / 2}" y="14" text-anchor="middle">{label}</text>
    <text x="{label_width + value_width / 2}" y="14" text-anchor="middle">\
{value}</text>
  </g>
</svg>
"""


def badges() -> dict[pathlib.Path, str]:
    return {
        BADGE_DIR / "license.svg": render("license", read_licence(), LICENCE_COLOUR),
        BADGE_DIR / "platform.svg": render("macOS", read_minimum_macos(), PLATFORM_COLOUR),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail instead of writing")
    arguments = parser.parse_args()

    BADGE_DIR.mkdir(parents=True, exist_ok=True)
    stale = []
    for path, content in badges().items():
        if arguments.check:
            if not path.exists() or path.read_text(encoding="utf-8") != content:
                stale.append(path.relative_to(ROOT))
        else:
            path.write_text(content, encoding="utf-8")

    if stale:
        print(
            "error: these badges no longer match their source: "
            + ", ".join(str(path) for path in stale),
            file=sys.stderr,
        )
        print("Run scripts/badges.py and commit the result.", file=sys.stderr)
        return 1

    print("Badges are in sync." if arguments.check else "Wrote README badges.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
