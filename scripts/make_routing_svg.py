#!/usr/bin/env python3
"""Build docs/images/routing.svg, the animated README explainer.

Two scenes loop: a .3mf (its real plate preview, rendered by the router itself) shows the
printer_model read from the file, and the file travels to the slicer that owns that printer.
Everything is embedded (no JS, no external requests) so GitHub can show it through <img>.

Needs the installed router (/Applications/3dSlicerRouter.app) for the previews, and Bambu Studio
and Snapmaker Orca in /Applications for their app icons. Uses sips (macOS) for conversions.

    python3 scripts/make_routing_svg.py
"""
import base64
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ROUTER = "/Applications/3dSlicerRouter.app/Contents/MacOS/3dSlicerRouter"
OUT = ROOT / "docs/images/routing.svg"

SCENES = [
    {"sample": "bambu-a1-keychain-tray.3mf", "printer": "Bambu Lab A1", "app": "Bambu Studio", "target": "bambu"},
    {"sample": "snapmaker-u1-four-colors.3mf", "printer": "Snapmaker U1", "app": "Snapmaker Orca", "target": "orca"},
]
APPS = {
    "bambu": ("Bambu Studio", "/Applications/BambuStudio.app/Contents/Resources/Icon.icns", "Bambu Lab printers"),
    "orca": ("Snapmaker Orca", "/Applications/Snapmaker Orca.app/Contents/Resources/Icon.icns", "Snapmaker printers"),
}


def sips(src, dst, *args):
    subprocess.run(["sips", *args, str(src), "--out", str(dst)], check=True, capture_output=True)


def b64(path):
    return base64.b64encode(Path(path).read_bytes()).decode()


def main():
    tmp = Path(tempfile.mkdtemp())
    thumbs = {}
    for s in SCENES:
        png = tmp / (s["target"] + ".png")
        subprocess.run([ROUTER, "--render", str(ROOT / "samples" / s["sample"]), str(png), "520",
                        "-AppleLanguages", "(en)"], check=True, capture_output=True)
        jpg = tmp / (s["target"] + ".jpg")
        sips(png, jpg, "-s", "format", "jpeg", "-s", "formatOptions", "80")
        thumbs[s["target"]] = b64(jpg)
    icons = {}
    for key, (_, icns, _) in APPS.items():
        png = tmp / (key + "-icon.png")
        sips(icns, png, "-s", "format", "png", "-Z", "144")
        icons[key] = b64(png)
    OUT.write_text(svg(thumbs, icons))
    print("wrote", OUT, f"{OUT.stat().st_size // 1024} KB")


def svg(thumbs, icons):
    tile_y = {"bambu": 64, "orca": 236}
    tiles = ""
    for key, (name, _, caption) in APPS.items():
        y = tile_y[key]
        tiles += f"""
  <g class="tile tile-{key}">
    <rect class="panel" x="640" y="{y}" width="288" height="100" rx="14"/>
    <g class="icon icon-{key}"><image x="658" y="{y + 18}" width="64" height="64" href="data:image/png;base64,{icons[key]}"/></g>
    <text class="app" x="740" y="{y + 46}">{name}</text>
    <text class="muted" x="740" y="{y + 70}">{caption}</text>
  </g>"""

    scenes = ""
    for i, s in enumerate(SCENES):
        t = s["target"]
        y = tile_y[t] + 50
        scenes += f"""
  <g class="scene scene-{i}">
    <g class="show">
      <image x="82" y="52" width="200" height="200" clip-path="url(#thumb)" href="data:image/jpeg;base64,{thumbs[t]}"/>
      <text class="file" x="182" y="282" text-anchor="middle">{s["sample"]}</text>
      <rect class="hl" x="185" y="306" width="110" height="24" rx="5"/>
      <text class="code" x="60" y="323">"printer_model": <tspan class="value">"{s["printer"]}"</tspan></text>
    </g>
    <path class="flow d1" pathLength="1" d="M332 200 H410"/>
    <path class="flow d2" pathLength="1" d="M560 200 C600 200 600 {y} 640 {y}"/>
    <rect class="ring" x="640" y="{tile_y[t]}" width="288" height="100" rx="14"/>
    <text class="caption" x="480" y="404" text-anchor="middle">printer_model is <tspan class="strong">{s["printer"]}</tspan>, so it opens in <tspan class="strong">{s["app"]}</tspan></text>
  </g>"""

    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 960 430" width="960" height="430" role="img" aria-labelledby="t d">
