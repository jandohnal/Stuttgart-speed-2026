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
- styles (cars with <stem>_styles.json, else the whole model as one style): with the nodes the
  style shows, triangles of two parts on top of each other (z-fighting, parts of two styles at
  once): duplicates (same corners) and coplanar overlaps (centroid inside a triangle of another
  part in the same plane, facing the same way; facing away: back_to_back, only counted). Parts
  laid flush on others on purpose (LAYERED: decals, lamps, plates ..., In / Out skins of a lid)
  and overlaps under OVERLAP_MIN triangles are counted apart (layered_overlaps).
  Open edges (used by one triangle only, corners welded at 1 mm, layered parts left out) as total length per style: the
  styles of one model should differ only by their own parts, so an outlier is a missing part.
  Other overlaps (a part doubled, parts of two styles at once): WARN
  Layered parts (LAYERED) closer than FLUSH to the part below them (z-fighting in the game, which
  draws both at one depth), or with corners sunk more than SUNK below it: WARN (layers)
- winding (cars): per part, shared edges whose two triangles disagree on the winding (corners
  welded at 1 mm, manifold edges only). Parts the game draws from their front only (ONE_SIDED:
  inner lid skins, interior, glass): WARN, their wrongly wound triangles are holes; others counted

Usage:
    python3 tools/mesh_check.py decomposed/GameData/CarModel        # every glTF below, recursively
    python3 tools/mesh_check.py decomposed/GameData/Track/farmland/farmland.gltf
"""
import argparse
import json
import math
import os
import re
import struct
import sys
from array import array
from collections import Counter

from crp import cross
from crp2gltf import LAYERED

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
    gl = json.load(open(path, encoding="utf-8"))
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
        holes = road_holes(json.load(open(road_path, encoding="utf-8")), ground)
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
    if not is_track:
        result["winding"] = winding_conflicts(gl, accessor)
        bad_winding = [w for w in result["winding"] if w["one_sided"]]
        if bad_winding:
            status = "FAIL" if status == "FAIL" else "WARN"
            problems.append("winding of one-sided parts " + ", ".join(w["node"] for w in bad_winding))
        result["styles"] = check_styles(path, gl, accessor)
        layers = sorted({f"{p['parts'][0]}/{p['parts'][1]}" for st in result["styles"] for p in st["layers"]})
        if layers:
            status = "FAIL" if status == "FAIL" else "WARN"
            problems.append("flush or sunk layers " + ", ".join(layers))
        bad = [st for st in result["styles"] if st["part_overlaps"]]
        if bad:
            status = "FAIL" if status == "FAIL" else "WARN"
            problems.append("overlapping parts in style " + ", ".join(str(st["style"]) for st in bad))
    result["status"] = status
    with open(os.path.join(os.path.dirname(path), stem + "_check.json"), "w", encoding="utf-8") as fh:
        json.dump(result, fh, indent=1)
    line = (f"{status:4} {stem:16} {tris:7} tris  flipped {flipped:5} ({100 * flipped / max(tris, 1):4.1f} %)"
            f"  dropped {dropped if dropped is not None else '-'}")
    if not is_track:
        opens = [st["open_edges_m"] for st in result["styles"]]
        line += f"  styles {len(opens)}  open edges {min(opens):.1f}-{max(opens):.1f} m"
    if is_track:
        line += f"  down {down}  holes {result['road_void']} cracks {result['cracks']} minor {result['road_minor']} margin {result['margin']}"
    if problems and status != "OK":
        line += "  <- " + ", ".join(problems)
    print(line)
    return result


WELD = 1000.0  # 1/m: corners closer than 1 mm are one vertex
PLANE_TOL = 0.002  # m: a centroid this close to another triangle's plane lies in it
PARALLEL = 0.999  # |cos| between normals of coplanar triangles
OVERLAP_CELL = 0.1  # m, grid for the overlap search


def car_triangles(gl, accessor):
    """{node name: [world triangle (3 points)]} of every mesh node."""
    out = {}
    for node, m, _ in mesh_nodes(gl):
        tris = out.setdefault(node["name"], [])
        for prim in gl["meshes"][node["mesh"]]["primitives"]:
            pos = accessor(prim["attributes"]["POSITION"])
            idx = accessor(prim["indices"])
            for t in range(0, len(idx) - 2, 3):
                tris.append([apply(m, pos[3 * i:3 * i + 3]) for i in idx[t:t + 3]])
    return out


# Parts the original lays flush on others on purpose (LAYERED, from the converter, which lifts them
# LIFT above the part below); and the inner and outer skins of one lid (HoodIn / HoodOut).
OVERLAP_MIN = 10  # triangles: smaller overlaps of other parts are edges touching, not a doubled part


def base_name(node):
    """Part name without the converter's _<geom>_<type>[_L|_R] suffix and trailing digits."""
    return re.sub(r"\d*_\d+_\d+(_[LR])*$", "", node)


