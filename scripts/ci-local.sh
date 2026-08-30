#!/usr/bin/env bash
#
# Runs the CI pipeline locally.
#
# GitHub Actions cannot run for this repository: it is private, so Actions consume the paid
# quota, and that quota is currently blocked ("recent account payments have failed or your
# spending limit needs to be increased"). Every hosted run has failed before starting a job.
# Until that is resolved this script is the only thing actually validating a change, so it
# performs the same steps as .github/workflows/ci.yml in the same order.
#
# Usage:
#   scripts/ci-local.sh            # everything
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"


# XcodeGen and SwiftPM shell out to git, and this checkout may sit under a git configuration
# that refuses bare repositories, which breaks dependency resolution. Scope the override to
# this script rather than changing the user's global config.
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=safe.bareRepository
export GIT_CONFIG_VALUE_0=all

DERIVED="$(mktemp -d)"
trap 'rm -rf "$DERIVED"' EXIT

FAILURES=()
step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
record_failure() { FAILURES+=("$1"); printf '\033[31mFAILED: %s\033[0m\n' "$1"; }

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: $1 is not installed. Run: brew install $2" >&2
    exit 1
  }
}
require xcodegen xcodegen
require swiftlint swiftlint

step "Lint"
if swiftlint lint --quiet; then
  echo "No lint errors."
else
  record_failure "swiftlint"
fi

run_project() {
  local dir="$1" project="$2" scheme="$3"
  step "$scheme"
  # The committed .xcodeproj is generated from project.yml. Compare against the working tree as
  # it was before regenerating, not against HEAD: when project.yml itself is an uncommitted
  # change, a diff against HEAD is expected and says nothing about drift.
  local before="$DERIVED/$project.before"
  cp "$dir/$project/project.pbxproj" "$before" 2>/dev/null || true
  (cd "$dir" && xcodegen generate --quiet)
  if [ -f "$before" ] && ! diff -q "$before" "$dir/$project/project.pbxproj" >/dev/null; then
    record_failure "$project was stale — regenerating changed it, so commit the regenerated project"
  fi

  local action="test"

  local log="$DERIVED/$scheme.log"
  local status=0
  xcodebuild "$action" \
    -project "$dir/$project" \
    -scheme "$scheme" \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED/$scheme" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGN_IDENTITY="" > "$log" 2>&1 || status=$?

  # The test host emits a lot of unrelated system-daemon chatter, some of which contains the
  # word "error:" and would otherwise be reported as a build problem. Filter on the noise's own
  # markers rather than trying to match only well-formed compiler diagnostics.
  grep -E "error:|warning: .*\.swift|Executed [0-9]+ test|TEST (SUCCEEDED|FAILED)|BUILD (SUCCEEDED|FAILED)" "$log" \
    | grep -v -e appintents -e iOSSimulator -e "\[Connection\]" -e NSCocoaErrorDomain \
              -e autoShortcut -e "Process Instance Registry" -e synchronousRemoteObjectProxy \
    | sort -u || true

  if [ "$status" -ne 0 ]; then
    record_failure "$scheme $action (exit $status, full log: $log)"
    # The log is inside the temp dir, so keep a copy the user can still read afterwards.
    cp "$log" "$REPO_ROOT/ci-local-$scheme.log"
    echo "Full log copied to ci-local-$scheme.log"
  fi

  # The broker compares bundle identity against its profile at signing time, which is far too late
  # to learn about a typo. Check the bundle we just built against the same expectations.
  local profile="$4"
  local built="$DERIVED/$scheme/Build/Products/Debug/$scheme.app"
  [ -d "$built" ] || built="$DERIVED/$scheme/Build/Products/Release/$scheme.app"
  if [ -n "$profile" ] && [ -d "$built" ]; then
    ./scripts/check-broker-profile.py "$profile" "$built" \
      || record_failure "$scheme does not match its notarization broker profile"
  fi
}

step "Version consistency"
./scripts/check-versions.sh || exit 1

step "README badges"
./scripts/badges.py --check || record_failure "README badges are out of date; run scripts/badges.py"

# The enrichment benchmark's discipline metric is the only thing standing between "the prompt never
# invents a source" and a claim nobody checked. A broken version of it survived a review once, so
# it is now checked itself. Offline: no endpoint, no model, no library.
step "Enrichment benchmark metric"
./scripts/bench-enrichment.py --self-test || record_failure "bench-enrichment discipline metric"

run_project "printfilemanager" "PrintFileManager.xcodeproj" "PrintFileManager" "printfilemanager"

step "Conformance record"
if [ -f .github/conformance.yml ]; then
  python3 - <<'PY' || exit 1
import sys, yaml, pathlib
record = yaml.safe_load(pathlib.Path(".github/conformance.yml").read_text())
required = {"standard_version", "assessed_on", "state", "evidence", "criteria"}
missing = required - record.keys()
if missing:
    sys.exit(f"conformance record is missing: {', '.join(sorted(missing))}")
valid = {"pass", "partial", "fail", "na", "unknown"}
bad = {k: v for k, v in record["criteria"].items() if v not in valid}
if bad:
    sys.exit(f"invalid results: {bad}")
if record["state"] == "Healthy" and "fail" in record["criteria"].values():
    sys.exit("state is Healthy while a criterion fails")
counts = {r: list(record["criteria"].values()).count(r) for r in valid if r in record["criteria"].values()}
print(f"{record['state']} — {counts}")
PY
else
  record_failure "no conformance record"
fi

printf '\n'
if [ ${#FAILURES[@]} -eq 0 ]; then
  printf '\033[32mAll checks passed.\033[0m\n'
  exit 0
fi

printf '\033[31m%d check(s) failed:\033[0m\n' "${#FAILURES[@]}"
printf '  - %s\n' "${FAILURES[@]}"
exit 1
