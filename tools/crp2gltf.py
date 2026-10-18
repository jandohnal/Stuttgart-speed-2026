"""Convert an NFS5 car model (.crp) to glTF 2.0 for use as a private visual reference.

Format: docs/formats/crp.md. Structure follows CrpLib from LibOpenNFS (MIT).
Writes <out>.gltf, <out>.bin and one PNG atlas per texture page next to it, plus
<out>_damage.json (damage zones and detachable parts). Damage: every part carries one glTF morph
target per damage zone it belongs to ("dz0" .. "dz9"), the original's offsets for a fully damaged
car. Detachable parts (hood, engine lid, doors, lights ...) come off when their zone is fully
damaged; parts the original models as one mesh for both sides (lights, aprons, exhaust) are split
into _L / _R nodes so each side comes off on its own.

Usage:
    python3 tools/crp2gltf.py sources/GameData/CarModel/356a.crp decomposed/GameData/CarModel/356a/356a.gltf
    python3 tools/crp2gltf.py ... --level 3      # in-game LOD instead of the showroom model
    python3 tools/crp2gltf.py ... --all          # also variant parts (styles, driver)
"""
import argparse
import json
import math
import os
import re
import struct
from collections import Counter

import fsh2png
from common import find_file
from crp import STATS, article_mesh, base_info, entry_text, find, parse_crp, to_gltf, vectors, write_gltf

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


def build_atlas(fsh_bytes, w, h):
    """Compose a texture page from FSH entries at their stored positions (first entry wins)."""
    atlas = bytearray(w * h * 4)
    taken = set()
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
        if (x0, y0, ew, eh) in taken:
            continue  # alternative texture (style, damage) for the same slot
        taken.add((x0, y0, ew, eh))
        rgba = fsh2png.decode_image(base, ew, eh, px, pal)
        for y in range(eh):
            if 0 <= y0 + y < h:
                x1 = min(ew, w - x0)
                if x1 > 0:
                    dst = ((y0 + y) * w + x0) * 4
                    atlas[dst:dst + x1 * 4] = rgba[y * ew * 4:(y * ew + x1) * 4]
    return bytes(atlas)


def load_textures(d, misc, tpg_path, out_dir, stem):
    """Return {tpage index: png filename}."""
    pages = read_tpg(tpg_path)
    if pages is None:
        return {}
    embedded = {e.index: d[e.data:e.data + e.length] for e in misc if e.tag == "sf"}
    car_dir = os.path.dirname(tpg_path)
    images, pngs = {}, {}
    for i, p in enumerate(pages):
        if "file" not in p:
            continue
        data = embedded.get(p["file"])
        if data is None and p.get("name"):  # shared textures (Suit, Head, Cabrio) live next to the .crp
            path = find_file(car_dir, os.path.splitext(p["name"])[0] + ".fsh")
            data = open(path, "rb").read() if path else None
        if data is None:
            continue
        images[i] = build_atlas(data, p["width"], p["height"])
    # A "sourcetpage" page is a copy of its source (own page so each side can take its own damage), not a flip.
    for i, p in enumerate(pages):
        if "mirror_of" in p and p["mirror_of"] in images:
            images[i] = images[p["mirror_of"]]
    for i, rgba in images.items():
        p = pages[i] if "file" in pages[i] else pages[pages[i]["mirror_of"]]
        fn = f"{stem}_tpage{i + 1}.png"
        fsh2png.write_png(os.path.join(out_dir, fn), p["width"], p["height"], rgba)
        pngs[i] = fn
    return pngs


def convert(src, out_path, level=1, include_all=False, tpg=None):
    d, arts, misc = parse_crp(open(src, "rb").read())
    STATS.clear()
    out_dir = os.path.dirname(os.path.abspath(out_path))
    os.makedirs(out_dir, exist_ok=True)
    stem = os.path.splitext(os.path.basename(out_path))[0]
    tpg = tpg or os.path.splitext(src)[0] + ".tpg"
    pngs = load_textures(d, misc, tpg, out_dir, stem)
    materials = {e.index: struct.unpack_from("<i", d, e.data + 0x28)[0] for e in misc if e.tag == "mt"}
    nodes, skipped, zone_acc, detach = [], 0, {}, {}
    for art in arts:
        name_e, base = find(art.sub, "Name"), base_info(d, art)
        if name_e is None or base is None or find(art.sub, "ef") is not None:
            continue
        name = entry_text(d, name_e)
        if not include_all and (base["type_index"] != 0 or (base["level_index"] >> 4) & BIL_DRIVER):
            skipped += 1
            continue
        # Use the requested level, or the closest more detailed one the part has.
        lev = level if level in base["levels"] else min((l for l in base["levels"] if l > level), default=None)
        if lev is None:
            continue
        mesh = article_mesh(d, art, lev, lev, materials, sources=True)
        if mesh and mesh[1]:
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
                nodes.append({"name": full_name, "offset": offset, "prims": side_prims, "targets": targets})
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
    tris = sum(len(p[3]) // 3 for n in nodes for p in n["prims"].values())
    morphed = sum(1 for n in nodes if n.get("targets"))
    print(f"{src}: {len(nodes)} parts ({morphed} with damage targets), {tris} triangles, {len(pngs)} texture pages, "
          f"{len(zones)} damage zones, {len(detachable)} detachable groups, {skipped} variant parts skipped")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("src")
    ap.add_argument("out")
    ap.add_argument("--level", type=int, default=1, help="detail level: 1-2 showroom, 3-7 in-game")
    ap.add_argument("--all", action="store_true", help="include variant and driver parts")
    ap.add_argument("--tpg", help="texture page config (default: <src>.tpg)")
    a = ap.parse_args()
    convert(a.src, a.out, a.level, a.all, a.tpg)


if __name__ == "__main__":
    main()
