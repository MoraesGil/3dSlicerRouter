# Samples

Six tiny synthetic 3MF projects, one per routing path. They carry the same metadata Bambu Studio and
Snapmaker Orca write (`printer_model`, bed size, filament colours, plates). The geometry is procedural,
so the slicers import them as plain models.

| File | Printer | Expected route | Shows off |
|---|---|---|---|
| `bambu-a1-keychain-tray.3mf` | Bambu Lab A1 | Bambu Studio | 6 two-colour tags on one plate |
| `bambu-a1mini-calibration.3mf` | Bambu Lab A1 mini | Bambu Studio | smaller 180 mm bed |
| `bambu-h2d-four-plates.3mf` | Bambu Lab H2D | Bambu Studio | 4 plates → panoramic preview |
| `snapmaker-u1-four-colors.3mf` | Snapmaker U1 | Snapmaker Orca | 4 toolheads, 4 colours |
| `unknown-printer-prusa-mk4s.3mf` | Original Prusa MK4S | asks once | picker + *Always use for this printer* |
| `no-printer-declared.3mf` | none | classifier or asks | plain 3MF with no slicer metadata |

```sh
# what would happen, without opening anything
/Applications/3dSlicerRouter.app/Contents/MacOS/3dSlicerRouter --inspect samples/*.3mf

# render a preview
/Applications/3dSlicerRouter.app/Contents/MacOS/3dSlicerRouter --render samples/bambu-h2d-four-plates.3mf h2d.png

# try the "printer changed" rule: open, retarget inside the slicer, save, open again
open samples/snapmaker-u1-four-colors.3mf
```

Regenerate them with `python3 scripts/make_samples.py` (Python standard library only).
