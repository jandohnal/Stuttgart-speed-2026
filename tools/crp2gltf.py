"""Convert an NFS5 car model (.crp) to glTF 2.0 for use as a private visual reference.

Format: docs/formats/crp.md. Structure follows CrpLib from LibOpenNFS (MIT).
Writes <out>.gltf, <out>.bin and one PNG atlas per texture page next to it, plus
<out>_damage.json (damage zones and detachable parts). Damage: every part carries one glTF morph
target per damage zone it belongs to ("dz0" .. "dz9"), the original's offsets for a fully damaged
car. Detachable parts (hood, engine lid, doors, lights ...) come off when their zone is fully
damaged; parts the original models as one mesh for both sides (lights, aprons, exhaust) are split
into _L / _R nodes so each side comes off on its own.
Styles (variants of the model, D-022): the parts of every [styleN] of the .tpg go into the glTF
(node <part>_<geom slot>_<type>) and <out>_styles.json lists per style the nodes to remove and the
atlases replacing the default style's (the style of the model's first car in nfs5.car). Parts that
only double another part (lower-detail stand-ins, copies) are left out; the inner skins of the lids
are turned away from the outer ones.

Usage:
    python3 tools/crp2gltf.py sources/GameData/CarModel/356a.crp decomposed/GameData/CarModel/356a/356a.gltf
    python3 tools/crp2gltf.py ... --level 3      # in-game LOD instead of the showroom model
    python3 tools/crp2gltf.py ... --all          # also parts no style uses, doubled parts and the driver
"""
import argparse
import json
import math
import os
import re
import struct
from collections import Counter

import car_colors
import fsh2png
from common import find_file
from crp import STATS, article_mesh, base_info, cross, entry_text, find, parse_crp, to_gltf, vectors, write_gltf

# Detail levels: 1-2 showroom ("fe"), 3-7 in-game LODs ("ig"); 0x8000 = damaged copy.
DAMAGED = 0x8000
BIL_DRIVER = 8
# Damage zones as found on the 356 A (centroids of their vertices); car front is -Z, right +X.
ZONE_NAMES = {0: "front_left", 1: "front", 2: "front_right", 3: "right", 4: "rear_right", 5: "rear",
              6: "rear_left", 7: "left", 8: "roof", 9: "bottom"}


# Parts that can come off: name -> kind; doors are grouped per side by their pivot (tr).
DETACHABLE = {"HoodOut": "hood", "HoodIn": "hood", "DecalHood": "hood",
              "TrunkOut": "engine_lid", "TrunkIn": "engine_lid", "DecalTrunk": "engine_lid",
              "DoorOut": "door", "DoorIn": "door", "DoorWindow": "door", "Handle": "door",
              "InteriorDoorGlass": "door", "SideMirrorLeft": "door", "License": "license",
              "Light1": "headlight", "Light3": "front_light", "Light2": "tail_light",
              "SkirtF": "front_apron", "SkirtR": "rear_apron", "Exhaust": "exhaust", "Spoiler": "spoiler"}
# Lids and the wing belong to their end of the car whatever their vertices say (935: hood mostly "left", wing "roof").
FIXED_ZONE = {"hood": 1, "engine_lid": 5, "spoiler": 5}
SPLIT_SIDES = {"Light1", "Light2", "Light3", "SkirtF", "SkirtR", "Exhaust"}  # one mesh for both sides
DETACH_MASS = {"hood": 12.0, "engine_lid": 10.0, "door": 25.0, "license": 0.5, "headlight": 1.5,
               "front_light": 1.0, "tail_light": 1.0, "front_apron": 4.0, "rear_apron": 4.0, "exhaust": 4.0,
               "spoiler": 8.0}


def split_sides(prims, sources):
    """Split a part's primitives by the side of each triangle's centre: {"L"|"R": (prims, sources)}."""
    out = {}
    for key, (pos, nrm, tex, idx) in prims.items():
        for t in range(0, len(idx), 3):
            tri = idx[t:t + 3]
            side = "L" if sum(pos[i][0] for i in tri) < 0.0 else "R"
            sp, ss = out.setdefault(side, ({}, {}))
            p2, n2, t2, i2, remap = sp.setdefault(key, ([], [], [], [], {}))
            s2 = ss.setdefault(key, [])
            for i in tri:
                if i not in remap:
                    remap[i] = len(p2)
                    p2.append(pos[i])
                    n2.append(nrm[i])
                    t2.append(tex[i])
                    s2.append(sources[key][i])
                i2.append(remap[i])
    return {side: ({k: v[:4] for k, v in sp.items()}, ss) for side, (sp, ss) in out.items()}


