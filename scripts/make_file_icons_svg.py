#!/usr/bin/env python3
"""Render the real app's file icons into a self-contained README illustration."""
import base64
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "build/DerivedData/Build/Products/Release/3dSlicerRouter.app/Contents/MacOS/3dSlicerRouter"
STYLES = [("router", "Router"), ("bambu", "Bambu"), ("orca", "Orca"),
          ("snapmaker", "Snapmaker"), ("prusa", "Prusa"), ("cura", "Cura"),
          ("creality", "Creality"), ("elegoo", "Elegoo")]


def main():
    if not APP.exists():
        raise SystemExit("Build first: ./scripts/build.sh --native")
    items = []
    with tempfile.TemporaryDirectory(prefix="slicerrouter-icons-") as temporary:
        for index, (style, label) in enumerate(STYLES):
            png = Path(temporary) / f"{style}.png"
            subprocess.run([str(APP), "--render-icon", style, str(png), "128"], check=True, capture_output=True)
            encoded = base64.b64encode(png.read_bytes()).decode("ascii")
            centre = 62.5 + index * 125
            items.append(f'<image x="{centre - 44}" y="24" width="88" height="88" href="data:image/png;base64,{encoded}"/>')
            items.append(f'<text x="{centre}" y="142" text-anchor="middle" fill="#E3ECE7" font-family="-apple-system,Helvetica,Arial,sans-serif" font-size="16">{label}</text>')
    svg = '<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="170" viewBox="0 0 1000 170" role="img" aria-label="Router file icons with slicer colours and letter markers">\n'
    svg += '<rect width="1000" height="170" rx="18" fill="#111820"/>\n'
    svg += "\n".join(items) + "\n</svg>\n"
    destination = ROOT / "docs/images/router-file-icons.svg"
    destination.write_text(svg)
    png = destination.with_suffix(".png")
    subprocess.run(["sips", "-s", "format", "png", str(destination), "--out", str(png)], check=True, capture_output=True)
    print(destination.relative_to(ROOT))
    print(png.relative_to(ROOT))


if __name__ == "__main__":
    main()
