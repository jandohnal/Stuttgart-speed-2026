"""Convert an NFS5 track (.crp) to glTF 2.0 plus road data JSON, as a private style reference.

Format: docs/formats/crp.md (chapter "Tratě"). Verified on skidpad and farmland (Normandie).
Writes next to <out>.gltf: <out>.bin, <stem>_road.json (SimD road slices split into segments,
start/finish from <track>_fstart.scn), <stem>_objects.json (placed objects with their collision
type and mass from animdefs.txt; their nodes are in the group "props") and uses the
track textures converted by tools/fsh2png.py (converted on the fly if missing).

Usage:
    python3 tools/track2gltf.py sources/GameData/Track/skidpad.crp decomposed/GameData/Track/skidpad/skidpad.gltf
    python3 tools/track2gltf.py ... --level 2     # coarser LOD (0 = most detailed)
    python3 tools/track2gltf.py ... --library     # also the object prototypes, laid out in a row
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
from crp import article_matrix, article_mesh, entry_text, find, parse_crp, to_gltf, write_gltf  # noqa: E402

GROUPS = [
    ("road", r"^RD"),
    ("vegetation", r"^(tree|oak|shrub|treewall)"),
    ("terrain", r"^(CNK|MESH|FARM|HILL|TOPOF|SECONDARY|CLIF)"),
]
PLACED_MIN_DISTANCE = 50.0  # m
BASE_TAG = 0x44  # Base: 4-character object tag (SIGN, CONE ...), the key into animdefs.txt
COLLIDE_TYPES = {"ksmackable": "smackable", "kbox": "box", "kcylinder": "cylinder", "0": "none"}
SIMD_SIZE = 80
SEGMENT_GAP = 30.0  # m; slices are ~6 m apart, a bigger jump starts the next road segment (alternative routes)
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


def object_tag(d, art):
    base = find(art.sub, "Base")
    if base is None or base.length < BASE_TAG + 4:
        return ""
    raw = d[base.data + BASE_TAG:base.data + BASE_TAG + 4].rstrip(b"\0")
    return raw.decode("latin1") if raw and all(32 <= c < 127 for c in raw) else ""


def load_animdefs(folder):
    """Object properties per tag from animdefs.txt: {tag: {"collide", "mass", "drivethrough"}}.

    Only the top-level keys of each SECTION:ANIM are read; the first section of a tag wins."""
    match = [f for f in os.listdir(folder) if f.lower() == "animdefs.txt"]
    if not match:
        return {}
    text = re.sub(r"//[^\n]*", "", open(os.path.join(folder, match[0]), encoding="latin1").read())
    defs = {}
    for m in re.finditer(r"SECTION:ANIM\s*\{", text):
        depth, j = 1, m.end()
        while depth and j < len(text):
            depth += {"{": 1, "}": -1}.get(text[j], 0)
            j += 1
        body = text[m.end():j - 1]
        while True:  # drop nested sections, keep the top-level keys
            flat = re.sub(r"SECTION:\w+\s*\{[^{}]*\}", "", body)
            if flat == body:
                break
            body = flat
        props = {k.lower(): v.strip() for k, v in re.findall(r"(\w+)\s*=\s*([^;]+);", body)}
        tag = props.get("tag")
        if not tag or tag in defs:
            continue
        defs[tag] = {"collide": COLLIDE_TYPES.get(props.get("collidetype", "0").lower(), "static"),
                     "mass": float(props.get("mass", 0) or 0),
                     "drivethrough": props.get("drivethrough", props.get("drivethru", "0")) == "1"}
    return defs


def road_slices(d, misc):
    sd = find(misc, "SimD")
    if sd is None:
        return []
    out = []
    for i in range(sd.length // SIMD_SIZE):
        o = sd.data + SIMD_SIZE * i
        f = struct.unpack_from("<20f", d, o)
        ints = struct.unpack_from("<20i", d, o)
        out.append({"position": to_gltf(f[1:4]), "up": to_gltf(f[4:7]), "forward": to_gltf(f[7:10]),
                    "right": to_gltf(f[10:13]),
                    "flags": [ints[0]] + list(ints[13:16]), "widths": f[16:20]})
    return out


def road_segments(slices):
    """Split SimD into continuous segments: [{first, last, length_m, closed}]. The first one is the
    main road, the others are short alternative routes appended after it."""
    starts = [0] + [i + 1 for i, (a, b) in enumerate(zip(slices, slices[1:]))
                    if math.dist(a["position"], b["position"]) > SEGMENT_GAP]
    out = []
    for first, end in zip(starts, starts[1:] + [len(slices)]):
        last = end - 1
        length = sum(math.dist(slices[i]["position"], slices[i + 1]["position"]) for i in range(first, last))
        closed = last > first and math.dist(slices[first]["position"], slices[last]["position"]) <= SEGMENT_GAP
        out.append({"first": first, "last": last, "length_m": round(length, 1), "closed": closed})
    return out


def race_gates(src, slices):
    """Start and finish lines from <track>_fstart.scn (TRIGGER_ELEMENT type 2 = start, 1 = finish).

    Block lines: position; basis (forward, up, right: 9 floats); parameters (first int = type);
    the two end points of the line (6 floats). Returns {"start": {...}, "finish": {...}} with the
    nearest road slice."""
    path = os.path.splitext(src)[0] + "_fstart.scn"
    if not os.path.exists(path):
        return {}
    lines = [ln.split() for ln in open(path, encoding="latin1") if ln.strip()]
    gates = {}
    for i, ln in enumerate(lines):
        if ln[0] != "TRIGGER_ELEMENT":
            continue
        kind = {"2": "start", "1": "finish"}.get(lines[i + 3][0])
        if kind is None or kind in gates:
            continue
        pos = to_gltf([float(x) for x in lines[i + 1]])
        basis = [float(x) for x in lines[i + 2]]
        ends = [float(x) for x in lines[i + 4]]
        nearest = min(range(len(slices)), key=lambda k: math.dist(slices[k]["position"], pos), default=-1)
        gates[kind] = {"slice": nearest, "position": [round(x, 4) for x in pos],
                       "forward": [round(x, 4) for x in to_gltf(basis[0:3])],
                       "line": [[round(x, 4) for x in to_gltf(ends[k:k + 3])] for k in (0, 3)]}
    return gates


def centerline_prims(slices, segments, lift=0.05):
    """Ribbon spanning -widths[0] .. +widths[1] along the 'right' vector, for visual checks."""
    pos, nrm, tex, idx = [], [], [], []
    for seg in segments:
        for i in range(seg["first"], seg["last"] + 1):
            s = slices[i]
            p, r, u = s["position"], s["right"], s["up"]
            for side in (-s["widths"][0], s["widths"][1]):
                pos.append(tuple(p[k] + r[k] * side + u[k] * lift for k in range(3)))
                nrm.append(tuple(u))
                tex.append((0.0, float(i)))
            if i > seg["first"]:
                a = len(pos) - 4
                idx += [a, a + 1, a + 2, a + 1, a + 3, a + 2]
    return {CENTERLINE: (pos, nrm, tex, idx)} if idx else {}


def convert(src, out_path, level=0, library=False):
    d, arts, misc = parse_crp(open(src, "rb").read())
    animdefs = load_animdefs(os.path.dirname(src))
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

    nodes, props, lib_x, stats = [], [], 0.0, {"library_skipped": 0, "no_level": 0}
    for art in arts:
        name_e = find(art.sub, "Name")
        if name_e is None:
            continue
        name = entry_text(d, name_e)
        # Articles with tr are objects with their own transform: placed ones (signs, columns ...)
        # carry their position on the track, prototypes (cones, cars, people) sit at the origin and
        # are placed by events (*.scn GEOM_ELEMENT) or traffic.
        matrix = article_matrix(d, art)
        # Prototypes keep only a small pivot offset (box debris, arrows 13 m up), so "placed" means
        # further than PLACED_MIN_DISTANCE from the origin horizontally.
        placed = matrix is not None and math.hypot(matrix[12], matrix[14]) > PLACED_MIN_DISTANCE
        is_library = matrix is not None and not placed
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
        if placed:
            node = f"{len(props):03d} {name}"  # unique; _objects.json refers to it
            tag = object_tag(d, art)
            info = animdefs.get(tag, {"collide": "static" if not tag else "cylinder", "mass": 0.0, "drivethrough": False})
            props.append({"node": node, "name": name, "tag": tag, **info,
                          "position": [round(x, 3) for x in matrix[12:15]]})
            nodes.append({"name": node, "offset": (0.0, 0.0, 0.0), "matrix": matrix, "prims": prims, "group": "props"})
            continue
        if is_library:
            xs = [p[0] for pr in prims.values() for p in pr[0]]
            width = max(xs) - min(xs) if xs else 1.0
            offset = (lib_x - min(xs, default=0.0), 0.0, -60.0)
            lib_x += width + 2.0
        nodes.append({"name": name, "offset": offset, "prims": prims,
                      "group": "library" if is_library else group_of(name)})

    slices = road_slices(d, misc)
    segments = road_segments(slices)
    if slices:
        nodes.append({"name": "road_centerline", "offset": (0.0, 0.0, 0.0), "prims": centerline_prims(slices, segments),
                      "group": "simd"})

    found = sum(1 for tex, _ in mat_info.values() if tex in textures)

    def material_spec(key):
        if key == CENTERLINE:
            return {"name": "simd_road", "color": (1.0, 0.1, 0.1, 0.45)}
        tex, method = mat_info.get(key, ("", ""))
        return {"name": f"{tex} ({method})", "uri": textures.get(tex),
                "alpha": None if method == "Opaque" else "MASK"}

    write_gltf(out_path, nodes, material_spec, "stuttgart-speed track2gltf")

    length = sum(seg["length_m"] for seg in segments)
    gates = race_gates(src, slices)
    with open(os.path.join(out_dir, stem + "_road.json"), "w") as fh:
        json.dump({"source": os.path.basename(src), "slice_count": len(slices), "length_m": round(length, 1),
                   "fields": "position, up, forward, right (unit vectors), flags [int0, int13..15], widths [4] m",
                   "segments": segments, **gates,
                   "slices": [{k: [round(x, 4) if isinstance(x, float) else x for x in v] for k, v in s.items()}
                              for s in slices]}, fh)

    with open(os.path.join(out_dir, stem + "_objects.json"), "w") as fh:
        json.dump({"source": os.path.basename(src),
                   "fields": "node = glTF node in group props; tag from Base 0x44; collide (smackable | box | "
                             "cylinder | none | static), mass kg and drivethrough from animdefs.txt",
                   "objects": props}, fh, indent=1)

    tris = sum(len(p[3]) // 3 for n in nodes for p in n["prims"].values())
    groups = {}
    for n in nodes:
        groups[n["group"]] = groups.get(n["group"], 0) + 1
    print(f"{src}: {len(nodes)} parts {groups}, {tris} triangles, textures {found}/{len(mat_info)}, "
          f"road {len(slices)} slices in {len(segments)} segments {length:.0f} m, "
          f"start/finish slice {gates.get('start', {}).get('slice', '-')}/{gates.get('finish', {}).get('slice', '-')}, "
          f"placed objects {len(props)}, library prototypes skipped {stats['library_skipped']}")


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
