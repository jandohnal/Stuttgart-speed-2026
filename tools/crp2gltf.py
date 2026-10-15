"""Convert an NFS5 car model (.crp) to glTF 2.0 for use as a private visual reference.

Format: docs/formats/crp.md. Structure follows CrpLib from LibOpenNFS (MIT).
Writes <out>.gltf, <out>.bin and one PNG atlas per texture page next to it.

Usage:
    python3 tools/crp2gltf.py sources/GameData/CarModel/356a.crp decomposed/GameData/CarModel/356a/356a.gltf
    python3 tools/crp2gltf.py ... --level 3      # in-game LOD instead of the showroom model
    python3 tools/crp2gltf.py ... --all          # also variant parts (styles, driver)
"""
import argparse
import json
import os
import re
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from refpack import decompress  # noqa: E402
import fsh2png  # noqa: E402

# Detail levels: 1-2 showroom ("fe"), 3-7 in-game LODs ("ig"); 0x8000 = damaged copy.
DAMAGED = 0x8000
BIL_DRIVER = 8


class Entry:
    __slots__ = ("tag", "index", "count", "length", "data", "sub")


def read_entry(d, o):
    t1, t2, count, off = struct.unpack_from("<IIiI", d, o)
    flags, length = t2 & 0xFF, t2 >> 8
    e = Entry()
    if flags & 1:
        e.index, eid = t1 & 0xFFFF, t1 >> 16
    else:
        e.index, eid = 0, t1
    e.tag = struct.pack(">I", eid).lstrip(b"\0").decode("latin1")
    e.count, e.length = count, length
    if length == 0:
        base = o + (off << 4)
        e.sub, e.data = [read_entry(d, base + 16 * i) for i in range(count)], None
    else:
        e.sub, e.data = [], o + off
    return e


def find(entries, tag, index=None):
    return next((e for e in entries if e.tag == tag and (index is None or e.index == index)), None)


def parse_crp(d):
    if d[:2] == b"\x10\xfb":
        d = decompress(d)[0]
    magic, info, misc_count, offs = struct.unpack_from("<4sIII", d, 0)
    if magic not in (b" raC", b"karT"):
        raise ValueError("not a CRP file")
    arti_count, start = info >> 5, offs << 4
    arts = [read_entry(d, start + 16 * i) for i in range(arti_count)]
    misc = [read_entry(d, start + 16 * (arti_count + i)) for i in range(misc_count)]
    return d, arts, misc


def parse_base(d, e):
    o = e.data
    level_count = struct.unpack_from("<I", d, o + 12)[0]
    info = d[o + 0x44:o + 0x54]
    levels = [struct.unpack_from("<ihhhh", d, o + 0x64 + 12 * i)[3] for i in range(level_count)]
    return {"geom_index": info[0], "type_index": info[1], "level_index": info[10], "levels": levels}


def parse_part(d, e):
    o = e.data
    mat = struct.unpack_from("<h", d, o + 4)[0]
    info_count, index_count = struct.unpack_from("<ii", d, o + 0x28)
    p = o + 0x30
    infos = {}
    for _ in range(info_count):
        rm, off, length, iid, level, ref = struct.unpack_from("<iihhhh", d, p)
        infos[iid] = off // (8 if iid == 2 else 16)
        p += 16
    rows = {}
    for _ in range(index_count):
        idx, iid, off = struct.unpack_from("<hHi", d, p)
        rows[iid] = off
        p += 8
    raw = d[p:p + index_count * e.count]
    return mat, infos, rows, raw


def vectors(d, e, n):
    return [struct.unpack_from(f"<{n}f", d, e.data + 4 * n * i) for i in range(e.count)]


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


def article_mesh(d, art, level, materials):
    """Return (name, translation, {material: (positions, normals, uvs, indices)}) or None."""
    vt = find(art.sub, "vt", level)
    if vt is None:
        return None
    verts = vectors(d, vt, 4)
    nm = find(art.sub, "nm", level)
    norms = vectors(d, nm, 4) if nm is not None and nm.count == vt.count else None
    uv_e = find(art.sub, "uv", level)
    uvs = vectors(d, uv_e, 2) if uv_e is not None else None
    tr = find(art.sub, "tr", level)
    offset = struct.unpack_from("<3f", d, tr.data + 48) if tr is not None else (0.0, 0.0, 0.0)
    prims = {}
    part_no = 0
    while True:
        pe = find(art.sub, "pr", (level << 12) | part_no)
        if pe is None:
            break
        part_no += 1
        mat, infos, rows, raw = parse_part(d, pe)
        if 0x4976 not in rows:
            continue
        vt_off, vt_adj = rows[0x4976], infos.get(0, 0)
        uv_off, uv_adj = rows.get(0x4975), infos.get(2, 0)
        key = materials.get(mat, -1)
        pos, nrm, tex, idx, seen = prims.setdefault(key, ([], [], [], [], {}))
        for k in range(pe.count):
            vi = raw[vt_off + k] + vt_adj
            ui = raw[uv_off + k] + uv_adj if uvs is not None and uv_off is not None else -1
            if vi >= len(verts):
                continue
            if (vi, ui) not in seen:
                seen[(vi, ui)] = len(pos)
                pos.append(verts[vi][:3])
                nrm.append(norms[vi][:3] if norms else (0.0, 1.0, 0.0))
                tex.append(uvs[ui] if 0 <= ui < len(uvs) else (0.0, 0.0))
            idx.append(seen[(vi, ui)])
    return offset, {k: v[:4] for k, v in prims.items() if len(v[3]) >= 3}


