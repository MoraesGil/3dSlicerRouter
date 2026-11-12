# Install, update and uninstall

[Português](INSTALL.pt-BR.md)

## Requirements

- macOS 14 or newer, on Apple silicon or Intel.
- At least one installed slicer that can open 3MF files, such as OrcaSlicer, Bambu Studio or Snapmaker Orca.
- To build: Xcode 15 or newer, its command-line tools, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

The app uses native macOS frameworks. There is no package manager dependency at runtime, network service, AI model, account or API key.

## Download and install

1. **[Download 3dSlicerRouter.dmg](https://github.com/MoraesGil/3dSlicerRouter/releases/latest/download/3dSlicerRouter.dmg)** from the [latest Release](https://github.com/MoraesGil/3dSlicerRouter/releases/latest). The same app supports Apple silicon and Intel.
2. Open the DMG. Drag **3dSlicerRouter** onto **Applications** in that window.
3. Eject the disk image. Open **3dSlicerRouter** from **Applications** and choose **Make default for .3mf**.

You do not need Xcode, Homebrew, Git or Terminal. A ZIP is also available; extract it and move the app to Applications. `SHA256SUMS` contains the checksums for both downloads.

This release is **ad-hoc signed**, without Developer ID signing or notarization. If macOS blocks the first launch and you trust the download, follow Apple's [Open Anyway instructions](https://support.apple.com/102445): try opening the installed app, then use **System Settings → Privacy & Security → Open Anyway** and confirm. Managed Macs may prevent this approval. Do not disable Gatekeeper or remove quarantine. See [Signing and downloads](#signing-and-downloads) for the limits of this distribution.

## Build from source

This section is for developers. It is not needed to install the download.

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

DMG and ZIP downloads are under [Releases](https://github.com/MoraesGil/3dSlicerRouter/releases). Check the version and source before running one. The DMG simplifies copying the app; it does not provide notarization. Approval of a downloaded build and Quick Look extension activation on a clean Mac still need separate validation. Do not disable Gatekeeper or system security to install this app.

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

1. Download the latest DMG from [Releases](https://github.com/MoraesGil/3dSlicerRouter/releases/latest).
2. Close 3dSlicerRouter. If you enabled its optional background item, turn it off in **System Settings → General → Login Items** before replacing the app.
3. Drag the new app to **Applications** and choose **Replace**. Eject the image and open the installed app. Review any new macOS approvals and re-enable the optional background item if needed.

Printer mappings and per-file choices remain in the user's application data. There is no automatic updater.

For a source installation:

```sh
git pull --ff-only
./scripts/build.sh --test --install
```

The build script preserves the optional indexer's enabled state and registers the updated extensions. Recheck any approvals requested by macOS after an update.

## Uninstall

Turn off the optional background item in System Settings if enabled, then move **3dSlicerRouter** from **Applications** to the Trash. Use Finder's **Get Info → Open with → Change All…** to assign `.3mf` to another installed slicer. This leaves the local catalog, cache, logs and routing choices in Application Support.

For a source installation, this script also removes the app's catalog, preview cache and logs:

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
