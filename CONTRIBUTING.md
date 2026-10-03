# Contributing

Thanks for helping 3D printing on the Mac get a little less annoying.

## Good first contributions

- **Another slicer or printer brand.** Add it to `SlicerApp.known` and `Mappings.byBrand`
  (`Sources/Core/Routing.swift`), plus a sample in `scripts/make_samples.py` and a test case.
- **A real-world 3MF that routes wrong.** Open an issue with the output of
  `3dSlicerRouter --inspect file.3mf`. Please do not attach files you are not allowed to share; the
  `Metadata/project_settings.config` keys `printer_model`, `printer_settings_id` and `printable_area` are
  usually enough.
- **Preview quality:** painted multi-material faces, per-object colours in Orca projects.

## Workflow

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project SlicerRouter.xcodeproj -scheme SlicerRouter test
./scripts/build.sh --install      # try it for real
```

- Keep it dependency-free; macOS frameworks only.
- Routing rules live in one pure function (`Router.decide`). Every new rule gets a unit test.
- UI strings go through `L10n` (English + Portuguese).
- Never commit customer or proprietary models. Generate samples procedurally.
