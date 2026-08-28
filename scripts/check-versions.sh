#!/usr/bin/env bash
# Both Xcode projects ship together in a single release, and the notarization broker rejects a
# bundle whose CFBundleShortVersionString does not equal the tag. A version that lives in only one
# project, or a plist that carries a literal instead of referencing the build setting, therefore
# fails late -- during signing -- rather than in CI. This check moves that failure forward.
set -euo pipefail

cd "$(dirname "$0")/.."

status=0

version_of() {
  awk -F'"' '/^ *MARKETING_VERSION:/ { print $2; exit }' "$1"
}

app_version="$(version_of printfilemanager/project.yml)"
quicklook_version="$(version_of Quicklook/project.yml)"

if [[ -z "$app_version" || -z "$quicklook_version" ]]; then
  echo "error: MARKETING_VERSION missing from one of the project files." >&2
  echo "  printfilemanager/project.yml: ${app_version:-<none>}" >&2
  echo "  Quicklook/project.yml:        ${quicklook_version:-<none>}" >&2
  status=1
elif [[ "$app_version" != "$quicklook_version" ]]; then
  echo "error: the two projects declare different versions." >&2
  echo "  printfilemanager/project.yml: $app_version" >&2
  echo "  Quicklook/project.yml:        $quicklook_version" >&2
  status=1
fi

if [[ ! "$app_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: MARKETING_VERSION must be a full X.Y.Z semver; the broker rejects anything else." >&2
  echo "  got: $app_version" >&2
  status=1
fi

# A literal here silently overrides the build setting, which is how 0.1 survived into a signed
# bundle after the project had already moved on. Uses plistlib rather than plutil so this check
# also runs on a Linux runner.
if ! python3 scripts/check_plist_versions.py; then
  status=1
fi

if [[ "$status" -eq 0 ]]; then
  echo "Version check passed: both projects declare $app_version."
fi

exit "$status"