def write_gltf(out_path, nodes_data, pngs):
    stem = os.path.splitext(os.path.basename(out_path))[0]
    buf = bytearray()
    gl = {"asset": {"version": "2.0", "generator": "stuttgart-speed crp2gltf"},
          "scene": 0, "scenes": [{"nodes": []}], "nodes": [], "meshes": [], "materials": [],
          "accessors": [], "bufferViews": [], "buffers": [], "textures": [], "images": [], "samplers": [{}]}
    mat_index = {}

    def material(tpage):
        if tpage not in mat_index:
            m = {"name": f"tpage{tpage + 1}" if tpage >= 0 else "untextured",
                 "pbrMetallicRoughness": {"metallicFactor": 0.0, "roughnessFactor": 0.8}, "doubleSided": True}
            if tpage in pngs:
                gl["images"].append({"uri": pngs[tpage]})
                gl["textures"].append({"source": len(gl["images"]) - 1, "sampler": 0})
                m["pbrMetallicRoughness"]["baseColorTexture"] = {"index": len(gl["textures"]) - 1}
                m["alphaMode"] = "MASK"
            mat_index[tpage] = len(gl["materials"])
            gl["materials"].append(m)
        return mat_index[tpage]

    def add(fmt, rows, comp, target, minmax=False):
        while len(buf) % 4:
            buf.append(0)
        start = len(buf)
        for r in rows:
            buf.extend(struct.pack(fmt, *r) if isinstance(r, tuple) else struct.pack(fmt, r))
        gl["bufferViews"].append({"buffer": 0, "byteOffset": start, "byteLength": len(buf) - start, "target": target})
        acc = {"bufferView": len(gl["bufferViews"]) - 1, "componentType": 5126 if "f" in fmt else 5125,
               "count": len(rows), "type": comp}
        if minmax:
            acc["min"] = [min(r[i] for r in rows) for i in range(3)]
            acc["max"] = [max(r[i] for r in rows) for i in range(3)]
        gl["accessors"].append(acc)
        return len(gl["accessors"]) - 1

    for name, offset, prims in nodes_data:
        mesh = {"name": name, "primitives": []}
        for tpage, (pos, nrm, tex, idx) in sorted(prims.items()):
            mesh["primitives"].append({
                "attributes": {"POSITION": add("<3f", [tuple(p) for p in pos], "VEC3", 34962, True),
                               "NORMAL": add("<3f", [tuple(n) for n in nrm], "VEC3", 34962),
                               "TEXCOORD_0": add("<2f", [tuple(t) for t in tex], "VEC2", 34962)},
                "indices": add("<I", idx, "SCALAR", 34963),
                "material": material(tpage)})
        gl["meshes"].append(mesh)
        node = {"name": name, "mesh": len(gl["meshes"]) - 1}
        if any(offset):
            node["translation"] = list(offset)
        gl["nodes"].append(node)
        gl["scenes"][0]["nodes"].append(len(gl["nodes"]) - 1)
    gl["buffers"].append({"uri": stem + ".bin", "byteLength": len(buf)})
    with open(os.path.join(os.path.dirname(out_path), stem + ".bin"), "wb") as fh:
        fh.write(buf)
    for k in ("textures", "images"):
        if not gl[k]:
            del gl[k]
    with open(out_path, "w") as fh:
        json.dump(gl, fh, indent=1)


def convert(src, out_path, level=1, include_all=False, tpg=None):
    d, arts, misc = parse_crp(open(src, "rb").read())
    out_dir = os.path.dirname(os.path.abspath(out_path))
    os.makedirs(out_dir, exist_ok=True)
    stem = os.path.splitext(os.path.basename(out_path))[0]
    tpg = tpg or os.path.splitext(src)[0] + ".tpg"
    pngs = load_textures(d, misc, tpg, out_dir, stem)
    materials = {e.index: struct.unpack_from("<i", d, e.data + 0x28)[0] for e in misc if e.tag == "mt"}
    nodes, skipped = [], 0
    for art in arts:
        name_e, base_e = find(art.sub, "Name"), find(art.sub, "Base")
        if name_e is None or base_e is None or find(art.sub, "ef") is not None:
            continue
        name = d[name_e.data:name_e.data + name_e.length].split(b"\0")[0].decode("latin1")
        base = parse_base(d, base_e)
        if not include_all and (base["type_index"] != 0 or (base["level_index"] >> 4) & BIL_DRIVER):
            skipped += 1
            continue
        # Use the requested level, or the closest more detailed one the part has.
        lev = level if level in base["levels"] else min((l for l in base["levels"] if l > level), default=None)
        if lev is None:
            continue
        mesh = article_mesh(d, art, lev, materials)
        if mesh and mesh[1]:
            nodes.append((f"{name}_{base['geom_index']}_{base['type_index']}", *mesh))
    write_gltf(out_path, nodes, pngs)
    tris = sum(len(p[3]) // 3 for _, _, prims in nodes for p in prims.values())
    print(f"{src}: {len(nodes)} parts, {tris} triangles, {len(pngs)} texture pages, {skipped} variant parts skipped")


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
