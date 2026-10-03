#!/bin/zsh
# Build the app (ad hoc signature). With --install: copy to /Applications, register it and refresh Quick Look.
set -euo pipefail
cd "${0:A:h}/.."

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
PRODUCTS="build/DerivedData/Build/Products"

xcodegen generate --quiet
xcodebuild -project SlicerRouter.xcodeproj -scheme SlicerRouter -configuration Release \
  -derivedDataPath build/DerivedData build -quiet
APP="$PRODUCTS/Release/3dSlicerRouter.app"
codesign --verify --deep --strict "$APP"
echo "built: $APP"

if [[ "${1:-}" == "--install" ]]; then
  DEST="/Applications/3dSlicerRouter.app"
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  # Build copies share the bundle id; keep LaunchServices pointing at /Applications only.
  for copy in "$PRODUCTS"/*/3dSlicerRouter.app(N); do "$LSREGISTER" -u "$copy" || true; done
  "$LSREGISTER" -f "$DEST"
  pluginkit -a "$DEST/Contents/PlugIns/SlicerRouterThumbnail.appex"
  pluginkit -a "$DEST/Contents/PlugIns/SlicerRouterPreview.appex"
  # Ad hoc signed extensions only activate after the host app has been launched once.
  open -g -a "$DEST" --args --version
  qlmanage -r cache >/dev/null 2>&1 || true
  echo "installed: $DEST"
  echo "make it the default for .3mf:  $DEST/Contents/MacOS/3dSlicerRouter --set-default"
fi
