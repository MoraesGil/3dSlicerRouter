#!/bin/zsh
# Reproducible CLI fallback when Xcode's build service cannot run. Uses the same
# sources, bundle metadata and architectures as the Xcode project; build.sh signs.
set -euo pipefail
cd "${0:A:h}/.."
PRODUCTS=build/DerivedData/Build/Products/Release
APP="$PRODUCTS/3dSlicerRouter.app"
OBJECTS=build/NativeObjects
DEVELOPER=$(xcode-select -p)
SDK=$(xcrun --sdk macosx --show-sdk-path)

case "${1:-}" in
  build)
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Library/LaunchAgents" "$OBJECTS"
    python3 - "$APP" <<'PY'
import pathlib, plistlib, re, sys
app = pathlib.Path(sys.argv[1])
project = pathlib.Path('project.yml').read_text()
version = re.search(r'MARKETING_VERSION: "([^"]+)"', project)[1]
build = re.search(r'CURRENT_PROJECT_VERSION: "([^"]+)"', project)[1]
targets = [('App', app, '3dSlicerRouter', 'SlicerRouter', 'com.moraesdev.3dslicerrouter')]
targets += [(name, app / 'Contents/PlugIns' / f'SlicerRouter{name}.appex', f'SlicerRouter{name}', f'SlicerRouter{name}', f'com.moraesdev.3dslicerrouter.{name.lower()}') for name in ('Thumbnail', 'Preview')]
for source, bundle, executable, module, identifier in targets:
    replacements = {'DEVELOPMENT_LANGUAGE': 'en', 'EXECUTABLE_NAME': executable,
                    'PRODUCT_NAME': executable, 'PRODUCT_MODULE_NAME': module,
                    'PRODUCT_BUNDLE_IDENTIFIER': identifier, 'MARKETING_VERSION': version,
                    'CURRENT_PROJECT_VERSION': build}
    text = pathlib.Path(f'Sources/{source}/Info.plist').read_text()
    for key, value in replacements.items():
        text = text.replace(f'$({key})', value)
    info = plistlib.loads(text.encode())
    info.update(CFBundleSupportedPlatforms=['MacOSX'], LSMinimumSystemVersion='14.0')
    (bundle / 'Contents/MacOS').mkdir(parents=True, exist_ok=True)
    (bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
(app / 'Contents/PkgInfo').write_bytes(b'APPL????')
PY
    NATIVE_TASK_PIDS=()
    for arch in arm64 x86_64; do
      FLAGS=(-swift-version 5 -sdk "$SDK" -target "$arch-apple-macos14.0" -O)
      xcrun swiftc $FLAGS -module-name SlicerRouter Sources/Core/*.swift Sources/App/*.swift -o "$OBJECTS/router-$arch" &
      NATIVE_TASK_PIDS+=($!)
      xcrun swiftc $FLAGS -module-name SlicerRouterIndexer Sources/Core/*.swift Sources/App/Store.swift Sources/App/Indexer.swift Sources/Indexer/main.swift -o "$OBJECTS/indexer-$arch" &
      NATIVE_TASK_PIDS+=($!)
      for name in Thumbnail Preview; do
        xcrun swiftc $FLAGS -parse-as-library -application-extension -emit-executable \
          -module-name "SlicerRouter$name" -Xlinker -e -Xlinker _NSExtensionMain \
          Sources/Core/*.swift Sources/$name/*.swift -o "$OBJECTS/$name-$arch" &
        NATIVE_TASK_PIDS+=($!)
      done
    done
    NATIVE_FAILURE=0
    for NATIVE_TASK_PID in $NATIVE_TASK_PIDS; do
      wait "$NATIVE_TASK_PID" || NATIVE_FAILURE=1
    done
    (( NATIVE_FAILURE == 0 )) || exit 1
    xcrun lipo -create "$OBJECTS/router-arm64" "$OBJECTS/router-x86_64" -output "$APP/Contents/MacOS/3dSlicerRouter"
    xcrun lipo -create "$OBJECTS/indexer-arm64" "$OBJECTS/indexer-x86_64" -output "$APP/Contents/Helpers/3dSlicerIndexer"
    for name in Thumbnail Preview; do
      xcrun lipo -create "$OBJECTS/$name-arm64" "$OBJECTS/$name-x86_64" -output "$APP/Contents/PlugIns/SlicerRouter$name.appex/Contents/MacOS/SlicerRouter$name"
    done
    cp Resources/LaunchAgents/com.moraesdev.3dslicerrouter.previews.v2.plist "$APP/Contents/Library/LaunchAgents/"
    ;;
  test)
    TEST="$PRODUCTS/SlicerRouterTests.xctest"
    FRAMEWORKS="$DEVELOPER/Platforms/MacOSX.platform/Developer/Library/Frameworks"
    LIBRARIES="$DEVELOPER/Platforms/MacOSX.platform/Developer/usr/lib"
    mkdir -p "$TEST/Contents/MacOS"
    xcrun swiftc -swift-version 5 -sdk "$SDK" -target "$(uname -m)-apple-macos14.0" \
      -emit-library -parse-as-library -module-name SlicerRouterTests \
      -F "$FRAMEWORKS" -I "$LIBRARIES" -L "$LIBRARIES" -lXCTestSwiftSupport \
      -Xlinker -rpath -Xlinker "$FRAMEWORKS" -Xlinker -rpath -Xlinker "$LIBRARIES" \
      Sources/Core/*.swift Sources/App/Store.swift Sources/App/Indexer.swift Tests/*.swift \
      -o "$TEST/Contents/MacOS/SlicerRouterTests"
    python3 - "$TEST/Contents/Info.plist" <<'PY'
import pathlib, plistlib, sys
pathlib.Path(sys.argv[1]).write_bytes(plistlib.dumps({'CFBundleIdentifier': 'com.moraesdev.3dslicerrouter.tests', 'CFBundleExecutable': 'SlicerRouterTests', 'CFBundlePackageType': 'BNDL'}))
PY
    xcrun xctest "$TEST"
    ;;
  *) echo "usage: $0 build|test" >&2; exit 2 ;;
esac
