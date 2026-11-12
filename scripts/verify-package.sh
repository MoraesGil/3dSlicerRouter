#!/bin/bash
# Check the actual downloadable files, including the app mounted from the DMG.
set -euo pipefail
cd "$(dirname "$0")/.."

for artifact in 3dSlicerRouter.dmg 3dSlicerRouter.zip SHA256SUMS; do
  [[ -f "build/$artifact" ]] || { echo "missing package: build/$artifact" >&2; exit 1; }
done
(cd build && shasum -a 256 -c SHA256SUMS)
hdiutil verify build/3dSlicerRouter.dmg

EXPECTED_VERSION=$(sed -n 's/.*MARKETING_VERSION: "\([^"]*\)".*/\1/p' project.yml)
[[ -n "$EXPECTED_VERSION" ]]
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/3dslicerrouter-package.XXXXXX")
MOUNT="$TEMP_ROOT/mount"
MOUNTED=false
cleanup() {
  if $MOUNTED; then hdiutil detach "$MOUNT" >/dev/null; fi
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT
mkdir "$MOUNT"
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT" build/3dSlicerRouter.dmg >/dev/null
MOUNTED=true
[[ -L "$MOUNT/Applications" && "$(readlink "$MOUNT/Applications")" == /Applications ]]
[[ -s "$MOUNT/READ ME - LEIA-ME.txt" ]]

verify_app() {
  local app_bundle="$1"
  codesign --verify --deep --strict "$app_bundle"
  [[ "$("$app_bundle/Contents/MacOS/3dSlicerRouter" --version)" == "$EXPECTED_VERSION" ]]
  for bundle_info in "$app_bundle/Contents/Info.plist" "$app_bundle"/Contents/PlugIns/*.appex/Contents/Info.plist; do
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$bundle_info")" == "$EXPECTED_VERSION" ]]
  done
  for binary in "$app_bundle/Contents/MacOS/3dSlicerRouter" \
      "$app_bundle/Contents/Helpers/3dSlicerIndexer" \
      "$app_bundle"/Contents/PlugIns/*.appex/Contents/MacOS/*; do
    lipo "$binary" -verify_arch arm64 x86_64
  done
}
verify_app "$MOUNT/3dSlicerRouter.app"
ditto -x -k build/3dSlicerRouter.zip "$TEMP_ROOT/unzipped"
verify_app "$TEMP_ROOT/unzipped/3dSlicerRouter.app"
diff -qr "$MOUNT/3dSlicerRouter.app" "$TEMP_ROOT/unzipped/3dSlicerRouter.app"
echo "verified: DMG and ZIP, version $EXPECTED_VERSION, arm64 + x86_64"
