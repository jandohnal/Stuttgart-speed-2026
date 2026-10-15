"""Shared reader for NFS5 .crp containers (cars and tracks) and a minimal glTF writer.

Format: docs/formats/crp.md. Structure follows CrpLib from LibOpenNFS (MIT).
Used by tools/crp2gltf.py (cars) and tools/track2gltf.py (tracks).
"""
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from refpack import decompress  # noqa: E402

INDEX_VERTEX = 0x4976  # "vI"
INDEX_UV = 0x4975  # "uI"


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
    """Return (decompressed bytes, articles, misc entries)."""
    if d[:2] == b"\x10\xfb":
        d = decompress(d)[0]
    magic, info, misc_count, offs = struct.unpack_from("<4sIII", d, 0)
    if magic not in (b" raC", b"karT"):
        raise ValueError("not a CRP file")
    arti_count, start = info >> 5, offs << 4
    arts = [read_entry(d, start + 16 * i) for i in range(arti_count)]
    misc = [read_entry(d, start + 16 * (arti_count + i)) for i in range(misc_count)]
    return d, arts, misc


def entry_text(d, e):
    return d[e.data:e.data + e.length].split(b"\0")[0].decode("latin1")


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


def article_mesh(d, art, level, part_level, materials):
    """Return (translation, {material key: (positions, normals, uvs, indices)}) or None.

    level: index of vt/nm/uv entries; part_level: level in the pr index (pr index = part_level << 12 | n).
    materials: {mt index: key}; parts are grouped into one primitive per key.
    """
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
        pe = find(art.sub, "pr", (part_level << 12) | part_no)
        if pe is None:
            break
        part_no += 1
        mat, infos, rows, raw = parse_part(d, pe)
        if INDEX_VERTEX not in rows:
            continue
        vt_off, vt_adj = rows[INDEX_VERTEX], infos.get(0, 0)
        uv_off, uv_adj = rows.get(INDEX_UV), infos.get(2, 0)
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
                nrm.append(norms[vi][:3] if norms else None)
                tex.append(uvs[ui] if 0 <= ui < len(uvs) else (0.0, 0.0))
            idx.append(seen[(vi, ui)])
    out = {}
    for k, (pos, nrm, tex, idx, _) in prims.items():
        idx = idx[:len(idx) - len(idx) % 3]
        if len(idx) >= 3:
            if any(n is None for n in nrm):
                nrm = smooth_normals(pos, idx)
            out[k] = (pos, nrm, tex, idx)
    return offset, out


def smooth_normals(pos, idx):
    """Area-weighted vertex normals for meshes without stored normals."""
    acc = [[0.0, 0.0, 0.0] for _ in pos]
    for t in range(0, len(idx), 3):
        a, b, c = (pos[i] for i in idx[t:t + 3])
        u = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
        v = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
        n = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
        for i in idx[t:t + 3]:
            acc[i][0] += n[0]
            acc[i][1] += n[1]
            acc[i][2] += n[2]
    out = []
    for x, y, z in acc:
        length = (x * x + y * y + z * z) ** 0.5
        out.append((x / length, y / length, z / length) if length > 1e-12 else (0.0, 1.0, 0.0))
    return out


def write_gltf(out_path, nodes_data, material_spec, generator):
    """Write <out>.gltf + <out>.bin.

    nodes_data: list of dicts {name, offset, prims, group (optional)}; nodes with a group become
    children of one empty node per group.
    material_spec(key) -> {"name": str, "uri": png file or None, "alpha": glTF alphaMode or None}.
    """
    stem = os.path.splitext(os.path.basename(out_path))[0]
    buf = bytearray()
    gl = {"asset": {"version": "2.0", "generator": generator},
          "scene": 0, "scenes": [{"nodes": []}], "nodes": [], "meshes": [], "materials": [],
          "accessors": [], "bufferViews": [], "buffers": [], "textures": [], "images": [], "samplers": [{}]}
    mat_index, group_index = {}, {}

    def material(key):
        if key not in mat_index:
            spec = material_spec(key)
            m = {"name": spec["name"],
                 "pbrMetallicRoughness": {"metallicFactor": 0.0, "roughnessFactor": 0.8}, "doubleSided": True}
            if spec.get("color"):
                m["pbrMetallicRoughness"]["baseColorFactor"] = list(spec["color"])
                if spec["color"][3] < 1:
                    m["alphaMode"] = "BLEND"
            if spec.get("uri"):
                gl["images"].append({"uri": spec["uri"]})
                gl["textures"].append({"source": len(gl["images"]) - 1, "sampler": 0})
                m["pbrMetallicRoughness"]["baseColorTexture"] = {"index": len(gl["textures"]) - 1}
                if spec.get("alpha"):
                    m["alphaMode"] = spec["alpha"]
            mat_index[key] = len(gl["materials"])
            gl["materials"].append(m)
        return mat_index[key]

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

    for nd in nodes_data:
        mesh = {"name": nd["name"], "primitives": []}
        for key, (pos, nrm, tex, idx) in sorted(nd["prims"].items(), key=lambda kv: kv[0]):
            mesh["primitives"].append({
                "attributes": {"POSITION": add("<3f", [tuple(p) for p in pos], "VEC3", 34962, True),
                               "NORMAL": add("<3f", [tuple(n) for n in nrm], "VEC3", 34962),
                               "TEXCOORD_0": add("<2f", [tuple(t) for t in tex], "VEC2", 34962)},
                "indices": add("<I", idx, "SCALAR", 34963),
                "material": material(key)})
        gl["meshes"].append(mesh)
        node = {"name": nd["name"], "mesh": len(gl["meshes"]) - 1}
        if any(nd["offset"]):
            node["translation"] = list(nd["offset"])
        node_i = len(gl["nodes"])
        gl["nodes"].append(node)
        group = nd.get("group")
        if group is None:
            gl["scenes"][0]["nodes"].append(node_i)
        else:
            if group not in group_index:
                group_index[group] = len(gl["nodes"])
                gl["nodes"].append({"name": group, "children": []})
                gl["scenes"][0]["nodes"].append(group_index[group])
            gl["nodes"][group_index[group]]["children"].append(node_i)
    gl["buffers"].append({"uri": stem + ".bin", "byteLength": len(buf)})
    with open(os.path.join(os.path.dirname(os.path.abspath(out_path)), stem + ".bin"), "wb") as fh:
        fh.write(buf)
    for k in ("textures", "images"):
        if not gl[k]:
            del gl[k]
    with open(out_path, "w") as fh:
        json.dump(gl, fh, indent=1)
    return gl