def damage_zones(d, art, level):
    """{zone: set of vt indices} from the part's dz entry, or {}.

    dz: u32 zone count, count x (i32 zone, i32 vertex count, i32 start), then u32 vertex indices
    grouped by zone (start/count index into that list)."""
    dz = find(art.sub, "dz", level)
    if dz is None or dz.length < 4:
        return {}
    n = struct.unpack_from("<I", d, dz.data)[0]
    base = dz.data + 4 + 12 * n
    zones = {}
    for z in range(n):
        zone, count, start = struct.unpack_from("<3i", d, dz.data + 4 + 12 * z)
        zones.setdefault(zone, set()).update(struct.unpack_from(f"<{count}I", d, base + 4 * start))
    return zones


def damage_targets(d, art, level, src):
    """Morph targets for one part: ({"names", key: [[offset per vertex] per zone]}, zone stats) or (None, {})."""
    zones = damage_zones(d, art, level)
    dvt = find(art.sub, "vt", DAMAGED | level)
    if not zones or dvt is None:
        return None, {}
    offsets = [to_gltf(v[:3]) for v in vectors(d, dvt, 4)]
    names = sorted(zones)
    targets = {"names": [f"dz{z}" for z in names]}
    for key, order in src.items():
        targets[key] = [[offsets[vi] if vi in zones[z] and vi < len(offsets) else (0.0, 0.0, 0.0) for vi in order]
                        for z in names]
    return targets, {z: [offsets[vi] for vi in vis if vi < len(offsets)] for z, vis in zones.items()}


def tpg_sections(text):
    """[(section name, {key: value})] in file order; keys lower case. Names repeat (file1.details)."""
    out, cur = [], None
    for line in text.splitlines():
        line = line.strip()
        m = re.match(r"^\[([^\]]+)\]$", line)
        if m:
            cur = (m.group(1).strip(), {})
            out.append(cur)
        elif cur is not None and "=" in line:
            k, v = line.split("=", 1)
            cur[1][k.strip().lower()] = v.strip()
    return out


def slot_types(kv):
    """Pairs geometryK=<slot>/typeK=<type> and textureK=<slot>/typeK=<type> -> [(kind, slot, type)]."""
    out = []
    for k, v in kv.items():
        m = re.match(r"(geometry|texture)(\d+)$", k)
        if m and v.lstrip("-").isdigit():
            out.append((m.group(1), int(v), int(kv.get("type" + m.group(2), 0))))
    return out


def read_styles(text):
    """[styleN] sections sorted by N: [{"index", "name", "geometry": {slot: type}, "texture": {slot: type}}].

    The original picks a car variant's parts by style: a geometry slot shows the parts of the type the
    style gives it (type 0 when not listed, nothing when the model has no part of that type)."""
    styles = []
    for name, kv in tpg_sections(text):
        m = re.match(r"style(\d+)$", name, re.I)
        if not m:
            continue
        st = {"index": int(m.group(1)), "name": kv.get("name", name), "geometry": {}, "texture": {}}
        for kind, slot, typ in slot_types(kv):
            st[kind][slot] = typ
        styles.append(st)
    return sorted(styles, key=lambda st: st["index"])


def read_entry_rules(text):
    """[fileN.<entry>] sections -> {(N - 1, entry): {"cond": [(kind, slot, type)], "frontend", "testdrive"}}.

    An FSH entry with a section is one of several alternatives for the same atlas area: it applies
    when any of its conditions holds (active type of that geometry or texture slot) and frontend /
    testdrive match. Repeated sections merge."""
    rules = {}
    for name, kv in tpg_sections(text):
        m = re.match(r"file(\d+)\.(\w+)$", name, re.I)
        if not m or m.group(2).lower() == "details":
            continue
        r = rules.setdefault((int(m.group(1)) - 1, m.group(2).lower()), {"cond": []})
        r["cond"] += slot_types(kv)
        for k in ("frontend", "testdrive"):
            if k in kv:
                r[k] = int(kv[k])
    return rules


# Driver textures (suit, face) follow the driver slot, whose parts are left out.
DRIVER_PAGES = {"suit", "head"}
# Showroom detail (level 1-2): the front-end texture variants, not the test drive ones.
FRONTEND, TESTDRIVE = 1, 0


def entry_applies(rule, style):
    """None: entry has no rule (always used); True / False: the alternative is / is not the style's."""
    if rule is None:
        return None
    if rule.get("frontend", FRONTEND) != FRONTEND or rule.get("testdrive", TESTDRIVE) != TESTDRIVE:
        return False
    if not rule["cond"]:
        return True
    return any(style[kind].get(slot, 0) == typ for kind, slot, typ in rule["cond"])


