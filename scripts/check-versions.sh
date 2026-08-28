#!/usr/bin/env bash
# The notarization broker rejects a bundle whose CFBundleShortVersionString does not equal the tag,
# and it does that at signing time -- after a tag has been cut. A version that is not full semver,
# or an Info.plist carrying a literal instead of referencing the build setting, therefore fails
# late and expensively. This moves that failure forward.
set -euo pipefail

cd "$(dirname "$0")/.."

status=0

version="$(awk -F'"' '/^ *MARKETING_VERSION:/ { print $2; exit }' printfilemanager/project.yml)"

if [[ -z "$version" ]]; then
  echo "error: MARKETING_VERSION missing from printfilemanager/project.yml." >&2
  status=1
elif [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: MARKETING_VERSION must be a full X.Y.Z semver; the broker rejects anything else." >&2
  echo "  got: $version" >&2
  status=1
fi

# A literal here silently overrides the build setting, which is how 0.1 once survived into a signed
# bundle after the project had already moved on. Uses plistlib rather than plutil so this check
# also runs on a Linux runner.
if ! python3 scripts/check_plist_versions.py; then
  status=1
fi

if [[ "$status" -eq 0 ]]; then
  echo "Version check passed: $version."
fi

exit "$status"
