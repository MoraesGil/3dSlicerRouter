#!/usr/bin/env python3
"""Generate small synthetic 3MF samples that exercise every routing path.

Only the Python standard library is used. The files carry the same metadata the
router reads from Bambu Studio / Snapmaker Orca projects (printer_model,
printable_area, filament_colour, plates), but the geometry is procedural, so the
slicers import them as plain models.

    python3 scripts/make_samples.py   # writes samples/*.3mf
"""
import json
import math
import zipfile
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "samples"

CONTENT_TYPES = """<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
 <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
 <Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/>
 <Default Extension="config" ContentType="text/plain"/>
</Types>
"""
RELS = """<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
 <Relationship Target="/3D/3dmodel.model" Id="rel0" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
</Relationships>
"""


# --- geometry (z from 0 up, centred on x/y) ---------------------------------

def box(w, d, h):
    x, y = w / 2, d / 2
    v = [(-x, -y, 0), (x, -y, 0), (x, y, 0), (-x, y, 0), (-x, -y, h), (x, -y, h), (x, y, h), (-x, y, h)]
    t = [(0, 2, 1), (0, 3, 2), (4, 5, 6), (4, 6, 7), (0, 1, 5), (0, 5, 4),
         (1, 2, 6), (1, 6, 5), (2, 3, 7), (2, 7, 6), (3, 0, 4), (3, 4, 7)]
    return v, t


def cylinder(r, h, n=48, r_top=None):
    r_top = r if r_top is None else r_top
    v = [(0, 0, 0), (0, 0, h)]
    for i in range(n):
        a = 2 * math.pi * i / n
        v += [(r * math.cos(a), r * math.sin(a), 0), (r_top * math.cos(a), r_top * math.sin(a), h)]
    t = []
    for i in range(n):
        b0, t0 = 2 + 2 * i, 3 + 2 * i
        b1, t1 = 2 + 2 * ((i + 1) % n), 3 + 2 * ((i + 1) % n)
        t += [(0, b1, b0), (1, t0, t1), (b0, b1, t1), (b0, t1, t0)]
    return v, t


def torus(R, r, n=48, m=20):
    v, t = [], []
    for i in range(n):
        a = 2 * math.pi * i / n
        for j in range(m):
            b = 2 * math.pi * j / m
            v.append(((R + r * math.cos(b)) * math.cos(a), (R + r * math.cos(b)) * math.sin(a), r + r * math.sin(b)))
    for i in range(n):
        for j in range(m):
            p, q = i * m + j, ((i + 1) % n) * m + j
            p2, q2 = i * m + (j + 1) % m, ((i + 1) % n) * m + (j + 1) % m
            t += [(p, q, q2), (p, q2, p2)]
    return v, t


def stack(*parts):
    """Merge meshes; each part is (mesh, dz)."""
    v, t = [], []
    for (pv, pt), dz in parts:
        base = len(v)
        v += [(x, y, z + dz) for x, y, z in pv]
        t += [(a + base, b + base, c + base) for a, b, c in pt]
    return v, t


# --- 3MF writer ----------------------------------------------------------------

