#!/bin/zsh
# Re-render the README images from samples/ (English UI strings).
set -euo pipefail
cd "${0:A:h}/.."
ROUTER=${ROUTER:-/Applications/3dSlicerRouter.app/Contents/MacOS/3dSlicerRouter}
mkdir -p docs/images
for name in bambu-h2d-four-plates snapmaker-u1-four-colors snapmaker-u1-painted-faces bambu-a1-keychain-tray; do
  "$ROUTER" --render "samples/$name.3mf" "docs/images/preview-$name.png" 1200 -AppleLanguages '(en)'
done