def read_tpg(path):
    """Return list of tpages: dict(file=index into file list or None, mirror_of, width, height)."""
    if not path or not os.path.exists(path):
        return None
    text = open(path, encoding="latin1").read()
    files = [f for _, f in sorted((int(k), v.strip()) for k, v in re.findall(r"^file(\d+)=(.*)$", text, re.M))]
    count = int(re.search(r"^numtpages=(\d+)", text, re.M).group(1))
    pages, next_file = [], 0
    for i in range(1, count + 1):
        m = re.search(rf"^\[tpage{i}\.details\]\n((?:[^\[\n].*\n?)*)", text, re.M)
        kv = dict(re.findall(r"^(\w+)=(.*)$", m.group(1), re.M)) if m else {}
        page = {"width": int(kv.get("width", 256)), "height": int(kv.get("height", 256))}
        if "sourcetpage" in kv:
            page["mirror_of"] = int(kv["sourcetpage"]) - 1
        else:
            page["file"] = next_file
            page["name"] = files[next_file] if next_file < len(files) else None
            next_file += 1
        pages.append(page)
    return pages


def fsh_images(fsh_bytes):
    """Decoded FSH entries: [(name, x0, y0, w, h, rgba)]."""
    out = []
    _, entries = fsh2png.parse(fsh_bytes)
    for e in entries:
        rec = next((r for r in e["records"] if (r[0] & 0x7F) in fsh2png.IMAGE_BPP), None)
        if rec is None:
            continue
        t, ew, eh, misc, px = rec
        base = t & 0x7F
        if t != base:
            px = fsh2png.decompress(px)[0]
        pal = next((fsh2png.decode_palette(r[0], r[4], r[1]) for r in e["records"] if r[0] in fsh2png.PALETTE_BPE), None)
        x0, y0 = struct.unpack_from("<hh", misc, 4)
        out.append((str(e.get("name", "")).strip().lower(), x0, y0, ew, eh, fsh2png.decode_image(base, ew, eh, px, pal)))
    return out


def build_atlas(images, w, h, choose=lambda name: None):
    """Compose a texture page from FSH entries at their stored positions.

    choose(entry name) -> None (no rule: always), True / False (alternative chosen or not, see
    entry_applies). Entries sharing an area: a chosen alternative wins over a plain entry, a plain
    entry over the first one; an area none applies to keeps its first entry so it is never empty."""
    groups = {}
    for img in images:
        groups.setdefault(img[1:5], []).append(img)
    order = []
    for rect, imgs in groups.items():
        picks = [(choose(i[0]), i) for i in imgs]
        plain = [i for c, i in picks if c is None]
        chosen = [i for c, i in picks if c]
        order.append((1, chosen[0]) if chosen else (0, plain[0]) if plain else (0, imgs[0]))
    atlas = bytearray(w * h * 4)
    # Plain entries first so a chosen alternative wins where areas overlap without matching.
    for _, (name, x0, y0, ew, eh, rgba) in sorted(order, key=lambda o: o[0]):
        for y in range(eh):
            if 0 <= y0 + y < h:
                x1 = min(ew, w - x0)
                if x1 > 0:
                    dst = ((y0 + y) * w + x0) * 4
                    atlas[dst:dst + x1 * 4] = rgba[y * ew * 4:(y * ew + x1) * 4]
    return bytes(atlas)


def load_textures(d, misc, tpg_path, out_dir, stem, styles=(), default=0):
    """Return ({tpage index: png filename} for the default style, [{tpage index: png} per style])."""
    pages = read_tpg(tpg_path)
    if pages is None:
        return {}, []
    rules = read_entry_rules(open(tpg_path, encoding="latin1").read())
    embedded = {e.index: d[e.data:e.data + e.length] for e in misc if e.tag == "sf"}
    car_dir = os.path.dirname(tpg_path)
    sources = {}
    for i, p in enumerate(pages):
        if "file" not in p:
            continue
        data = embedded.get(p["file"])
        if data is None and p.get("name"):  # shared textures (Suit, Head, Cabrio) live next to the .crp
            path = find_file(car_dir, os.path.splitext(p["name"])[0] + ".fsh")
            data = open(path, "rb").read() if path else None
        if data is not None:
            sources[i] = fsh_images(data)
    variants = list(styles) or [None]
    per_style = [{} for _ in variants]
    written = {}  # (page, rgba) -> png
    # The default style first so its atlases get the plain names (<stem>_tpage<n>.png).
    for s in [default] + [k for k in range(len(variants)) if k != default]:
        st = variants[s]
        images = {}
        for i, imgs in sources.items():
            f = pages[i]["file"]
            driver = os.path.splitext(pages[i].get("name") or "")[0].lower() in DRIVER_PAGES
            choose = (lambda name, f=f, st=st: entry_applies(rules.get((f, name)), st)) if st and not driver \
                else (lambda name: None)
            images[i] = build_atlas(imgs, pages[i]["width"], pages[i]["height"], choose)
        # A "sourcetpage" page is a copy of its source (own page so each side can take its own damage), not a flip.
        for i, p in enumerate(pages):
            if "mirror_of" in p and p["mirror_of"] in images:
                images[i] = images[p["mirror_of"]]
        for i, rgba in images.items():
            p = pages[i] if "file" in pages[i] else pages[pages[i]["mirror_of"]]
            key = (i, rgba)
            if key not in written:
                fn = f"{stem}_tpage{i + 1}.png" if s == default else f"{stem}_tpage{i + 1}_style{st['index']}.png"
                fsh2png.write_png(os.path.join(out_dir, fn), p["width"], p["height"], rgba)
                written[key] = fn
            per_style[s][i] = written[key]
    return per_style[default], per_style if styles else []