def is_decal(name):
    return name.startswith("Decal")


def layered(a, b):
    """True for a pair of parts that overlap by design (LAYERED, or In / Out skins of one part)."""
    if any(base_name(n).startswith(LAYERED) for n in (a, b)):
        return True
    ka, kb = (re.sub(r"(In|Out)$", "", base_name(n)) for n in (a, b))
    return ka == kb and base_name(a) != base_name(b)


# Parts the game draws from their front only (materials.gd, _car_kind / _car_material): inner lid
# skins by name, interior and glass by texture page.
ONE_SIDED_PARTS = ("HoodIn", "TrunkIn", "MoveSpoilerIn")
ONE_SIDED_PAGES = ("interior", "glass", "intglass")


def winding_conflicts(gl, accessor):
    """[{node, edges, one_sided}] for parts with shared edges whose triangles disagree on the winding
    (one_sided: edges where one of the two triangles is drawn from its front only)."""
    key = lambda p: (round(p[0] * WELD), round(p[1] * WELD), round(p[2] * WELD))
    out = []
    for node, m, _ in mesh_nodes(gl):
        uses = {}
        by_name = base_name(node["name"]).startswith(ONE_SIDED_PARTS)
        for prim in gl["meshes"][node["mesh"]]["primitives"]:
            page = gl["materials"][prim["material"]]["name"].split(" ")[-1] if "material" in prim else ""
            one_sided = by_name or page in ONE_SIDED_PAGES
            pos = accessor(prim["attributes"]["POSITION"])
            idx = accessor(prim["indices"])
            for t in range(0, len(idx) - 2, 3):
                k = [key(pos[3 * i:3 * i + 3]) for i in idx[t:t + 3]]
                if len(set(k)) < 3:
                    continue
                for a, b in ((0, 1), (1, 2), (2, 0)):
                    uses.setdefault(frozenset((k[a], k[b])), []).append((k[a], one_sided))
        bad = [u for u in uses.values() if len(u) == 2 and u[0][0] == u[1][0]]
        if bad:
            out.append({"node": node["name"], "edges": len(bad), "one_sided": sum(1 for u in bad if u[0][1] or u[1][1])})
    return sorted(out, key=lambda e: -e["edges"])


FLUSH = 0.0002  # m: a layered part closer than this to the part below z-fights
SUNK = 0.0005  # m: corners of a layered part this far below the part it lies on are hidden in it
SUNK_MIN = 3  # corners: one or two are an end touching a curved surface (wiper on the glass)
LAYER_TOL = 0.005  # m: how far above or below a part a layered part's corner still lies on it
LAYER_PARALLEL = 0.9  # |cos| between the normals of a layered part and the part below


def layer_check(parts):
    """Layered parts on the parts below them: [{parts, min_mm, sunk}] with min_mm < FLUSH or sunk corners."""
    base = {name: tris for name, tris in parts.items() if not base_name(name).startswith(LAYERED)}
    planes, grid = [], {}
    for name, tris in base.items():
        for tri in tris:
            n = cross(*tri)
            length = math.sqrt(sum(c * c for c in n))
            if length < 1e-9:
                continue
            planes.append((name, tri, tuple(c / length for c in n)))
            lo = [min(p[i] for p in tri) - LAYER_TOL for i in range(3)]
            hi = [max(p[i] for p in tri) + LAYER_TOL for i in range(3)]
            for cx in range(math.floor(lo[0] / OVERLAP_CELL), math.floor(hi[0] / OVERLAP_CELL) + 1):
                for cy in range(math.floor(lo[1] / OVERLAP_CELL), math.floor(hi[1] / OVERLAP_CELL) + 1):
                    for cz in range(math.floor(lo[2] / OVERLAP_CELL), math.floor(hi[2] / OVERLAP_CELL) + 1):
                        grid.setdefault((cx, cy, cz), []).append(len(planes) - 1)
    found = {}
    for name, tris in parts.items():
        if name in base or is_decal(name) and not tris:
            continue
        for tri in tris:
            n = cross(*tri)
            length = math.sqrt(sum(c * c for c in n))
            if length < 1e-9:
                continue
            n = tuple(c / length for c in n)
            c = [sum(p[i] for p in tri) / 3.0 for i in range(3)]
            # Centre: how far above the part below (flush); corners: how far below it (sunk).
            for point, what in [(c, "centre")] + [(p, "corner") for p in tri]:
                cell = tuple(math.floor(point[i] / OVERLAP_CELL) for i in range(3))
                for j in grid.get(cell, ()):
                    other, otri, on = planes[j]
                    if sum(n[i] * on[i] for i in range(3)) < LAYER_PARALLEL:
                        continue
                    d = sum((point[i] - otri[0][i]) * on[i] for i in range(3))
                    if abs(d) > LAYER_TOL:
                        continue
                    foot = [point[i] - d * on[i] for i in range(3)]
                    if not inside(foot, otri, on):
                        continue
                    r = found.setdefault((name, other), {"min": LAYER_TOL, "sunk": 0})
                    if what == "centre":
                        r["min"] = min(r["min"], abs(d))
                    elif d < -SUNK:
                        r["sunk"] += 1
                    break
    return [{"parts": [a, b], "min_mm": round(r["min"] * 1000, 2), "sunk": r["sunk"]}
            for (a, b), r in sorted(found.items()) if r["min"] < FLUSH or r["sunk"] >= SUNK_MIN]


