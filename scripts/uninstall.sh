#!/bin/zsh
# Uninstall 3dSlicerRouter.
#   ./scripts/uninstall.sh [bundle-id-for-.3mf-and-.gcode] [--purge-xattrs <folder>]
# Default: remove the app, its index and settings, then hand .3mf and .gcode back to Bambu Studio.
set -uo pipefail

TARGET="com.bambulab.bambu-studio"
PURGE=""
while (( $# )); do
  case "$1" in
    --purge-xattrs) PURGE="${2:?folder required}"; shift 2 ;;
    *) TARGET="$1"; shift ;;
  esac
done

APP="/Applications/3dSlicerRouter.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# Stop the optional background indexer before its bundle disappears.
[[ -x "$APP/Contents/MacOS/3dSlicerRouter" ]] && "$APP/Contents/MacOS/3dSlicerRouter" --background off >/dev/null 2>&1

# Explicit purge removes only Router-owned file icon metadata, before the binary is removed.
if [[ -n "$PURGE" && -x "$APP/Contents/MacOS/3dSlicerRouter" ]]; then
  find "$PURGE" -type f \( -iname '*.3mf' -o -iname '*.gcode' \) -exec "$APP/Contents/MacOS/3dSlicerRouter" --forget {} +
fi

# Remove first: the app owns the org.3mf.3mf type declaration, so the new default must be set after it is gone.
[[ -d "$APP" ]] && "$LSREGISTER" -u "$APP"
rm -rf "$APP"
rm -rf "$HOME/Library/Application Support/3dSlicerRouter" "$HOME/Library/Logs/3dSlicerRouter"
defaults delete com.moraesdev.3dslicerrouter 2>/dev/null
qlmanage -r cache >/dev/null 2>&1
echo "removed app, index and settings"

if command -v duti >/dev/null; then
  for ext in .3mf .gcode; do
    duti -s "$TARGET" "$ext" all && echo "default for $ext → $TARGET"
  done
else
  echo "duti not found: set the default in Finder (Get Info → Open with → Change All…)"
fi

if [[ -n "$PURGE" ]]; then
  find "$PURGE" -type f \( -iname '*.3mf' -o -iname '*.gcode' \) -exec xattr -d com.moraesdev.slicer-router {} \; 2>/dev/null
  echo "stripped router memory from .3mf and .gcode files under $PURGE"
fi