def default_style(styles, model, cars_path):
    """Position in styles of the style the glTF's own textures show: the one of the model's first
    variant in FEData/Data/nfs5.car (the menu's first car of the model), else the first style."""
    if not styles:
        return 0
    if cars_path and os.path.exists(cars_path):
        first = car_colors.model_styles(open(cars_path, "rb").read()).get(model.lower(), [])
        for k, st in enumerate(styles):
            if first and st["index"] == first[0]:
                return k
    return 0


def find_cars(src):
    """FEData/Data/nfs5.car of the installation the .crp comes from (GameData/CarModel/<model>.crp)."""
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(src))))
    data = find_file(root, "FEData")
    data = data and find_file(data, "Data")
    return data and find_file(data, "nfs5.car")


TOP_SLOTS = (37, 41)
TOP_MIN_DROP = 0.05  # m: a lowered top is at least this much lower than the raised one
SHOWROOM = (1, 2)  # detail levels of the front-end model
COVER_TOL = 0.01  # m: a triangle centre this close to another part's surface is covered by it
COVER_SHARE = 0.8  # share of a part's triangles covered for it to be a duplicate
COVER_CELL = 0.1  # m, grid for the cover search
COPY_MIN = 4  # triangles; gauge needles are single triangles on top of each other
COPY_SHARE = 0.95  # share covered by one part of about the same size for a part at the requested level to be its copy


def point_triangle_distance(p, a, b, c):
    """Distance from p to triangle abc (closest point by region, Ericson 5.1.5)."""
    sub = lambda u, v: (u[0] - v[0], u[1] - v[1], u[2] - v[2])
    dot = lambda u, v: u[0] * v[0] + u[1] * v[1] + u[2] * v[2]
    ab, ac, ap = sub(b, a), sub(c, a), sub(p, a)
    d1, d2 = dot(ab, ap), dot(ac, ap)
    if d1 <= 0 and d2 <= 0:
        return math.dist(p, a)
    bp = sub(p, b)
    d3, d4 = dot(ab, bp), dot(ac, bp)
    if d3 >= 0 and d4 <= d3:
        return math.dist(p, b)
    vc = d1 * d4 - d3 * d2
    if vc <= 0 and d1 >= 0 and d3 <= 0:
        t = d1 / (d1 - d3) if d1 != d3 else 0.0
        return math.dist(p, tuple(a[i] + t * ab[i] for i in range(3)))
    cp = sub(p, c)
    d5, d6 = dot(ab, cp), dot(ac, cp)
    if d6 >= 0 and d5 <= d6:
        return math.dist(p, c)
    vb = d5 * d2 - d1 * d6
    if vb <= 0 and d2 >= 0 and d6 <= 0:
        t = d2 / (d2 - d6) if d2 != d6 else 0.0
        return math.dist(p, tuple(a[i] + t * ac[i] for i in range(3)))
    va = d3 * d6 - d5 * d4
    if va <= 0 and d4 - d3 >= 0 and d5 - d6 >= 0:
        t = (d4 - d3) / ((d4 - d3) + (d5 - d6)) if (d4 - d3) + (d5 - d6) else 0.0
        return math.dist(p, tuple(b[i] + t * (c[i] - b[i]) for i in range(3)))
    den = va + vb + vc
    if abs(den) < 1e-18:
        return min(math.dist(p, a), math.dist(p, b), math.dist(p, c))
    v, w = vb / den, vc / den
    return math.dist(p, tuple(a[i] + ab[i] * v + ac[i] * w for i in range(3)))


def mesh_triangles(mesh):
    """World (car space) triangles of an article_mesh result."""
    offset, prims = mesh[0], mesh[1]
    out = []
    for pos, _, _, idx in prims.values():
        for t in range(0, len(idx) - 2, 3):
            out.append([tuple(pos[i][k] + offset[k] for k in range(3)) for i in idx[t:t + 3]])
    return out


