# Install, update and uninstall

[Português](INSTALL.pt-BR.md)

## Requirements

- macOS 14 or newer, on Apple silicon or Intel.
- At least one installed slicer that can open 3MF files, such as OrcaSlicer, Bambu Studio or Snapmaker Orca.
- To build: Xcode 15 or newer, its command-line tools, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

The app uses native macOS frameworks. There is no package manager dependency at runtime, network service, AI model, account or API key.

## Build from source

```sh
brew install xcodegen
git clone https://github.com/MoraesGil/3dSlicerRouter.git
cd 3dSlicerRouter
./scripts/build.sh --test --install
```

The script builds a universal Release app, signs the helper and extensions before the host app, verifies the signatures and extension entitlements, then installs in `/Applications/3dSlicerRouter.app`.

If Xcode's build service is unavailable, use the same sources and SDK through the native CLI backend:

```sh
./scripts/build.sh --native --test --install
```

Both backends require Xcode. The native backend uses `swiftc`, `lipo` and `xctest`; it does not install another toolchain.

For terminal use, add this alias to your shell configuration:

```sh
alias 3dSlicerRouter=/Applications/3dSlicerRouter.app/Contents/MacOS/3dSlicerRouter
```

## First launch and approvals

1. Open **3dSlicerRouter** from Applications. Choose **Make default for .3mf**. This keeps the router as the default; individual files can still open in different slicers.
2. Finder thumbnails and Quick Look use the two bundled extensions. If macOS has disabled them, review **System Settings → General → Login Items & Extensions → Quick Look**. The wording can vary by macOS version.
3. Background pre-rendering is optional. Enable it explicitly with `3dSlicerRouter --background on`. If approval is pending, the app opens the native Login Items settings pane so you can approve it yourself.

Opening a selected file and rendering its preview do not require Accessibility or Screen Recording. The optional indexer can trigger macOS requests for protected folders or removable volumes. Registration approval and successful worker execution are separate states; use `--index-status` and the local log to diagnose failures.

## Signing and downloads

The default build is **ad-hoc signed**. It is not Developer ID signed or notarized. A valid local signature does not prove that Gatekeeper will accept a downloaded archive on another Mac.

Prebuilt archives, when available, are under [Releases](https://github.com/MoraesGil/3dSlicerRouter/releases). Check the version and source before running one. Building locally is the supported route while notarized distribution remains on the roadmap. Do not disable Gatekeeper or system security to install this app.

## Verify the installation

```sh
3dSlicerRouter --version
3dSlicerRouter --list-slicers
3dSlicerRouter --inspect samples/*.3mf
codesign --verify --deep --strict /Applications/3dSlicerRouter.app
```

The slicer list is built from valid installations. Removed apps, broken symlinks and stale LaunchServices registrations do not become picker buttons. The sample without printer metadata asks which installed slicer to use.

To check file association, use Finder: select a `.3mf` → **Get Info** → **Open with**. It should name **3dSlicerRouter**. You can set it from the CLI with `3dSlicerRouter --set-default`.


### Ad-hoc helper limitation

Automatic indexer startup remains experimental in ad-hoc builds. macOS may reject a launch with
`EX_CONFIG` (78) or `Launch Constraint Violation` even when registration appears enabled. This was
observed locally; disabling system security is not a supported fix. On-demand previews remain
available. Use `--render` or foreground `--index` when needed.

## Update

```sh
git pull --ff-only
./scripts/build.sh --test --install
```

The installer preserves the optional indexer's enabled state and registers the updated extensions. Printer mappings and per-file choices remain in the user's application data. Recheck any approvals requested by macOS after an update.

## Uninstall

```sh
./scripts/uninstall.sh
```

This removes the app, stops its optional agent, deletes its local catalog, preview cache and logs, and assigns `.3mf` to Bambu Studio when `duti` is available. To choose a different installed replacement:

```sh
./scripts/uninstall.sh com.orcaslicer.OrcaSlicer
```

Without `duti`, choose the replacement in Finder's **Get Info → Open with → Change All…**. No printer or slicer settings are deleted.

Per-file routing attributes are harmless metadata and are not removed by default. To explicitly remove them from a folder:

```sh
./scripts/uninstall.sh --purge-xattrs /path/to/your/3mf-folder
```

## Troubleshooting

| Symptom | Check |
|---|---|
| Double-click bypasses the router | Finder may have a per-file **Always Open With** override. Review it in Get Info. |
| Thumbnail is old | Save the project, confirm the Quick Look extensions are enabled, and request the preview again. An embedded-image fallback may be old. |
| The wrong app opens | Hold Option when opening to choose again, or use `--forget file.3mf`. |
| Background status is enabled but nothing renders | Check idle/power conditions, the background job's execution state and `~/Library/Logs/3dSlicerRouter/indexer.log`. Enabled registration alone does not prove a completed run. |
| A large project has only its saved preview | Compressed projects above 250 MB use the embedded first-plate fallback. |

Please report issues with the macOS version, app version and sanitized `--inspect` output. Do not attach credentials, customer models or private file paths.
