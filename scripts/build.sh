#!/bin/zsh
# Build the app (ad hoc signature). With --install: copy to /Applications, register it and refresh Quick Look.
set -euo pipefail
cd "${0:A:h}/.."

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
PRODUCTS="build/DerivedData/Build/Products"
APP="$PRODUCTS/Release/3dSlicerRouter.app"
NATIVE=false
INSTALL=false
TEST=false
for arg in "$@"; do
  case "$arg" in
    --native) NATIVE=true ;;
    --install) INSTALL=true ;;
    --test) TEST=true ;;
    *) echo "usage: $0 [--native] [--test] [--install]" >&2; exit 2 ;;
  esac
done

if $NATIVE; then
  ./scripts/native.sh build
else
  xcodegen generate --quiet
  xcodebuild -project SlicerRouter.xcodeproj -scheme SlicerRouter -configuration Release \
    -derivedDataPath build/DerivedData build -quiet
fi

# Incremental builds must not retain this app's obsolete service definitions.
for legacy in com.moraesdev.3dslicerrouter.indexer.plist com.moraesdev.3dslicerrouter.previews.plist; do
  rm -f "$APP/Contents/Library/LaunchAgents/$legacy"
done

# Sign inside-out. Never use --deep to re-sign the host: that can discard the
# extensions' sandbox entitlements while still producing a valid outer signature.
codesign --force --sign - --identifier com.moraesdev.3dslicerrouter.indexer "$APP/Contents/Helpers/3dSlicerIndexer"
CHECK=$(mktemp "$PRODUCTS/Release/entitlements.XXXXXX")
trap 'rm -f "$CHECK"' EXIT
for name in Thumbnail Preview; do
  EXTENSION="$APP/Contents/PlugIns/SlicerRouter${name}.appex"
  codesign --force --sign - --entitlements "Sources/$name/$name.entitlements" --generate-entitlement-der "$EXTENSION"
  for arch in arm64 x86_64; do
    codesign -d --arch "$arch" --entitlements :- "$EXTENSION" > "$CHECK" 2>/dev/null
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$CHECK")" == true ]]
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.files.user-selected.read-only' "$CHECK")" == true ]]
  done
  codesign --verify --strict "$EXTENSION"
done
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "built: $APP"

if $TEST; then
  if $NATIVE; then
    ./scripts/native.sh test
  else
    xcodebuild -project SlicerRouter.xcodeproj -scheme SlicerRouter -derivedDataPath build/DerivedData test
  fi
fi

if $INSTALL; then
  DEST="/Applications/3dSlicerRouter.app"
  BACKGROUND_WAS_ENABLED=false
  # Unregister the previous revision before its executable/signature is replaced.
  if [[ -x "$DEST/Contents/MacOS/3dSlicerRouter" ]]; then
    [[ "$("$DEST/Contents/MacOS/3dSlicerRouter" --background status)" == "background: ativo" ]] && BACKGROUND_WAS_ENABLED=true
    "$DEST/Contents/MacOS/3dSlicerRouter" --background off
  fi
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  # Build copies share the bundle id; keep LaunchServices pointing at /Applications only.
  for copy in "$PRODUCTS"/*/3dSlicerRouter.app(N); do "$LSREGISTER" -u "$copy" || true; done
  "$LSREGISTER" -f "$DEST"
  pluginkit -a "$DEST/Contents/PlugIns/SlicerRouterThumbnail.appex"
  pluginkit -a "$DEST/Contents/PlugIns/SlicerRouterPreview.appex"
  # Activate the signed host through LaunchServices without opening a UI or taking focus.
  xcrun swift - "$DEST" <<'SWIFT'
import AppKit
let configuration = NSWorkspace.OpenConfiguration()
configuration.activates = false
configuration.hides = true
configuration.arguments = ["--version"]
let url = URL(fileURLWithPath: CommandLine.arguments.last!)
NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
    if let error {
        fputs("Could not activate the installed host: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
    exit(0)
}
RunLoop.main.run()
SWIFT
  if $BACKGROUND_WAS_ENABLED; then "$DEST/Contents/MacOS/3dSlicerRouter" --background on; fi
  qlmanage -r cache >/dev/null 2>&1 || true
  echo "installed: $DEST"
  echo "make it the default for .3mf and .gcode:  $DEST/Contents/MacOS/3dSlicerRouter --set-default"
fi