def redundant_lods(candidates, level, styles):
    """Indices of candidates that are lower-detail stand-ins duplicating parts of the requested level.

    A part without the requested level falls back to a less detailed one. Some of those only exist
    as a low-detail copy of something the requested level already has: dropped when their slot
    (geom, type) has a part at the requested level, or when COVER_SHARE of them lies on such parts (935 and GT1: the wing is in
    the showroom Body, separate Spoiler at levels 3-6; 935, 964, GT1: SideMirrorLeft / Right at
    levels 2-5 next to SideMirror at level 1), so both would be drawn on top of each other. Others are the only version of the
    part (f901 roof, tyre treads, cop and factory models). A fallback part is dropped when
    COVER_SHARE of its triangle centres lie within COVER_TOL of showroom parts shown in every style
    that shows it."""
    if level not in SHOWROOM:
        return set()
    every = set(range(len(styles))) or {0}
    vis = lambda slot: {k for k, st in enumerate(styles) if style_shows(st, slot)} if styles else every
    # The two convertible tops share their rear body: never each other's duplicate.
    showroom = [(k, c[3], mesh_triangles(c[5])) for k, c in enumerate(candidates)
                if c[4] == level and c[3][0] not in TOP_SLOTS]
    out = set()
    for k, c in enumerate(candidates):
        if c[4] == level or c[3][0] in TOP_SLOTS:
            continue
        # Slot 0 holds unrelated small parts; a stand-in is on the same texture pages as its part.
        same_slot = [candidates[j][2].strip() for j, slot, _ in showroom
                     if slot == c[3] and slot[0] != 0 and set(candidates[j][5][1]) == set(c[5][1])]
        if same_slot:
            out.add(k)
            print(f"  {c[2].strip()} (slot {c[3][0]} type {c[3][1]}, level {c[4]}): stand-in for {', '.join(same_slot)} "
                  f"of the same slot, left out")
            continue
        grid = cover_grid([tris for _, slot, tris in showroom if vis(c[3]) <= vis(slot)])
        tris = mesh_triangles(c[5])
        covered = covered_count(tris, grid)
        if tris and covered >= COVER_SHARE * len(tris):
            out.add(k)
            print(f"  {c[2].strip()} (slot {c[3][0]} type {c[3][1]}, level {c[4]}): duplicates showroom parts "
                  f"({covered}/{len(tris)} triangles), left out")
    # Copies at the requested level: a part (nearly) identical to another one shown in all its styles,
    # on the same texture pages (outer and inner glass are meant to overlap, as are the In / Out
    # skins of the lids).
    for k, c in enumerate(candidates):
        if k in out or c[4] != level or c[3][0] in TOP_SLOTS or re.search(r"(In|Out)\d*$", c[2].strip()):
            continue
        tris = mesh_triangles(c[5])
        if len(tris) < COPY_MIN:
            continue
        for j, slot, other in showroom:
            if j == k or j in out or not vis(c[3]) <= vis(slot) or not abs(len(other) - len(tris)) <= 0.1 * len(tris) \
                    or set(c[5][1]) != set(candidates[j][5][1]):
                continue
            # Keep the part that comes off with the door (SideMirrorLeft) over its plain copy.
            if DETACHABLE.get(c[2].strip()) and not DETACHABLE.get(candidates[j][2].strip()):
                continue
            covered = covered_count(tris, cover_grid([other]))
            if covered >= COPY_SHARE * len(tris):
                out.add(k)
                print(f"  {c[2].strip()} (slot {c[3][0]} type {c[3][1]}): copy of {candidates[j][2].strip()} "
                      f"(slot {slot[0]} type {slot[1]}, {covered}/{len(tris)} triangles), left out")
                break
    return out


# Inner skin of a lid -> its outer skin (part names). They lie in one plane; the inner one must face
# away from the outer one, or seen from outside the two z-fight (901, 914: the luggage-space texture
# showed through the front lid). The game draws inner skins from their front only (materials.gd).
INNER_SKINS = {"HoodIn": "HoodOut", "TrunkIn": "TrunkOut", "MoveSpoilerIn": "MoveSpoiler"}
SKIN_DIST = 0.05  # m: an inner triangle takes its side from the outer triangle nearest to its centre