def write(name, objects, printer=None, bed=(256, 256), colours=("#FFFFFF",), plates=1, preset=None):
    """objects: list of dicts {name, mesh, x, y, extruder, plate}."""
    res, build = [], []
    for i, o in enumerate(objects, 1):
        v, t = o["mesh"]
        verts = "".join(f'<vertex x="{x:.4f}" y="{y:.4f}" z="{z:.4f}"/>' for x, y, z in v)
        tris = "".join(f'<triangle v1="{a}" v2="{b}" v3="{c}"/>' for a, b, c in t)
        res.append(f'<object id="{i}" type="model"><mesh><vertices>{verts}</vertices><triangles>{tris}</triangles></mesh></object>')
        build.append(f'<item objectid="{i}" transform="1 0 0 0 1 0 0 0 1 {o["x"]:.3f} {o["y"]:.3f} 0" printable="1"/>')
    model = ('<?xml version="1.0" encoding="UTF-8"?>\n'
             '<model unit="millimeter" xml:lang="en-US" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">\n'
             ' <metadata name="Application">3dSlicerRouter samples</metadata>\n'
             f' <metadata name="Title">{name}</metadata>\n'
             f' <resources>{"".join(res)}</resources>\n'
             f' <build>{"".join(build)}</build>\n</model>\n')

    files = {"[Content_Types].xml": CONTENT_TYPES, "_rels/.rels": RELS, "3D/3dmodel.model": model}
    if printer is not None:
        w, d = bed
        settings = {
            "printer_model": printer,
            "printer_settings_id": f"{printer} 0.4 nozzle",
            "print_settings_id": preset or "0.20mm Standard",
            "printable_area": [f"0x0", f"{w}x0", f"{w}x{d}", f"0x{d}"],
            "filament_colour": list(colours),
            "version": "1.0.0",
        }
        files["Metadata/project_settings.config"] = json.dumps(settings, indent=4)
        objs = "".join(
            f'<object id="{i}"><metadata key="name" value="{o["name"]}"/>'
            f'<metadata key="extruder" value="{o.get("extruder", 1)}"/></object>\n'
            for i, o in enumerate(objects, 1))
        plate_xml = ""
        for p in range(1, plates + 1):
            inst = "".join(
                f'<model_instance><metadata key="object_id" value="{i}"/><metadata key="instance_id" value="0"/></model_instance>'
                for i, o in enumerate(objects, 1) if o.get("plate", 1) == p)
            plate_xml += f'<plate><metadata key="plater_id" value="{p}"/>{inst}</plate>\n'
        files["Metadata/model_settings.config"] = f'<?xml version="1.0" encoding="UTF-8"?>\n<config>\n{objs}{plate_xml}</config>\n'

    OUT.mkdir(exist_ok=True)
    with zipfile.ZipFile(OUT / name, "w", zipfile.ZIP_DEFLATED) as z:
        for path, text in files.items():
            info = zipfile.ZipInfo(path, date_time=(2026, 10, 3, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, text)
    print("wrote", OUT / name)


def plate_offset(index, plates, w, d):
    """Bambu Studio / Orca plate grid: ceil(sqrt(n)) columns, 1.2x pitch, rows grow towards -Y."""
    cols = math.ceil(math.sqrt(plates))
    return (index % cols) * w * 1.2, -(index // cols) * d * 1.2


def main():
    tag = stack((box(40, 22, 3), 0), (cylinder(5, 2), 3))
    write("bambu-a1-keychain-tray.3mf", printer="Bambu Lab A1", bed=(256, 256),
          colours=("#F2F2F2", "#E5322D"), preset="0.16mm High Quality @BBL A1",
          objects=[{"name": f"tag-{i + 1}", "mesh": tag, "x": 68 + (i % 3) * 60, "y": 88 + (i // 3) * 80,
                    "extruder": 1 + (i % 2)} for i in range(6)])

    write("bambu-a1mini-calibration.3mf", printer="Bambu Lab A1 mini", bed=(180, 180),
          colours=("#2D7FF9", "#FFB000"), preset="0.20mm Standard @BBL A1M",
          objects=[{"name": "cube-20mm", "mesh": box(20, 20, 20), "x": 70, "y": 90, "extruder": 1},
                   {"name": "cylinder-20mm", "mesh": cylinder(10, 20), "x": 110, "y": 90, "extruder": 2}])

    towers = ("#FFFFFF", "#111111", "#0ACC38", "#E5322D")
    write("snapmaker-u1-four-colors.3mf", printer="Snapmaker U1", bed=(270, 270),
          colours=towers, preset="0.20mm Standard @U1",
          objects=[{"name": f"tower-T{i}", "mesh": stack((cylinder(14, 30 + 12 * i, r_top=9), 0)),
                    "x": 75 + (i % 2) * 120, "y": 80 + (i // 2) * 110, "extruder": i + 1} for i in range(4)])

    w, d = 350, 320
    plates = []
    shapes = [("cube", box(60, 60, 60)), ("cone", cylinder(35, 70, r_top=2)),
              ("ring", torus(35, 10)), ("stairs", stack((box(80, 40, 10), 0), (box(60, 40, 10), 10), (box(40, 40, 10), 20)))]
    for p, (label, mesh) in enumerate(shapes):
        ox, oy = plate_offset(p, len(shapes), w, d)
        plates.append({"name": label, "mesh": mesh, "x": ox + w / 2, "y": oy + d / 2, "extruder": p % 2 + 1, "plate": p + 1})
    write("bambu-h2d-four-plates.3mf", printer="Bambu Lab H2D", bed=(w, d),
          colours=("#7B5CFF", "#F2F2F2"), preset="0.20mm Standard @BBL H2D", plates=4, objects=plates)

    write("unknown-printer-prusa-mk4s.3mf", printer="Original Prusa MK4S", bed=(250, 210),
          colours=("#FF7A00",), preset="0.20mm SPEED @MK4S",
          objects=[{"name": "benchy-ish", "mesh": stack((box(60, 30, 8), 0), (box(30, 26, 22), 8), (cylinder(5, 10), 30)),
                    "x": 125, "y": 105}])

    write("no-printer-declared.3mf",
          objects=[{"name": "ring", "mesh": torus(30, 9), "x": 128, "y": 128}])


if __name__ == "__main__":
    main()
