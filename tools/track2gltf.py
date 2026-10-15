"""Convert an NFS5 track (.crp) to glTF 2.0 plus road data JSON, as a private style reference.

Format: docs/formats/crp.md (chapter "Tratě"). Verified on skidpad so far.
Writes next to <out>.gltf: <out>.bin, <stem>_road.json (SimD road slices) and uses the
track textures converted by tools/fsh2png.py (converted on the fly if missing).

Usage:
    python3 tools/track2gltf.py sources/GameData/Track/skidpad.crp decomposed/GameData/Track/skidpad/skidpad.gltf
    python3 tools/track2gltf.py ... --level 2     # coarser LOD (0 = most detailed)
    python3 tools/track2gltf.py ... --library     # also the object library, laid out in a row
"""
import argparse
import json
import math
import os
import re
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fsh2png  # noqa: E402
from crp import article_mesh, entry_text, find, parse_crp, write_gltf  # noqa: E402

GROUPS = [
    ("road", r"^RD"),
    ("vegetation", r"^(tree|oak|shrub|treewall)"),
    ("terrain", r"^(CNK|MESH|FARM|HILL|TOPOF|SECONDARY|CLIF)"),
]
SIMD_SIZE = 80
CENTERLINE = "__road_centerline"


def group_of(name):
    for group, pattern in GROUPS:
        if re.match(pattern, name, re.I):
            return group
    return "objects"


def texture_files(src, d, misc, out_dir):
    """Return {texture name: png filename in out_dir}, converting the track .fsh if needed."""
    index_path = os.path.join(out_dir, "index.json")
    if not os.path.exists(index_path):
        sn = find(misc, "sn")
        fsh_name = entry_text(d, sn) if sn else os.path.splitext(os.path.basename(src))[0] + ".fsh"
        folder = os.path.dirname(src)
        match = [f for f in os.listdir(folder) if f.lower() == fsh_name.lower()]
        if not match:
            return {}
        fsh2png.convert(os.path.join(folder, match[0]), out_dir)
    files = {}
    for e in json.load(open(index_path))["entries"]:
        if "file" in e:
            files.setdefault(e["name"], e["file"])
    return files


def road_slices(d, misc):
    sd = find(misc, "SimD")
    if sd is None:
        return []
    out = []
    for i in range(sd.length // SIMD_SIZE):
        o = sd.data + SIMD_SIZE * i
        f = struct.unpack_from("<20f", d, o)
        ints = struct.unpack_from("<20i", d, o)
        out.append({"position": f[1:4], "up": f[4:7], "forward": f[7:10], "right": f[10:13],
                    "flags": [ints[0]] + list(ints[13:16]), "widths": f[16:20]})
    return out


def centerline_prims(slices, lift=0.05):
    """Ribbon spanning -widths[0] .. +widths[1] along the 'right' vector, for visual checks."""
    pos, nrm, tex, idx = [], [], [], []
    for i, s in enumerate(slices):
        p, r, u = s["position"], s["right"], s["up"]
        for side in (-s["widths"][0], s["widths"][1]):
            pos.append(tuple(p[k] + r[k] * side + u[k] * lift for k in range(3)))
            nrm.append(tuple(u))
            tex.append((0.0, float(i)))
        if i:
            a = 2 * (i - 1)
            idx += [a, a + 1, a + 2, a + 1, a + 3, a + 2]
    return {CENTERLINE: (pos, nrm, tex, idx)} if idx else {}


def convert(src, out_path, level=0, library=False):
    d, arts, misc = parse_crp(open(src, "rb").read())
    out_dir = os.path.dirname(os.path.abspath(out_path))
    os.makedirs(out_dir, exist_ok=True)
    stem = os.path.splitext(os.path.basename(out_path))[0]
    textures = texture_files(src, d, misc, out_dir)
    materials, mat_info = {}, {}
    for e in misc:
        if e.tag == "mt":
            tex = d[e.data + 0x28:e.data + 0x2C].decode("latin1")
            method = d[e.data + 0x10:e.data + 0x20].split(b"\0")[0].decode("latin1")
            materials[e.index] = e.index
            mat_info[e.index] = (tex, method)

    nodes, lib_x, stats = [], 0.0, {"library_skipped": 0, "no_level": 0}
    for art in arts:
        name_e = find(art.sub, "Name")
        if name_e is None:
            continue
        name = entry_text(d, name_e)
        is_library = find(art.sub, "tr") is not None  # object prototypes at the origin, placed at run time
        if is_library and not library:
            stats["library_skipped"] += 1
            continue
        levels = sorted({s.index >> 12 for s in art.sub if s.tag == "pr"})
        lev = level if level in levels else min((lv for lv in levels if lv > level), default=None)
        if lev is None:
            lev = max(levels, default=None)
        if lev is None:
            stats["no_level"] += 1
            continue
        mesh = article_mesh(d, art, lev, lev, materials)
        if not mesh or not mesh[1]:
            continue
        offset, prims = mesh
        if is_library:
            xs = [p[0] for pr in prims.values() for p in pr[0]]
            width = max(xs) - min(xs) if xs else 1.0
            offset = (lib_x - min(xs, default=0.0), 0.0, -60.0)
            lib_x += width + 2.0
        nodes.append({"name": name, "offset": offset, "prims": prims,
                      "group": "library" if is_library else group_of(name)})

    slices = road_slices(d, misc)
    if slices:
        nodes.append({"name": "road_centerline", "offset": (0.0, 0.0, 0.0), "prims": centerline_prims(slices),
                      "group": "simd"})

    found = sum(1 for tex, _ in mat_info.values() if tex in textures)

    def material_spec(key):
        if key == CENTERLINE:
            return {"name": "simd_road", "color": (1.0, 0.1, 0.1, 0.45)}
        tex, method = mat_info.get(key, ("", ""))
        return {"name": f"{tex} ({method})", "uri": textures.get(tex),
                "alpha": None if method == "Opaque" else "MASK"}

    write_gltf(out_path, nodes, material_spec, "stuttgart-speed track2gltf")

    length = sum(math.dist(a["position"], b["position"]) for a, b in zip(slices, slices[1:]))
    with open(os.path.join(out_dir, stem + "_road.json"), "w") as fh:
        json.dump({"source": os.path.basename(src), "slice_count": len(slices), "length_m": round(length, 1),
                   "fields": "position, up, forward, right (unit vectors), flags [int0, int13..15], widths [4] m",
                   "slices": [{k: [round(x, 4) if isinstance(x, float) else x for x in v] for k, v in s.items()}
                              for s in slices]}, fh)

    tris = sum(len(p[3]) // 3 for n in nodes for p in n["prims"].values())
    groups = {}
    for n in nodes:
        groups[n["group"]] = groups.get(n["group"], 0) + 1
    print(f"{src}: {len(nodes)} parts {groups}, {tris} triangles, textures {found}/{len(mat_info)}, "
          f"road {len(slices)} slices {length:.0f} m, library skipped {stats['library_skipped']}")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("src")
    ap.add_argument("out")
    ap.add_argument("--level", type=int, default=0, help="detail level, 0 = most detailed")
    ap.add_argument("--library", action="store_true", help="include object library (laid out in a row)")
    a = ap.parse_args()
    convert(a.src, a.out, a.level, a.library)


if __name__ == "__main__":
    main()
