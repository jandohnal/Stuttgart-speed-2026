"""Check converted models (glTF from crp2gltf.py / track2gltf.py) for flipped faces and holes.

One line per model on stdout, details in <stem>_check.json next to the model.

Checks:
- flipped: triangles whose winding disagrees with their stored vertex normals (seen from outside
  their back face is lit from the wrong side, and with back-face culling they vanish)
- dropped: triangles the converter had to drop (index out of range), from asset.extras
  (with the converter's own winding fixes: flipped_by_normal, flipped_up)
- down (tracks): road and terrain triangles facing down
- road holes (tracks): vertical rays across every SimD slice of <stem>_road.json that hit no solid
  (road, terrain, objects) triangle near the slice height (road_holes). On the main route's road
  with nothing below at all: FAIL; a seam narrower than 2 * CRACK or on the road edge (EDGE), off the main route, at the ends of a segment or with the
  surface at another height: WARN; beside the road (RAY_MARGIN): only counted

Usage:
    python3 tools/mesh_check.py decomposed/GameData/CarModel        # every glTF below, recursively
    python3 tools/mesh_check.py decomposed/GameData/Track/farmland/farmland.gltf
"""
import argparse
import json
import math
import os
import struct
import sys
from array import array

from crp import cross

FLIPPED_MAX = 0.005  # share of triangles
DOWN_MAX = 0.005
DOWN_Y = -0.1  # unit normal y below this faces down (walls around 0 are left alone)
TRACK_GROUPS = ("road", "terrain")  # must face up
SOLID_GROUPS = ("road", "terrain", "objects")  # the game collides with these (game/scripts/main.gd); rays may hit any
RAY_STEP = 0.5  # m across the road
RAY_MARGIN = 3.0  # m beside the road edges
RAY_HEIGHT = 5.0  # m; a hit must lie this close to the slice height
CRACK = 0.15  # m; a void with ground this far on both sides is a seam, not a hole
EDGE = 0.25  # m; the outermost road rays: SimD widths are not verified to end on the road mesh
END_SLICES = 5  # slices at the open end of a segment (beyond start and finish), ~30 m
CELL = 10.0  # m, spatial grid for the ray test
COMPONENTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def load(path):
    gl = json.load(open(path))
    buf = open(os.path.join(os.path.dirname(path), gl["buffers"][0]["uri"]), "rb").read()

    def accessor(i):
        a = gl["accessors"][i]
        view = gl["bufferViews"][a["bufferView"]]
        n = COMPONENTS[a["type"]]
        start = view.get("byteOffset", 0) + a.get("byteOffset", 0)
        out = array("f" if a["componentType"] == 5126 else "I")
        out.frombytes(buf[start:start + 4 * n * a["count"]])
        return out

    return gl, accessor


def matmul(a, b):
    """Column-major 4x4 product a * b."""
    return [sum(a[r + 4 * k] * b[k + 4 * c] for k in range(4)) for c in range(4) for r in range(4)]


def local_matrix(node):
    if "matrix" in node:
        return list(node["matrix"])
    t = node.get("translation", (0.0, 0.0, 0.0))
    return [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, t[0], t[1], t[2], 1]


def mesh_nodes(gl):
    """[(node, world matrix, group name or None)] for nodes with a mesh."""
    out = []

    def walk(i, parent, group):
        node = gl["nodes"][i]
        m = matmul(parent, local_matrix(node))
        if "mesh" in node:
            out.append((node, m, group))
        for c in node.get("children", []):
            walk(c, m, node["name"] if "mesh" not in node else group)

    for i in gl["scenes"][0]["nodes"]:
        walk(i, [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1], None)
    return out


def apply(m, p):
    x, y, z = p
    return (m[0] * x + m[4] * y + m[8] * z + m[12], m[1] * x + m[5] * y + m[9] * z + m[13],
            m[2] * x + m[6] * y + m[10] * z + m[14])


