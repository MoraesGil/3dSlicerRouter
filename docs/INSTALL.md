# Install, update and uninstall

[Português](INSTALL.pt-BR.md)

## Dependencies

| | What | Needed for |
|---|---|---|
| **Runtime** | macOS 14 Sonoma or newer (Apple silicon or Intel) | running the app |
| | [Bambu Studio](https://bambulab.com/en/download/studio) and/or [Snapmaker Orca](https://www.snapmaker.com/) in `/Applications` | the slicers it routes to |
| | *(optional)* a local [LAYA classifier](../README.md#files-with-no-printer-optional) | files that declare no printer |
| **Build** | Xcode 15 or newer (Command Line Tools alone are not enough) | compiling |
| | [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen` | generating the Xcode project |
| *Optional* | [duti](https://github.com/moretension/duti): `brew install duti` | switching default apps from the terminal |
| | Python 3 | regenerating `samples/` only |

There are **no third-party libraries**. Zip reading, SQLite, SceneKit rendering, Quick Look and
LaunchServices all come from macOS.

**Permissions:** none. The app does not ask for Accessibility, Screen Recording or Full Disk Access.
macOS hands it only the file you double-clicked. The plate preview is rendered off-screen and is not a
screenshot of any window.

## Option A: build from source (recommended)

```sh
brew install xcodegen
git clone https://github.com/MoraesGil/3dSlicerRouter.git
cd 3dSlicerRouter
./scripts/build.sh --install
/Applications/3dSlicerRouter.app/Contents/MacOS/3dSlicerRouter --set-default
```

`build.sh --install`:

1. generates `SlicerRouter.xcodeproj` and builds Release with an ad hoc signature;
2. copies the app to `/Applications/3dSlicerRouter.app` and registers it with LaunchServices;
3. registers both Quick Look extensions (thumbnail and preview);
4. launches the app once in the background (`--version`), because macOS only activates the extensions
   of an ad hoc signed app after its first launch.

`--set-default` makes the router the default app for `.3mf`. You can do the same in Finder: select any
`.3mf` → **Get Info** → **Open with: 3dSlicerRouter** → **Change All…**.

### Check it

```sh
/Applications/3dSlicerRouter.app/Contents/MacOS/3dSlicerRouter --inspect samples/*.3mf
duti -x 3mf                     # should print 3dSlicerRouter
```

Finder may keep old thumbnails cached for a while. `qlmanage -r cache` and relaunching Finder
(⌥ + right-click the Finder icon in the Dock → *Relaunch*) refresh them.

## Option B: prebuilt download

1. Download `3dSlicerRouter.zip` from [Releases](https://github.com/MoraesGil/3dSlicerRouter/releases).
2. Unzip and drag **3dSlicerRouter.app** to **/Applications**.
3. The build is ad hoc signed, not notarized, so remove the download quarantine once:
   ```sh
   xattr -dr com.apple.quarantine /Applications/3dSlicerRouter.app
   ```
4. Open the app once from `/Applications`. A small window explains what it does; click
   **Make default for .3mf**.

## Update

```sh
cd 3dSlicerRouter && git pull && ./scripts/build.sh --install
```

Your mappings and per-file memory are kept.

## Uninstall

```sh
./scripts/uninstall.sh                          # remove the app + data, hand .3mf to Bambu Studio
./scripts/uninstall.sh com.snapmaker.snapmaker-orca   # …or hand .3mf to another app
./scripts/uninstall.sh --purge-xattrs ~/Downloads     # also strip the router's memory from files there
```

What the script does, if you prefer to do it by hand:

0. **Turn off the background indexer** (if you enabled it): `3dSlicerRouter --background off`.
1. **Remove the app and its Quick Look extensions.**
   ```sh
   /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u /Applications/3dSlicerRouter.app
   rm -rf /Applications/3dSlicerRouter.app
   ```
2. **Give `.3mf` back to a slicer, after removing the app** (the app owns the `org.3mf.3mf` type):
   `duti -s com.bambulab.bambu-studio .3mf all`, or in Finder: **Get Info** → **Open with** → choose the
   slicer → **Change All…**.
3. **Delete its data.**
   ```sh
   rm -rf ~/Library/Application\ Support/3dSlicerRouter      # SQLite index, catalog and previews
   rm -rf ~/Library/Logs/3dSlicerRouter                      # indexer log
   defaults delete com.moraesdev.3dslicerrouter 2>/dev/null # settings (LAYA endpoint)
   qlmanage -r cache                                        # drop cached thumbnails
   ```
4. *(Optional)* **Remove the per-file memory.** Each routed file carries the extended attribute
   `com.moraesdev.slicer-router`. It is harmless metadata, but you can strip it:
   ```sh
   find ~/Downloads -name '*.3mf' -exec xattr -d com.moraesdev.slicer-router {} \; 2>/dev/null
   ```

Nothing else is installed. The only background item is the optional indexer, which lives inside the
app bundle and disappears with it; there are no kernel or system extensions.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Double-click still opens a slicer directly | That file has a Finder *Always Open With* override: `xattr -d com.apple.LaunchServices.OpenWith file.3mf` |
| No thumbnails or previews | Launch the app once (`open -a 3dSlicerRouter --args --version`), then `qlmanage -r cache` |
| `--set-default` points to a build folder | Build copies share the bundle id. Run `./scripts/build.sh --install` again; it unregisters them |
| "App is damaged" / cannot be opened (download) | `xattr -dr com.apple.quarantine /Applications/3dSlicerRouter.app` |
| A file keeps going to the wrong slicer | `3dSlicerRouter --forget file.3mf`, or hold ⌥ while opening to pick again |
| Testing thumbnails from the terminal hangs | `qlmanage -t` is unreliable with modern extensions. Look at Finder or use `QLThumbnailGenerator` |