def orient_inner_skins(candidates):
    """Turn every triangle of an inner skin (INNER_SKINS) to face away from the nearest triangle of
    its outer skin and recompute its normals from the faces. Stored winding and normals of the inner
    skins are mixed (half of the 356 A HoodIn faces up, half down)."""
    flipped = 0
    for inner, outer in INNER_SKINS.items():
        outs = [mesh_triangles(c[5]) for c in candidates if c[2].strip() == outer]
        if not outs:
            continue
        faces = []
        for tris in outs:
            for tri in tris:
                n = cross(*tri)
                length = math.sqrt(sum(x * x for x in n))
                if length > 1e-12:
                    faces.append((tuple(sum(p[i] for p in tri) / 3.0 for i in range(3)), tuple(x / length for x in n)))
        grid = {}
        for f in faces:
            grid.setdefault(tuple(math.floor(f[0][i] / SKIN_DIST) for i in range(3)), []).append(f)
        for c in candidates:
            if c[2].strip() != inner:
                continue
            offset, prims = c[5][0], c[5][1]
            for pos, nrm, _, idx in prims.values():
                for t in range(0, len(idx) - 2, 3):
                    tri = [tuple(pos[i][k] + offset[k] for k in range(3)) for i in idx[t:t + 3]]
                    n = cross(*tri)
                    centre = tuple(sum(p[i] for p in tri) / 3.0 for i in range(3))
                    cell = tuple(math.floor(centre[i] / SKIN_DIST) for i in range(3))
                    near = [f for dx in (-1, 0, 1) for dy in (-1, 0, 1) for dz in (-1, 0, 1)
                            for f in grid.get((cell[0] + dx, cell[1] + dy, cell[2] + dz), ())]
                    if not near:
                        continue
                    on = min(near, key=lambda f: math.dist(f[0], centre))[1]
                    if sum(n[i] * on[i] for i in range(3)) > 0.0:
                        idx[t], idx[t + 1] = idx[t + 1], idx[t]
                        flipped += 1
                # Normals from the faces as they now are (area weighted): away from the outer skin.
                acc = {}
                for t in range(0, len(idx) - 2, 3):
                    n = cross(*(pos[i] for i in idx[t:t + 3]))
                    for i in idx[t:t + 3]:
                        a = acc.setdefault(i, [0.0, 0.0, 0.0])
                        for k in range(3):
                            a[k] += n[k]
                for i, a in acc.items():
                    length = math.sqrt(sum(x * x for x in a))
                    if length > 1e-12:
                        nrm[i] = tuple(x / length for x in a)
    if flipped:
        print(f"  inner skins: {flipped} triangles turned away from their outer skin")


def cover_grid(tri_lists):
    grid = {}
    for tris in tri_lists:
        for tri in tris:
            lo = [math.floor((min(p[i] for p in tri) - COVER_TOL) / COVER_CELL) for i in range(3)]
            hi = [math.floor((max(p[i] for p in tri) + COVER_TOL) / COVER_CELL) for i in range(3)]
            for x in range(lo[0], hi[0] + 1):
                for y in range(lo[1], hi[1] + 1):
                    for z in range(lo[2], hi[2] + 1):
                        grid.setdefault((x, y, z), []).append(tri)
    return grid


def covered_count(tris, grid):
    """Triangles of tris whose centre lies within COVER_TOL of a triangle in the grid."""
    covered = 0
    for tri in tris:
        centre = tuple(sum(p[i] for p in tri) / 3.0 for i in range(3))
        cell = tuple(math.floor(centre[i] / COVER_CELL) for i in range(3))
        if any(point_triangle_distance(centre, *o) <= COVER_TOL for o in grid.get(cell, ())):
            covered += 1
    return covered


def style_shows(style, slot):
    """True when the style shows the part of this (geom slot, type)."""
    return style["geometry"].get(slot[0], 0) == slot[1]


