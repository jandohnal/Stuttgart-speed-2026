"""Convert an NFS5 track (.crp) to glTF 2.0 plus road data JSON, as a private style reference.

Format: docs/formats/crp.md (chapter "Tratě"). Verified on skidpad and farmland (Normandie).
Writes next to <out>.gltf: <out>.bin, <stem>_road.json (SimD road slices split into segments,
start/finish from <track>_fstart.scn, on a circuit without it an own line on a straight),
<stem>_objects.json (placed objects with their collision
type and mass from animdefs.txt; their nodes are in the group "props"), <stem>_lights.json (ef
flares and emitters: world ones, ones on placed objects, ones on library prototypes) and uses the
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

import ai_lines
import fsh2png
import scn
from common import find_file
from crp import EFFECT_FLARE, STATS, article_effects, article_matrix, article_mesh, base_info, entry_text, find, parse_crp, to_gltf, write_gltf

GROUPS = [
    ("road", r"^RD"),
    ("vegetation", r"^(tree|oak|shrub|treewall)"),
    ("terrain", r"^(CNK|MESH|FARM|HILL|TOPOF|SECONDARY|CLIF)|.*SECONDARY"),  # WOBJ (1 FHILL..._SECONDARY), DIRTROAD01_SECONDARY
]
PLACED_MIN_DISTANCE = 50.0  # m
SIMD_SIZE = 80
SEGMENT_LINK = 20.0  # m; a segment continues into the one that starts this close to its end (same direction)
SEGMENT_GAP = 30.0  # m; slices are ~6 m apart, a bigger jump starts the next road segment (alternative routes)
LAP_GRID_SLICES = 10  # slices (~60 m) behind a circuit's own start/finish line that must be straight (grid)
LAP_AHEAD_SLICES = 6  # slices (~36 m) after it that must be straight
LAP_STRAIGHT_DEG = 3.0  # largest heading change over that stretch
LAP_LINE_OFFSET = 3.0  # m; both racing lines (.lsp) must stay this close to the slice centre there
CENTERLINE = "__road_centerline"


def geom_matrix(geom):
    """A GEOM_ELEMENT's placement as a glTF column-major matrix, mirrored like crp.article_matrix
    (rows of the basis = axes, as in the tr matrix of placed articles; scale per axis)."""
    b, s, p = geom["basis"], geom["scale"], geom["position"]
    m = [b[0] * s[0], b[1] * s[0], b[2] * s[0], 0.0,
         b[3] * s[1], b[4] * s[1], b[5] * s[1], 0.0,
         b[6] * s[2], b[7] * s[2], b[8] * s[2], 0.0,
         p[0], p[1], p[2], 1.0]
    for i in (1, 2, 3, 4, 8, 12):
        m[i] = -m[i]
    return m


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
        fsh = find_file(os.path.dirname(src), fsh_name)
        if fsh is None:
            return {}
        fsh2png.convert(fsh, out_dir)
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
        out.append({"first": first, "last": last, "length_m": round(length, 1), "closed": closed, "next": None})
    # SimD does not store a route in driving order: Monte Carlo's segments are joined end to start.
    for seg in out:
        end = slices[seg["last"]]
        best = None
        for j, other in enumerate(out):
            start = slices[other["first"]]
            d = math.dist(end["position"], start["position"])
            if other is not seg and d <= SEGMENT_LINK and sum(a * b for a, b in zip(end["forward"], start["forward"])) > 0.5:
                if best is None or d < best[0]:
                    best = (d, j)
        if best:
            seg["next"] = best[1]
    return out


def road_lap(segments):
    """The segments of a closed lap from segment 0 (following "next"), or None."""
    order, j = [], 0
    while j is not None and j not in order:
        order.append(j)
        j = segments[j]["next"]
    if j != 0 or len(order) < 2:
        return None
    return {"segments": order, "length_m": round(sum(segments[k]["length_m"] for k in order), 1)}


def race_gates(src, slices):
    """Start and finish lines (scn.start_finish) in glTF space, each with the nearest road slice."""
    gates = {}
    for kind, trigger in scn.start_finish(src).items():
        pos = to_gltf(trigger["position"])
        ends = trigger["line"]
        nearest = min(range(len(slices)), key=lambda k: math.dist(slices[k]["position"], pos), default=-1)
        gates[kind] = {"slice": nearest, "position": [round(x, 4) for x in pos],
                       "forward": [round(x, 4) for x in to_gltf(trigger["basis"][0:3])],
                       "line": [[round(x, 4) for x in to_gltf(ends[k:k + 3])] for k in (0, 3)]}
    return gates


def lap_gates(src, slices, segments, lap):
    """Own start/finish line for a circuit without _fstart.scn (Monte Carlo): the lap slice nearest
    to the lap's start (slice 0, where the car used to start) whose stretch from LAP_GRID_SLICES
    before to LAP_AHEAD_SLICES after it turns by at most LAP_STRAIGHT_DEG, so the grid stands on a
    straight, and where both racing lines (racer/work/<track>0.lsp, 1.lsp) stay within
    LAP_LINE_OFFSET of the slice centre: in Monte Carlo the slices run on into streets that a
    variant closes off, while the route takes another street. Start and finish are the same line
    across the road ("source": "lap")."""
    order = [i for k in lap["segments"] for i in range(segments[k]["first"], segments[k]["last"] + 1)]
    n = len(order)
    track = os.path.splitext(os.path.basename(src))[0]
    offsets = []
    for k in (0, 1):
        path = find_file(os.path.join(os.path.dirname(src), "racer", "work"), f"{track}{k}.lsp")
        if path:
            _, points = ai_lines.read_lsp(path)
            if len(points) == len(slices):
                offsets.append(ai_lines.line_offsets(points, slices)[0])

    def heading(i):
        f = slices[order[i % n]]["forward"]
        return math.atan2(f[0], f[2])

    def turn(i):
        h = heading(i)
        return max(abs((math.degrees(heading(i + k) - h) + 180.0) % 360.0 - 180.0)
                   for k in range(-LAP_GRID_SLICES, LAP_AHEAD_SLICES + 1))

    def on_route(i):
        return all(abs(line[order[(i + k) % n]]) <= LAP_LINE_OFFSET
                   for line in offsets for k in range(-LAP_GRID_SLICES, LAP_AHEAD_SLICES + 1))

    straight = [i for i in range(n) if turn(i) <= LAP_STRAIGHT_DEG and on_route(i)]
    if not straight:
        return {}
    index = order[min(straight, key=lambda i: min(i, n - i))]
    s = slices[index]
    pos, right, (left_w, right_w) = s["position"], s["right"], s["widths"][0:2]
    line = {"slice": index,
            "position": [round(x, 4) for x in pos], "forward": [round(x, 4) for x in s["forward"]],
            "line": [[round(pos[k] - right[k] * left_w, 4) for k in range(3)],
                     [round(pos[k] + right[k] * right_w, 4) for k in range(3)]],
            "source": "lap"}
    return {"start": line, "finish": dict(line)}


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


def light_entry(effect, article=None):
    out = {"id": effect["id"], "position": [round(x, 3) for x in effect["position"]],
           "direction": [round(x, 4) for x in effect["direction"]]}
    if article:
        out["article"] = article
    return out


def convert(src, out_path, level=0, library=False):
    d, arts, misc = parse_crp(open(src, "rb").read())
    STATS.clear()
    animdefs = scn.read_animdefs(os.path.dirname(src))
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
    # Prototypes the start scene places (finish line tiles FNSH): exported where it puts them.
    gate_geoms = {}
    for geom in scn.start_geoms(src):
        gate_geoms.setdefault(geom["tag"], []).append(geom)
    lights = {"world": [], "props": {}, "library": {}, "emitters": []}
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
        effects = article_effects(d, art)
        if is_library:
            tag = base_info(d, art)["tag"]
            flares = [light_entry(e) for e in effects if e["kind"] == EFFECT_FLARE]
            if tag and flares and tag not in lights["library"]:
                lights["library"][tag] = flares
        gate_tag = base_info(d, art)["tag"] if is_library else ""
        if is_library and not library and gate_tag not in gate_geoms:
            stats["library_skipped"] += 1
            continue
        levels = sorted({s.index >> 12 for s in art.sub if s.tag == "pr"})
        lev = level if level in levels else min((lv for lv in levels if lv > level), default=None)
        if lev is None:
            lev = max(levels, default=None)
        if lev is None:
            stats["no_level"] += 1
            continue
        if gate_tag in gate_geoms:
            gate_mesh = article_mesh(d, art, lev, lev, materials)
            if gate_mesh and gate_mesh[1]:
                # The scene places the vertices as they are; the prototype's tr (pivot) is not applied:
                # on farmland the two FNSH tiles then cover the 2 x 6 m road exactly.
                for i, geom in enumerate(gate_geoms.pop(gate_tag)):
                    nodes.append({"name": f"{gate_tag} {i}", "offset": (0.0, 0.0, 0.0), "matrix": geom_matrix(geom),
                                  "prims": gate_mesh[1], "group": "gates"})
            if not library:
                continue
        ground = not placed and not is_library and group_of(name) in ("road", "terrain")
        mesh = article_mesh(d, art, lev, lev, materials, up=ground)
        if not mesh or not mesh[1]:
            continue
        offset, prims = mesh
        if placed:
            node = f"{len(props):03d} {name}"  # unique; _objects.json refers to it
            flares = [light_entry(e) for e in effects if e["kind"] == EFFECT_FLARE]
            if flares:
                lights["props"][node] = flares
            tag = base_info(d, art)["tag"]
            info = animdefs.get(tag, {"collide": "static" if not tag else "cylinder", "mass": 0.0, "drivethrough": False})
            props.append({"node": node, "name": name, "tag": tag, **info,
                          "position": [round(x, 3) for x in matrix[12:15]]})
            nodes.append({"name": node, "offset": (0.0, 0.0, 0.0), "matrix": matrix, "prims": prims, "group": "props"})
            continue
        if not is_library:
            for e in effects:
                (lights["world"] if e["kind"] == EFFECT_FLARE else lights["emitters"]).append(light_entry(e, name))
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

    write_gltf(out_path, nodes, material_spec, "stuttgart-speed track2gltf",
               {k: STATS[k] for k in ("dropped", "flipped_by_normal", "flipped_up")})

    length = sum(seg["length_m"] for seg in segments)
    lap = road_lap(segments)
    gates = race_gates(src, slices)
    if not gates and lap:
        gates = lap_gates(src, slices, segments, lap)
    with open(os.path.join(out_dir, stem + "_road.json"), "w") as fh:
        json.dump({"source": os.path.basename(src), "slice_count": len(slices), "length_m": round(length, 1),
                   "fields": "position, up, forward, right (unit vectors), flags [int0, int13..15], widths [4] m",
                   "segments": segments, "lap": lap, **gates,
                   "slices": [{k: [round(x, 4) if isinstance(x, float) else x for x in v] for k, v in s.items()}
                              for s in slices]}, fh)

    with open(os.path.join(out_dir, stem + "_objects.json"), "w") as fh:
        json.dump({"source": os.path.basename(src),
                   "fields": "node = glTF node in group props; tag from Base 0x44; collide (smackable | box | "
                             "cylinder | none | static), mass kg and drivethrough from animdefs.txt",
                   "objects": props}, fh, indent=1)

    with open(os.path.join(out_dir, stem + "_lights.json"), "w") as fh:
        json.dump({"source": os.path.basename(src),
                   "fields": "id = flare in GameData/Render/flare.dat (flares.json) or emitter tag; position and "
                             "direction in glTF space: world, local to the prop node (props, keyed by node in "
                             "group props) or local to a library prototype (library, keyed by object tag)",
                   **lights}, fh, indent=1)
    flare_ids = {}
    for e in lights["world"] + [f for v in lights["props"].values() for f in v]:
        flare_ids[e["id"]] = flare_ids.get(e["id"], 0) + 1

    tris = sum(len(p[3]) // 3 for n in nodes for p in n["prims"].values())
    groups = {}
    for n in nodes:
        groups[n["group"]] = groups.get(n["group"], 0) + 1
    print(f"{src}: {len(nodes)} parts {groups}, {tris} triangles, textures {found}/{len(mat_info)}, "
          f"road {len(slices)} slices in {len(segments)} segments {length:.0f} m"
          + (f" (lap of {len(lap['segments'])} segments {lap['length_m']:.0f} m), " if lap else ", ") +
          f"start/finish slice {gates.get('start', {}).get('slice', '-')}/{gates.get('finish', {}).get('slice', '-')}, "
          f"placed objects {len(props)}, library prototypes skipped {stats['library_skipped']}, "
          f"flares {sum(flare_ids.values())} {dict(sorted(flare_ids.items()))}, emitters {len(lights['emitters'])}")


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
