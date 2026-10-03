#!/bin/zsh
# Zip the Release build for GitHub Releases (expects a prior Release build).
set -euo pipefail
cd "${0:A:h}/.."
APP="build/DerivedData/Build/Products/Release/3dSlicerRouter.app"
[[ -d "$APP" ]] || { echo "build first: ./scripts/build.sh"; exit 1; }
rm -f build/3dSlicerRouter.zip
ditto -c -k --keepParent "$APP" build/3dSlicerRouter.zip
shasum -a 256 build/3dSlicerRouter.zip