def check(path):
    gl, accessor = load(path)
    stem = os.path.splitext(os.path.basename(path))[0]
    road_path = os.path.join(os.path.dirname(path), stem + "_road.json")
    is_track = os.path.exists(road_path)
    tris = flipped = degenerate = down = surface = 0
    per_node = []
    ground = []  # world triangles of the solid groups (tracks)
    for node, m, group in mesh_nodes(gl):
        n_flip = n_tris = 0
        for prim in gl["meshes"][node["mesh"]]["primitives"]:
            pos = accessor(prim["attributes"]["POSITION"])
            nrm = accessor(prim["attributes"]["NORMAL"])
            idx = accessor(prim["indices"])
            for t in range(0, len(idx) - 2, 3):
                a, b, c = idx[t], idx[t + 1], idx[t + 2]
                ax, ay, az = pos[3 * a:3 * a + 3]
                ux, uy, uz = pos[3 * b] - ax, pos[3 * b + 1] - ay, pos[3 * b + 2] - az
                vx, vy, vz = pos[3 * c] - ax, pos[3 * c + 1] - ay, pos[3 * c + 2] - az
                nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
                n_tris += 1
                if nx * nx + ny * ny + nz * nz < 1e-14:
                    degenerate += 1
                    continue
                sx = nrm[3 * a] + nrm[3 * b] + nrm[3 * c]
                sy = nrm[3 * a + 1] + nrm[3 * b + 1] + nrm[3 * c + 1]
                sz = nrm[3 * a + 2] + nrm[3 * b + 2] + nrm[3 * c + 2]
                if nx * sx + ny * sy + nz * sz < 0.0:
                    n_flip += 1
                if is_track and group in SOLID_GROUPS:
                    w = [apply(m, pos[3 * i:3 * i + 3]) for i in (a, b, c)]
                    ground.append(w)
                if is_track and group in TRACK_GROUPS:
                    wy = (w[1][2] - w[0][2]) * (w[2][0] - w[0][0]) - (w[1][0] - w[0][0]) * (w[2][2] - w[0][2])
                    surface += 1
                    wl = math.dist(cross(*w), (0.0, 0.0, 0.0))
                    if wl > 1e-12 and wy / wl < DOWN_Y:
                        down += 1
        tris += n_tris
        flipped += n_flip
        if n_flip:
            per_node.append({"node": node["name"], "triangles": n_tris, "flipped": n_flip})
    extras = gl["asset"].get("extras", {})
    dropped = extras.get("dropped")
    result = {"model": os.path.basename(path), "triangles": tris, "flipped": flipped,
              "degenerate": degenerate, "dropped": dropped,
              "converter_flipped": {k: extras.get(k) for k in ("flipped_by_normal", "flipped_up")},
              "flipped_nodes": sorted(per_node, key=lambda e: -e["flipped"])}
    status = "OK"
    problems = []
    if tris and flipped / tris > FLIPPED_MAX:
        status = "FAIL"
        problems.append(f"flipped {100 * flipped / tris:.1f} %")
    if dropped:
        status = "FAIL"
        problems.append(f"dropped {dropped}")
    if dropped is None:
        problems.append("no converter stats")
    if is_track:
        result["ground_triangles"] = surface
        result["down"] = down
        if surface and down / surface > DOWN_MAX:
            status = "FAIL" if status == "FAIL" else "WARN"
            problems.append(f"down {100 * down / surface:.1f} %")
        holes = road_holes(json.load(open(road_path)), ground)
        result.update(holes)
        if holes["road_void"]:
            status = "FAIL"
            problems.append(f"road holes {holes['road_void']} rays at {len(holes['road_holes'])} slices")
        if holes["cracks"]:
            status = "FAIL" if status == "FAIL" else "WARN"
            problems.append(f"seams or road edge {holes['cracks']} rays")
        if holes["road_minor"]:
            status = "FAIL" if status == "FAIL" else "WARN"
            problems.append(f"road misses off the main route or offset {holes['road_minor']} rays "
                            f"at {len(holes['road_minor_slices'])} slices")
    result["status"] = status
    with open(os.path.join(os.path.dirname(path), stem + "_check.json"), "w") as fh:
        json.dump(result, fh, indent=1)
    line = (f"{status:4} {stem:16} {tris:7} tris  flipped {flipped:5} ({100 * flipped / max(tris, 1):4.1f} %)"
            f"  dropped {dropped if dropped is not None else '-'}")
    if is_track:
        line += f"  down {down}  holes {result['road_void']} cracks {result['cracks']} minor {result['road_minor']} margin {result['margin']}"
    if problems and status != "OK":
        line += "  <- " + ", ".join(problems)
    print(line)
    return result


