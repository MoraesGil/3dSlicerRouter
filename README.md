<div align="center">

# 3dSlicerRouter

### Open every `.3mf` in the right slicer, automatically.

Double-click a 3MF on your Mac. 3dSlicerRouter reads the printer saved inside the file and opens
**Bambu Studio**, **Snapmaker Orca** or any slicer you choose.

[![CI](https://github.com/MoraesGil/3dSlicerRouter/actions/workflows/ci.yml/badge.svg)](https://github.com/MoraesGil/3dSlicerRouter/actions/workflows/ci.yml)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-native-F05138?logo=swift&logoColor=white)
![Dependencies](https://img.shields.io/badge/dependencies-0-brightgreen)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

<img src="docs/images/routing.svg" width="100%" alt="Animation: a Bambu Lab A1 project opens in Bambu Studio and a Snapmaker U1 project opens in Snapmaker Orca, because the router reads printer_model from each file">

[Install](docs/INSTALL.md) · [Try the samples](samples/) · [How it decides](#how-it-decides) · [Português](README.pt-BR.md)

</div>

## The problem

Bambu Studio, Snapmaker Orca, OrcaSlicer and PrusaSlicer all save `.3mf`, and Finder can only
have one default app for it. With printers from two brands you end up opening a U1 project in
Bambu Studio (or an A1 project in Orca) and getting preset warnings, missing filaments or a bed type
that changed without you noticing.

3dSlicerRouter becomes the default app for `.3mf` and gets out of the way. It has no window: it
reads `printer_model` from the project and hands the file to the slicer that owns that printer.

## Any printer, any slicer

| | Printer in the file | Opens in |
|:-:|---|---|
| <img src="docs/images/app-bambu-studio.png" width="40" alt="Bambu Studio"> | `Bambu Lab A1`, `A1 mini`, `P1S`, `X1C`, `H2D`, … | **Bambu Studio** |
| <img src="docs/images/app-snapmaker-orca.png" width="40" alt="Snapmaker Orca"> | `Snapmaker U1`, `J1`, `Artisan`, … | **Snapmaker Orca** |
| | Anything else (`Original Prusa MK4S`, `Elegoo Centauri Carbon`, …) | **Your choice**, asked once and remembered |

For a printer it has never seen, the router asks once: Bambu Studio, Snapmaker Orca or
**Other app…**, a native picker where any slicer in `/Applications` works (OrcaSlicer, PrusaSlicer,
Creality Print, Elegoo Slicer, Cura). Tick *Always use for this printer* and you are never asked again.
You can also map printers from the terminal:

```sh
3dSlicerRouter --map "Original Prusa MK4S" /Applications/PrusaSlicer.app
3dSlicerRouter --mappings
```

Need the other slicer for one file? **Hold ⌥ (Option) while opening** and pick. Finder's
*Open With* keeps working too, and the next double-click reads the file again.

## See where a file goes before you open it

The router also teaches Finder about 3MF projects:

- **List view and small icons** show the icon of the slicer the file will open in.
- **Larger icons, Gallery and the preview pane** show the plate: the image the slicer saved, or a
  rendered isometric view of the declared printer's bed when the file has none.
- **Quick Look (Space)** on a single-plate project is a 3D view you can orbit and zoom. Projects with
  several plates show every plate side by side.

<p align="center">
<img src="docs/images/preview-bambu-h2d-four-plates.png" width="49%" alt="Generated preview of a Bambu Lab H2D project with four plates">
<img src="docs/images/preview-snapmaker-u1-four-colors.png" width="49%" alt="Generated preview of a four-colour Snapmaker U1 project">
</p>

## How it decides

| Situation | Result |
|---|---|
| First open | Slicer mapped to the file's printer; unknown printer asks once |
| Same file, same printer | Where it opened last time, manual choices included |
| Printer changed within the brand (A1 → A1 mini) | Same slicer, no question |
| Printer changed to Bambu Lab (U1 → A1) | Bambu Studio, no question |
| Printer changed to another brand (A1 → U1) | Asks, with the mapped slicer first |
| No printer in the file | Optional local classifier, otherwise asks |
| ⌥ held while opening | Always asks |

The decision is stored on the file itself as an extended attribute (`com.moraesdev.slicer-router`)
and in a local SQLite index. **The file's contents are never modified.**

> Why not the `Application` field? Snapmaker Orca also writes `BambuStudio-…` there. The printer comes
> from `Metadata/project_settings.config` → `printer_model`.

## Install

Requires macOS 14 or newer and at least one slicer.

```sh
brew install xcodegen
git clone https://github.com/MoraesGil/3dSlicerRouter.git && cd 3dSlicerRouter
./scripts/build.sh --install
alias 3dSlicerRouter=/Applications/3dSlicerRouter.app/Contents/MacOS/3dSlicerRouter   # add to ~/.zshrc
3dSlicerRouter --set-default
```

Prefer a download? Grab the zip from [Releases](https://github.com/MoraesGil/3dSlicerRouter/releases).
Dependencies, update and **uninstall**: [docs/INSTALL.md](docs/INSTALL.md).

## Try it

Six small synthetic projects in [`samples/`](samples/) cover every path:

```sh
open samples/bambu-a1-keychain-tray.3mf        # Bambu Studio
open samples/snapmaker-u1-four-colors.3mf      # Snapmaker Orca
open samples/unknown-printer-prusa-mk4s.3mf    # asks once
3dSlicerRouter --inspect samples/*.3mf         # see every decision, opens nothing
```

## Command line

`3dSlicerRouter` is the alias from [Install](#install), pointing at
`/Applications/3dSlicerRouter.app/Contents/MacOS/3dSlicerRouter`.

| Command | What it does |
|---|---|
| `--inspect file.3mf…` | Printer, thumbnail, memory and decision, without opening or writing anything |
| `--map "<printer>" /Applications/App.app` | Send that printer to any slicer |
| `--mappings` | List brand defaults and your mappings |
| `--render file.3mf out.png [px]` | Isometric plate preview as PNG |
| `--forget file.3mf…` | Erase the router's memory for these files |
| `--set-default` | Make the router the default app for `.3mf` |

## Files with no printer (optional)

Some 3MF files carry no slicer metadata at all. For those the router can ask a local decision
model (for example LAYA) through any server that speaks the `/v1/systemone` typed-choice API and
returns probabilities. It opens directly only at 75 % confidence or more; otherwise it asks you with
its guess first. If nothing is listening on `http://127.0.0.1:8100/v1/systemone`, it simply asks.

```sh
defaults write com.moraesdev.3dslicerrouter LayaEndpoint off    # or another URL
```

## FAQ

**Does it touch my files?** Only extended attributes (the decision and Finder metadata). The 3MF
contents stay byte-for-byte the same.

**Does it need special permissions?** No. No Accessibility, Screen Recording or Full Disk Access.
macOS hands it only the file you opened.

**Does it phone home?** No. The only network call is the optional classifier on `localhost`.

## Roadmap

- [ ] Built-in defaults for OrcaSlicer, PrusaSlicer, Elegoo Slicer and Creality Print (today: *Other app…* or `--map`)
- [ ] Settings window for printer → slicer mappings
- [ ] Painted multi-material faces in the preview
- [ ] Notarized release

Ideas, printers that route wrong and PRs are welcome: [CONTRIBUTING.md](CONTRIBUTING.md).

## Disclaimer

Not affiliated with, endorsed or sponsored by Bambu Lab or Snapmaker. Bambu Studio, Snapmaker Orca
and their icons are trademarks of their owners, shown only to describe compatibility.

## License

[MIT](LICENSE) © Gilberto Moraes ([@MoraesGil](https://github.com/MoraesGil))
