#!/bin/zsh
# Uninstall 3dSlicerRouter.
#   ./scripts/uninstall.sh [bundle-id-for-.3mf] [--purge-xattrs <folder>]
# Default: remove the app, its index and settings, then hand .3mf back to Bambu Studio.
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

# Remove first: the app owns the org.3mf.3mf type declaration, so the new default must be set after it is gone.
[[ -d "$APP" ]] && "$LSREGISTER" -u "$APP"
rm -rf "$APP"
rm -rf "$HOME/Library/Application Support/3dSlicerRouter"
defaults delete com.moraesdev.3dslicerrouter 2>/dev/null
qlmanage -r cache >/dev/null 2>&1
echo "removed app, index and settings"

if command -v duti >/dev/null; then
  duti -s "$TARGET" .3mf all && echo "default for .3mf → $TARGET"
else
  echo "duti not found: set the default in Finder (Get Info → Open with → Change All…)"
fi

if [[ -n "$PURGE" ]]; then
  find "$PURGE" -name '*.3mf' -exec xattr -d com.moraesdev.slicer-router {} \; 2>/dev/null
  echo "stripped router memory from .3mf files under $PURGE"
fi