def road_holes(road, ground):
    """Vertical rays across each slice (along its right vector) against the ground triangles.

    A ray that misses finds either nothing at any height ("void": the car falls through) or a
    surface more than RAY_HEIGHT above or below the slice ("offset": SimD and the geometry
    disagree, e.g. side routes). Void on the road of the main route (segment 0 and the lap),
    away from the ends of an open segment, is a hole."""
    slices, segments = road["slices"], road["segments"]
    main = set((road.get("lap") or {}).get("segments") or [0])
    grid = {}
    for k, (a, b, c) in enumerate(ground):
        x0, x1 = min(a[0], b[0], c[0]), max(a[0], b[0], c[0])
        z0, z1 = min(a[2], b[2], c[2]), max(a[2], b[2], c[2])
        for gx in range(math.floor(x0 / CELL), math.floor(x1 / CELL) + 1):
            for gz in range(math.floor(z0 / CELL), math.floor(z1 / CELL) + 1):
                grid.setdefault((gx, gz), []).append(k)

    def probe(x, z, y):
        found = "void"
        for k in grid.get((math.floor(x / CELL), math.floor(z / CELL)), ()):
            a, b, c = ground[k]
            d = (b[2] - c[2]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[2] - c[2])
            if abs(d) < 1e-12:
                continue
            l1 = ((b[2] - c[2]) * (x - c[0]) + (c[0] - b[0]) * (z - c[2])) / d
            l2 = ((c[2] - a[2]) * (x - c[0]) + (a[0] - c[0]) * (z - c[2])) / d
            l3 = 1.0 - l1 - l2
            if l1 >= -1e-6 and l2 >= -1e-6 and l3 >= -1e-6:
                if abs(l1 * a[1] + l2 * b[1] + l3 * c[1] - y) <= RAY_HEIGHT:
                    return "hit"
                found = "offset"
        return found

    counts = {"road_void": 0, "road_offset": 0, "road_minor": 0, "cracks": 0, "margin": 0}
    holes, minor = [], []
    for j, seg in enumerate(segments):
        for i in range(seg["first"], seg["last"] + 1):
            s = slices[i]
            p, r = s["position"], s["right"]
            left, right = s["widths"][0], s["widths"][1]
            end = not seg["closed"] and min(i - seg["first"], seg["last"] - i) < END_SLICES
            miss = {"void": 0, "offset": 0, "crack": 0, "margin": 0}
            void_at = []
            off = -left - RAY_MARGIN
            while off <= right + RAY_MARGIN + 1e-6:
                res = probe(p[0] + r[0] * off, p[2] + r[2] * off, p[1] + r[1] * off)
                if res == "void" and -left <= off <= right and (min(off + left, right - off) < EDGE or all(
                        probe(p[0] + r[0] * o, p[2] + r[2] * o, p[1] + r[1] * o) == "hit" for o in (off - CRACK, off + CRACK))):
                    res = "crack"  # a seam, or the road edge
                if res != "hit":
                    miss[res if -left <= off <= right else "margin"] += 1
                    if res == "void" and -left <= off <= right:
                        void_at.append(round(off, 1))
                off += RAY_STEP
            counts["margin"] += miss["margin"]
            counts["cracks"] += miss["crack"]
            if not (miss["void"] or miss["offset"]):
                continue
            entry = {"slice": i, "segment": j, "void": miss["void"], "offset": miss["offset"],
                     "void_at_m": void_at, "position": [round(x, 1) for x in p]}
            if miss["void"] and j in main and not end:
                counts["road_void"] += miss["void"]
                counts["road_offset"] += miss["offset"]
                holes.append(entry)
            else:
                counts["road_minor"] += miss["void"] + miss["offset"]
                minor.append({**entry, "reason": "end" if end else "side route" if j not in main else "offset"})
    return {**counts, "road_holes": holes, "road_minor_slices": minor}


def gltf_files(target):
    if os.path.isfile(target):
        return [target]
    found = []
    for root, dirs, files in os.walk(target):
        dirs.sort()
        found += [os.path.join(root, f) for f in sorted(files) if f.endswith(".gltf")]
    return found


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("targets", nargs="+", help="glTF files or folders")
    a = ap.parse_args()
    results = [check(p) for t in a.targets for p in gltf_files(t)]
    counts = {s: sum(1 for r in results if r["status"] == s) for s in ("OK", "WARN", "FAIL")}
    print(f"{len(results)} models: {counts['OK']} OK, {counts['WARN']} WARN, {counts['FAIL']} FAIL")
    sys.exit(1 if counts["FAIL"] else 0)


if __name__ == "__main__":
    main()