<title id="t">3dSlicerRouter picks the slicer from the printer inside the .3mf</title>
<desc id="d">A Bambu Lab A1 project opens in Bambu Studio; a Snapmaker U1 project opens in Snapmaker Orca. The router reads printer_model from each file.</desc>
<style>
  svg {{ --bg:#ffffff; --panel:#f6f8fa; --line:#d0d7de; --ink:#1f2328; --muted:#59636e; --accent:#1a7f37; --tint:rgba(26,127,55,.16); }}
  @media (prefers-color-scheme: dark) {{
    svg {{ --bg:#0d1117; --panel:#161b22; --line:#30363d; --ink:#e6edf3; --muted:#9198a1; --accent:#3fb950; --tint:rgba(63,185,80,.22); }}
  }}
  text {{ font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","Noto Sans",Helvetica,Arial,sans-serif; fill:var(--ink); }}
  .frame {{ fill:var(--bg); stroke:var(--line); }}
  .panel {{ fill:var(--panel); stroke:var(--line); }}
  .rail {{ fill:none; stroke:var(--line); stroke-width:2; stroke-dasharray:2 6; stroke-linecap:round; }}
  .router {{ fill:var(--panel); stroke:var(--line); }}
  .app {{ font-size:17px; font-weight:600; }}
  .muted {{ font-size:13px; fill:var(--muted); }}
  .file {{ font-size:13px; font-weight:600; }}
  .code {{ font-family:ui-monospace,SFMono-Regular,"SF Mono",Menlo,Consolas,monospace; font-size:12.5px; fill:var(--muted); }}
  .value {{ fill:var(--ink); font-weight:600; }}
  .hl {{ fill:var(--tint); transform-box:fill-box; transform-origin:left center; }}
  .flow {{ fill:none; stroke:var(--accent); stroke-width:2.5; stroke-linecap:round; stroke-dasharray:1; stroke-dashoffset:0; }}
  .ring {{ fill:none; stroke:var(--accent); stroke-width:2.5; }}
  .caption {{ font-size:15px; fill:var(--muted); }}
  .strong {{ fill:var(--ink); font-weight:600; }}
  .icon {{ transform-box:fill-box; transform-origin:center; }}
  .tile-bambu {{ opacity:1; }}
  .tile-orca {{ opacity:.42; }}
  .scene-1 {{ display:none; }}

  @media (prefers-reduced-motion: no-preference) {{
    .scene-1 {{ display:inline; }}
    .scene, .scene .show, .hl, .d1, .d2, .ring, .caption, .tile, .icon {{
      animation-duration:10s; animation-iteration-count:infinite; animation-timing-function:cubic-bezier(.16,1,.3,1);
    }}
    .scene-1, .scene-1 * {{ animation-delay:-5s; }}
    .tile-bambu, .icon-bambu {{ animation-delay:-5s; }}
    .scene .show {{ animation-name:show; }}
    .hl {{ animation-name:sweep; }}
    .d1 {{ animation-name:draw1; }}
    .d2 {{ animation-name:draw2; }}
    .ring, .caption {{ animation-name:arrive; }}
    .tile {{ animation-name:dim; opacity:1; }}
    .scene-0 .ring, .scene-1 .ring {{ opacity:0; }}
  }}
  @keyframes show  {{ 0% {{ opacity:0; transform:translateY(6px); }} 5%,46% {{ opacity:1; transform:none; }} 50%,100% {{ opacity:0; }} }}
  @keyframes sweep {{ 0%,7% {{ transform:scaleX(0); }} 15%,46% {{ transform:scaleX(1); }} 50%,100% {{ transform:scaleX(0); }} }}
  @keyframes draw1 {{ 0%,15% {{ stroke-dashoffset:1; }} 21%,46% {{ stroke-dashoffset:0; }} 50%,100% {{ stroke-dashoffset:1; }} }}
  @keyframes draw2 {{ 0%,21% {{ stroke-dashoffset:1; }} 29%,46% {{ stroke-dashoffset:0; }} 50%,100% {{ stroke-dashoffset:1; }} }}
  @keyframes arrive {{ 0%,28% {{ opacity:0; }} 32%,46% {{ opacity:1; }} 50%,100% {{ opacity:0; }} }}
  @keyframes dim   {{ 0%,28% {{ opacity:1; }} 32%,46% {{ opacity:.42; }} 50%,100% {{ opacity:1; }} }}
</style>
<defs><clipPath id="thumb"><rect x="82" y="52" width="200" height="200" rx="10"/></clipPath></defs>

<rect class="frame" x="0.5" y="0.5" width="959" height="429" rx="18"/>
<rect class="panel" x="32" y="36" width="300" height="320" rx="14"/>
<path class="rail" d="M332 200 H410"/>
<path class="rail" d="M560 200 C600 200 600 114 640 114"/>
<path class="rail" d="M560 200 C600 200 600 286 640 286"/>
<rect class="router" x="410" y="176" width="150" height="48" rx="24"/>
<text class="file" x="485" y="205" text-anchor="middle">3dSlicerRouter</text>
<text class="muted" x="485" y="250" text-anchor="middle">reads printer_model</text>
{tiles}
{scenes}
</svg>
"""


if __name__ == "__main__":
    main()
