#!/bin/zsh
# Package a prior Release build for people installing from GitHub Releases.
set -euo pipefail
cd "${0:A:h}/.."
APP="build/DerivedData/Build/Products/Release/3dSlicerRouter.app"
[[ -d "$APP" ]] || { echo "build first: ./scripts/build.sh"; exit 1; }
codesign --verify --deep --strict "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/3dslicerrouter-dmg.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/3dSlicerRouter.app"
ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/READ ME - LEIA-ME.txt" <<'HELP'
3dSlicerRouter — macOS 14 or newer / macOS 14 ou mais novo
Apple silicon + Intel

INSTALL
1. Drag 3dSlicerRouter.app onto Applications in this window.
2. Eject this disk image. Open 3dSlicerRouter from Applications.
3. Choose “Use for .3mf and .gcode”. Keep at least one slicer installed.

This release is ad-hoc signed, not Developer ID signed or notarized.
macOS may block the first launch. If you trust this download, follow
Apple’s per-app “Open Anyway” instructions in System Settings >
Privacy & Security. Managed Macs may not permit this approval.
Do not disable Gatekeeper or remove quarantine from the app.

INSTALAR
1. Arraste 3dSlicerRouter.app para Applications nesta janela.
2. Ejete esta imagem de disco. Abra 3dSlicerRouter em Aplicativos.
3. Escolha “Usar para .3mf e .gcode”. Mantenha um fatiador instalado.

Esta versão usa assinatura ad-hoc, sem Developer ID nem notarização.
O macOS pode bloquear a primeira abertura. Se você confia no download,
siga as instruções da Apple para “Abrir Mesmo Assim” em Ajustes do
Sistema > Privacidade e Segurança. Macs gerenciados podem impedir
essa autorização. Não desative o Gatekeeper nem remova a quarentena.

Apple: https://support.apple.com/102445
Downloads: https://github.com/MoraesGil/3dSlicerRouter/releases/latest
Help / Ajuda: https://github.com/MoraesGil/3dSlicerRouter/blob/main/docs/INSTALL.md
HELP
hdiutil create -volname "3dSlicerRouter $VERSION" -srcfolder "$STAGING" \
  -format UDZO -fs HFS+ -ov build/3dSlicerRouter.dmg
rm -f build/3dSlicerRouter.zip
ditto -c -k --keepParent "$APP" build/3dSlicerRouter.zip
(cd build && shasum -a 256 3dSlicerRouter.dmg 3dSlicerRouter.zip > SHA256SUMS)
cat build/SHA256SUMS
