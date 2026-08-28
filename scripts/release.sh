#!/usr/bin/env bash
#
# Builds, signs, notarizes and packages the two apps for distribution.
#
# Quick Look extensions will not load on a machine other than the one that built them unless they
# are signed, and macOS will refuse to open an unnotarized download, so this is the only supported
# way to hand either app to someone else.
#
# Prerequisites:
#   * A "Developer ID Application" certificate in the login keychain.
#   * A notarytool keychain profile. Create one once with:
#       xcrun notarytool store-credentials "printfilemanager" \
#         --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-password"
#
# Usage:
#   scripts/release.sh                       # sign and notarize both apps
#   scripts/release.sh --skip-notarize       # sign only, for local verification
#
set -euo pipefail

TEAM_ID="${TEAM_ID:-}"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"
NOTARY_PROFILE="${NOTARY_PROFILE:-printfilemanager}"
SKIP_NOTARIZE=0

for arg in "$@"; do
  case "$arg" in
    --skip-notarize) SKIP_NOTARIZE=1 ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/.release"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

if ! security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
  echo "error: no '$SIGN_IDENTITY' certificate found in the keychain." >&2
  echo "       Add one in Xcode under Settings > Accounts > Manage Certificates." >&2
  exit 1
fi

build_and_sign() {
  local project_dir="$1" project="$2" scheme="$3" app_name="$4"

  echo "==> Building $scheme"
  (cd "$REPO_ROOT/$project_dir" && xcodegen generate --quiet)

  xcodebuild archive \
    -project "$REPO_ROOT/$project_dir/$project" \
    -scheme "$scheme" \
    -configuration Release \
    -destination 'platform=macOS' \
    -archivePath "$BUILD_DIR/$scheme.xcarchive" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    ${TEAM_ID:+DEVELOPMENT_TEAM="$TEAM_ID"} \
    OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime"

  local app="$BUILD_DIR/$scheme.xcarchive/Products/Applications/$app_name"
  [ -d "$app" ] || { echo "error: archive did not produce $app_name" >&2; exit 1; }
  cp -R "$app" "$BUILD_DIR/"

  echo "==> Verifying signature of $app_name"
  # --deep checks the embedded appex bundles too, which is the part that actually has to be
  # valid for Quick Look to load them.
  codesign --verify --deep --strict --verbose=2 "$BUILD_DIR/$app_name"
}

notarize() {
  local app_name="$1"
  local zip_path="$BUILD_DIR/${app_name%.app}.zip"

  echo "==> Notarizing $app_name"
  ditto -c -k --keepParent "$BUILD_DIR/$app_name" "$zip_path"
  xcrun notarytool submit "$zip_path" --keychain-profile "$NOTARY_PROFILE" --wait

  echo "==> Stapling $app_name"
  xcrun stapler staple "$BUILD_DIR/$app_name"
  xcrun stapler validate "$BUILD_DIR/$app_name"

  # Re-zip after stapling so the artifact carries the ticket.
  rm -f "$zip_path"
  ditto -c -k --keepParent "$BUILD_DIR/$app_name" "$zip_path"
  echo "==> Ready: $zip_path"
}

build_and_sign "printfilemanager" "PrintFileManager.xcodeproj" "PrintFileManager" "PrintFileManager.app"
build_and_sign "Quicklook" "ThreeMFQuickLook.xcodeproj" "ThreeMFQuickLook" "ThreeMFQuickLook.app"

if [ "$SKIP_NOTARIZE" -eq 1 ]; then
  echo "==> Skipping notarization as requested. The apps are signed but not distributable."
  exit 0
fi

notarize "PrintFileManager.app"
notarize "ThreeMFQuickLook.app"

echo
echo "Done. Artifacts are in $BUILD_DIR."
echo "Install ThreeMFQuickLook.app into /Applications and launch it once so the Quick Look"
echo "extensions register, then run: qlmanage -r && qlmanage -r cache"