def write_styles(path, src, styles, default, nodes, slots, pngs, style_pngs, material_spec):
    """<stem>_styles.json: per style the nodes to remove and the atlases replacing the default ones."""
    out = []
    for k, st in enumerate(styles):
        hidden = sorted(n["name"] for n in nodes if not style_shows(st, n["slot"]))
        # Convertible top: slots TOP_SLOTS are the rear body with the top up and with it down (named
        # Cabrio / CabrioUp / CabrioDown by model); a style lists both and the game shows one. Down
        # (the lower one) by default, "top_up" swaps them.
        top = {}
        for slot in TOP_SLOTS:
            names = [n for n in nodes if n["slot"][0] == slot and style_shows(st, n["slot"])]
            if names:
                top[slot] = names
        top_up = None
        if len(top) == len(TOP_SLOTS):
            height = {slot: max(v[1] + n["offset"][1] for n in ns for prim in n["prims"].values() for v in prim[0])
                      for slot, ns in top.items()}
            up, down = sorted(TOP_SLOTS, key=lambda slot: (-round(height[slot], 2), -slot))
            hidden = sorted(set(hidden) | {n["name"] for n in top[up]})
            # Same height: two copies of the raised top (356, 356 B, 993, 996 have no lowered one
            # at showroom detail), the second one is just left off.
            if height[up] - height[down] > TOP_MIN_DROP:
                top_up = {"hide": sorted(n["name"] for n in top[down]), "show": sorted(n["name"] for n in top[up])}
        textures = {material_spec(i)["name"]: fn for i, fn in sorted(style_pngs[k].items()) if pngs.get(i) != fn}
        # Slots the style sets to a type the model has no part for: the part is left off (roof of a cabrio ...).
        empty = sorted(g for g, t in st["geometry"].items() if (g, t) not in slots)
        out.append({"style": st["index"], "name": st["name"], "geometry": {str(g): t for g, t in sorted(st["geometry"].items())},
                    "texture": {str(g): t for g, t in sorted(st["texture"].items())}, "empty_slots": empty,
                    "hide": hidden, "textures": textures})
        if top_up:
            out[-1]["top_up"] = top_up
    with open(path, "w") as fh:
        json.dump({"source": os.path.basename(src), "default": styles[default]["index"],
                   "fields": "styles from the .tpg [styleN]: geometry slot -> part type (unlisted: 0), texture "
                             "slot -> type; hide: glTF nodes of other styles to remove (convertibles: and the rear "
                             "body with the top up); top_up: nodes to remove instead / keep for the top up; "
                             "textures: material name -> atlas PNG replacing the glTF one (the default style's)",
                   "styles": out}, fh, indent=1)