def style_check(parts):
    """Overlaps and open edges of the visible parts ({name: [triangles]})."""
    key = lambda p: (round(p[0] * WELD), round(p[1] * WELD), round(p[2] * WELD))
    seen, dup, edges = {}, Counter(), Counter()
    planes, grid = [], {}
    for name, tris in parts.items():
        for tri in tris:
            k = [key(p) for p in tri]
            if len(set(k)) < 3:
                continue
            # Layered parts lie on others with their own rim (LIFT above them): not open body edges.
            if not base_name(name).startswith(LAYERED):
                for a, b in ((0, 1), (1, 2), (2, 0)):
                    edges[frozenset((k[a], k[b]))] += 1
            corners = frozenset(k)
            other = seen.get(corners)
            if other is not None and other != name:
                dup[tuple(sorted((other, name)))] += 1
            seen.setdefault(corners, name)
            n = cross(*tri)
            length = math.sqrt(sum(c * c for c in n))
            if length < 1e-9:
                continue
            n = tuple(c / length for c in n)
            planes.append((name, tri, n))
            lo = [min(p[i] for p in tri) for i in range(3)]
            hi = [max(p[i] for p in tri) for i in range(3)]
            for cx in range(math.floor(lo[0] / OVERLAP_CELL), math.floor(hi[0] / OVERLAP_CELL) + 1):
                for cy in range(math.floor(lo[1] / OVERLAP_CELL), math.floor(hi[1] / OVERLAP_CELL) + 1):
                    for cz in range(math.floor(lo[2] / OVERLAP_CELL), math.floor(hi[2] / OVERLAP_CELL) + 1):
                        grid.setdefault((cx, cy, cz), []).append(len(planes) - 1)
    overlap, back = Counter(), Counter()
    for name, tri, n in planes:
        c = [sum(p[i] for p in tri) / 3.0 for i in range(3)]
        cell = tuple(math.floor(c[i] / OVERLAP_CELL) for i in range(3))
        for j in grid.get(cell, ()):
            other, otri, on = planes[j]
            facing = sum(n[i] * on[i] for i in range(3))
            if other == name or abs(facing) < PARALLEL:
                continue
            if abs(sum((c[i] - otri[0][i]) * on[i] for i in range(3))) > PLANE_TOL:
                continue
            if inside(c, otri, on):
                (overlap if facing > 0.0 else back)[tuple(sorted((name, other)))] += 1
                break
    open_len = 0.0
    for e, count in edges.items():
        if count == 1:
            a, b = tuple(e)
            open_len += math.dist(a, b) / WELD
    return dup, overlap, back, open_len


def inside(p, tri, n):
    """Point p (in the triangle's plane) inside the triangle with unit normal n."""
    for k in range(3):
        a, b = tri[k], tri[(k + 1) % 3]
        e = [b[i] - a[i] for i in range(3)]
        w = [p[i] - a[i] for i in range(3)]
        c = cross((0.0, 0.0, 0.0), e, w)
        if sum(c[i] * n[i] for i in range(3)) < -1e-9:
            return False
    return True


def check_styles(path, gl, accessor):
    """Per style: overlapping parts and open edge length (see the module doc)."""
    stem = os.path.splitext(os.path.basename(path))[0]
    styles_path = os.path.join(os.path.dirname(path), stem + "_styles.json")
    styles = json.load(open(styles_path, encoding="utf-8"))["styles"] if os.path.exists(styles_path) else [{"style": 0, "name": "", "hide": []}]
    parts = car_triangles(gl, accessor)
    out = []
    for st in styles:
        hidden = set(st["hide"])
        shown = {k: v for k, v in parts.items() if k not in hidden}
        dup, overlap, back, open_len = style_check(shown)
        pairs = overlap
        bad = {p: c for p, c in pairs.items() if not layered(*p) and c >= OVERLAP_MIN}
        out.append({"style": st["style"], "name": st["name"], "open_edges_m": round(open_len, 2),
                    "duplicates": sum(dup.values()), "overlaps": sum(overlap.values()),
                    "back_to_back": sum(back.values()),
                    "part_overlaps": [{"parts": list(p), "triangles": c} for p, c in sorted(bad.items(), key=lambda e: -e[1])],
                    "layered_overlaps": sum(c for p, c in pairs.items() if p not in bad),
                    "layers": layer_check(shown)})
    return out


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
