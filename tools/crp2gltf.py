"""Convert an NFS5 car model (.crp) to glTF 2.0 for use as a private visual reference.

Format: docs/formats/crp.md. Structure follows CrpLib from LibOpenNFS (MIT).
Writes <out>.gltf, <out>.bin and one PNG atlas per texture page next to it, plus
<out>_damage.json (damage zones). Damage: every part carries one glTF morph target per damage
zone it belongs to ("dz0" .. "dz9"), the original's offsets for a fully damaged car.

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
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fsh2png  # noqa: E402
from crp import article_mesh, entry_text, find, parse_crp, to_gltf, vectors, write_gltf  # noqa: E402

# Detail levels: 1-2 showroom ("fe"), 3-7 in-game LODs ("ig"); 0x8000 = damaged copy.
DAMAGED = 0x8000
BIL_DRIVER = 8
# Damage zones as found on the 356 A (centroids of their vertices); car front is -Z, right +X.
ZONE_NAMES = {0: "front_left", 1: "front", 2: "front_right", 3: "right", 4: "rear_right", 5: "rear",
              6: "rear_left", 7: "left", 8: "roof", 9: "bottom"}


def parse_base(d, e):
    o = e.data
    level_count = struct.unpack_from("<I", d, o + 12)[0]
    info = d[o + 0x44:o + 0x54]
    levels = [struct.unpack_from("<ihhhh", d, o + 0x64 + 12 * i)[3] for i in range(level_count)]
    return {"geom_index": info[0], "type_index": info[1], "level_index": info[10], "levels": levels}


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
            ext = os.path.join(car_dir, os.path.splitext(p["name"])[0] + ".fsh")
            alt = [f for f in os.listdir(car_dir) if f.lower() == os.path.basename(ext).lower()]
            data = open(os.path.join(car_dir, alt[0]), "rb").read() if alt else None
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
    out_dir = os.path.dirname(os.path.abspath(out_path))
    os.makedirs(out_dir, exist_ok=True)
    stem = os.path.splitext(os.path.basename(out_path))[0]
    tpg = tpg or os.path.splitext(src)[0] + ".tpg"
    pngs = load_textures(d, misc, tpg, out_dir, stem)
    materials = {e.index: struct.unpack_from("<i", d, e.data + 0x28)[0] for e in misc if e.tag == "mt"}
    nodes, skipped, zone_acc = [], 0, {}
    for art in arts:
        name_e, base_e = find(art.sub, "Name"), find(art.sub, "Base")
        if name_e is None or base_e is None or find(art.sub, "ef") is not None:
            continue
        name = entry_text(d, name_e)
        base = parse_base(d, base_e)
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
            targets, stats = damage_targets(d, art, lev, vertex_sources)
            verts = [to_gltf(v[:3]) for v in vectors(d, find(art.sub, "vt", lev), 4)]
            for z, vis in damage_zones(d, art, lev).items():
                acc = zone_acc.setdefault(z, [0.0, 0.0, 0.0, 0, 0.0])
                for vi in vis:
                    if vi < len(verts):
                        for k in range(3):
                            acc[k] += verts[vi][k] + offset[k]
                        acc[3] += 1
                acc[4] = max([acc[4]] + [math.hypot(*o) for o in stats.get(z, [])])
            nodes.append({"name": f"{name}_{base['geom_index']}_{base['type_index']}",
                          "offset": offset, "prims": prims, "targets": targets})

    def material_spec(tpage):
        return {"name": f"tpage{tpage + 1}" if tpage >= 0 else "untextured", "uri": pngs.get(tpage), "alpha": "MASK"}

    write_gltf(out_path, nodes, material_spec, "stuttgart-speed crp2gltf")
    zones = [{"zone": z, "name": ZONE_NAMES.get(z, f"zone{z}"), "blend_shape": f"dz{z}",
              "centroid": [round(acc[k] / acc[3], 3) for k in range(3)], "vertices": acc[3],
              "max_offset_m": round(acc[4], 3)} for z, acc in sorted(zone_acc.items()) if acc[3]]
    with open(os.path.join(out_dir, stem + "_damage.json"), "w") as fh:
        json.dump({"source": os.path.basename(src),
                   "fields": "zone id, name (as seen on the 356 A), blend shape on every part in it, "
                             "centroid of its vertices (glTF, m), max dent of a fully damaged car (m)",
                   "zones": zones}, fh, indent=1)
    tris = sum(len(p[3]) // 3 for n in nodes for p in n["prims"].values())
    morphed = sum(1 for n in nodes if n.get("targets"))
    print(f"{src}: {len(nodes)} parts ({morphed} with damage targets), {tris} triangles, {len(pngs)} texture pages, "
          f"{len(zones)} damage zones, {skipped} variant parts skipped")


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