def convert(src, out_path, level=1, include_all=False, tpg=None, cars=None):
    d, arts, misc = parse_crp(open(src, "rb").read())
    STATS.clear()
    out_dir = os.path.dirname(os.path.abspath(out_path))
    os.makedirs(out_dir, exist_ok=True)
    stem = os.path.splitext(os.path.basename(out_path))[0]
    tpg = tpg or os.path.splitext(src)[0] + ".tpg"
    styles = read_styles(open(tpg, encoding="latin1").read()) if os.path.exists(tpg) else []
    default = default_style(styles, os.path.splitext(os.path.basename(src))[0], cars or find_cars(src))
    pngs, style_pngs = load_textures(d, misc, tpg, out_dir, stem, styles, default)
    geom_slots = {info["geom_index"] for info in map(lambda art: base_info(d, art), arts) if info is not None}
    # Parts some style shows (geom slot, type); without styles the base car (type 0 everywhere).
    shown = {(slot, st["geometry"].get(slot, 0)) for st in styles for slot in geom_slots} if styles \
        else {(slot, 0) for slot in geom_slots}
    materials = {e.index: struct.unpack_from("<i", d, e.data + 0x28)[0] for e in misc if e.tag == "mt"}
    nodes, skipped, zone_acc, detach, slots = [], 0, {}, {}, set()
    candidates = []
    for art in arts:
        name_e, base = find(art.sub, "Name"), base_info(d, art)
        if name_e is None or base is None or find(art.sub, "ef") is not None:
            continue
        name = entry_text(d, name_e)
        part_slot = (base["geom_index"], base["type_index"])
        slots.add(part_slot)
        if not include_all and ((base["level_index"] >> 4) & BIL_DRIVER or part_slot not in shown):
            skipped += 1
            continue
        # Use the requested level, or the closest less detailed one the part has.
        lev = level if level in base["levels"] else min((l for l in base["levels"] if l > level), default=None)
        if lev is None:
            continue
        mesh = article_mesh(d, art, lev, lev, materials, sources=True)
        if mesh and mesh[1]:
            candidates.append((art, base, name, part_slot, lev, mesh))
    redundant = set() if include_all else redundant_lods(candidates, level, styles)
    orient_inner_skins(candidates)
    skipped += len(redundant)
    for k, (art, base, name, part_slot, lev, mesh) in enumerate(candidates):
        if k in redundant:
            continue
        if True:
            offset, prims, vertex_sources = mesh
            zones = damage_zones(d, art, lev)
            verts = [to_gltf(v[:3]) for v in vectors(d, find(art.sub, "vt", lev), 4)]
            node_name = f"{name}_{base['geom_index']}_{base['type_index']}"
            kind = DETACHABLE.get(name.strip())
            parts = split_sides(prims, vertex_sources) if name.strip() in SPLIT_SIDES else {"": (prims, vertex_sources)}
            for side, (side_prims, side_sources) in sorted(parts.items()):
                targets, stats = damage_targets(d, art, lev, side_sources)
                for z, offs in stats.items():
                    acc = zone_acc.setdefault(z, [0.0, 0.0, 0.0, 0, 0.0])
                    acc[4] = max([acc[4]] + [math.hypot(*o) for o in offs])
                full_name = f"{node_name}_{side}" if side else node_name
                nodes.append({"name": full_name, "offset": offset, "prims": side_prims, "targets": targets,
                              "slot": part_slot})
                if kind:
                    group = kind
                    if kind == "door":
                        group += "_left" if offset[0] < 0.0 else "_right"
                    elif side:
                        group += "_left" if side == "L" else "_right"
                    entry = detach.setdefault(group, {"kind": kind, "nodes": [], "zones": Counter()})
                    entry["nodes"].append(full_name)
                    used = {vi for src_list in side_sources.values() for vi in src_list}
                    for z, vis in zones.items():
                        entry["zones"][z] += len(used & vis)
            for z, vis in zones.items():
                acc = zone_acc.setdefault(z, [0.0, 0.0, 0.0, 0, 0.0])
                for vi in vis:
                    if vi < len(verts):
                        for k in range(3):
                            acc[k] += verts[vi][k] + offset[k]
                        acc[3] += 1

    pages = read_tpg(tpg) or []

    def page_kind(tpage):
        """Texture file of a page without extension (exterior, glass, intglass ...); the game picks materials by it."""
        if not 0 <= tpage < len(pages):
            return ""
        p = pages[tpage]
        if "mirror_of" in p and 0 <= p["mirror_of"] < len(pages):
            p = pages[p["mirror_of"]]
        return os.path.splitext(p.get("name") or "")[0].lower()

    def material_spec(tpage):
        name = f"tpage{tpage + 1} {page_kind(tpage)}".strip() if tpage >= 0 else "untextured"
        return {"name": name, "uri": pngs.get(tpage), "alpha": "MASK"}

    # Left and right copies of a part (doors, wheels) share a name: suffix the side so every node is unique.
    counts = Counter(n["name"] for n in nodes)
    renamed = {}
    for n in nodes:
        if counts[n["name"]] > 1:
            new = f"{n['name']}_{'L' if n['offset'][0] < 0.0 else 'R'}"
            renamed[(n["name"], n["offset"][0] < 0.0)] = new
            n["name"] = new
    for g, e in detach.items():
        left = g.endswith("_left")
        e["nodes"] = [renamed.get((name, left), name) for name in e["nodes"]]
    write_gltf(out_path, nodes, material_spec, "stuttgart-speed crp2gltf",
               {k: STATS[k] for k in ("dropped", "flipped_by_normal", "flipped_up")})
    zones = [{"zone": z, "name": ZONE_NAMES.get(z, f"zone{z}"), "blend_shape": f"dz{z}",
              "centroid": [round(acc[k] / acc[3], 3) for k in range(3)], "vertices": acc[3],
              "max_offset_m": round(acc[4], 3)} for z, acc in sorted(zone_acc.items()) if acc[3]]
    detachable = [{"group": g, "kind": e["kind"], "nodes": e["nodes"],
                   "zone": FIXED_ZONE.get(e["kind"], max(sorted(e["zones"]), key=lambda z: e["zones"][z]) if e["zones"] else -1),
                   "mass_kg": DETACH_MASS.get(e["kind"], 3.0)} for g, e in sorted(detach.items())]
    with open(os.path.join(out_dir, stem + "_damage.json"), "w") as fh:
        json.dump({"source": os.path.basename(src),
                   "fields": "zones: id, name (as seen on the 356 A), blend shape on every part in it, centroid "
                             "of its vertices (glTF, m), max dent of a fully damaged car (m); detachable: group "
                             "of nodes that comes off when its zone (most of its vertices) is fully damaged, "
                             "estimated mass",
                   "zones": zones, "detachable": detachable}, fh, indent=1)
    if styles:
        write_styles(os.path.join(out_dir, stem + "_styles.json"), src, styles, default, nodes, slots, pngs,
                     style_pngs, material_spec)
    tris = sum(len(p[3]) // 3 for n in nodes for p in n["prims"].values())
    morphed = sum(1 for n in nodes if n.get("targets"))
    print(f"{src}: {len(nodes)} parts ({morphed} with damage targets), {tris} triangles, {len(pngs)} texture pages, "
          f"{len(zones)} damage zones, {len(detachable)} detachable groups, {len(styles)} styles, "
          f"{skipped} unused or driver parts skipped")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("src")
    ap.add_argument("out")
    ap.add_argument("--level", type=int, default=1, help="detail level: 1-2 showroom, 3-7 in-game")
    ap.add_argument("--all", action="store_true", help="include variant and driver parts")
    ap.add_argument("--tpg", help="texture page config (default: <src>.tpg)")
    ap.add_argument("--cars", help="front-end car database for the default style (default: FEData/Data/nfs5.car)")
    a = ap.parse_args()
    convert(a.src, a.out, a.level, a.all, a.tpg, a.cars)


if __name__ == "__main__":
    main()
