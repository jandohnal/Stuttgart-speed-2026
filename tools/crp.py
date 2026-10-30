"""Shared reader for NFS5 .crp containers (cars and tracks) and a minimal glTF writer.

Format: docs/formats/crp.md. Structure follows CrpLib from LibOpenNFS (MIT).
Used by tools/crp2gltf.py (cars) and tools/track2gltf.py (tracks).
"""
import json
import os
import struct
from collections import Counter

from archives import decompress

INDEX_VERTEX = 0x4976  # "vI"
INDEX_UV = 0x4975  # "uI"
PRIM_STRIP = 1  # pr header u16 at 0x00: 3 = triangle list, 1 = triangle strip, 4 = quad list
PRIM_QUADS = 4
CREASE_COS = 0.5  # 60 degrees: smoothed normals do not cross a sharper edge
UP_MIN = 0.02  # |normal y| below this is a wall: its facing cannot be told from "up"
# Triangles fixed or dropped by article_mesh since the last reset; converters store them in the glTF.
STATS = Counter()


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


def base_info(d, art):
    """The article's Base entry: level count and levels (cars), the info bytes at 0x44 read as car
    indices (geom, type, level index) and as a track object tag (4 characters: SIGN, CONE ...)."""
    base = find(art.sub, "Base")
    if base is None:
        return None
    o = base.data
    count = struct.unpack_from("<I", d, o + 12)[0]
    info = d[o + 0x44:o + 0x54]
    raw = info[:4].rstrip(b"\0")
    return {"geom_index": info[0], "type_index": info[1], "level_index": info[10],
            "levels": [struct.unpack_from("<ihhhh", d, o + 0x64 + 12 * i)[3] for i in range(count)]
            if base.length >= 0x64 + 12 * count else [],
            "tag": raw.decode("latin1") if raw and all(32 <= c < 127 for c in raw) else ""}


def entry_text(d, e):
    return d[e.data:e.data + e.length].split(b"\0")[0].decode("latin1")


def strip_to_list(corners):
    """Triangle strip -> list of corner triples; odd triangles swap their first two corners so
    all keep the same winding, degenerate ones (repeated vertex) are dropped."""
    out = []
    for i in range(len(corners) - 2):
        a, b, c = corners[i:i + 3]
        if a[0] == b[0] or b[0] == c[0] or a[0] == c[0]:
            continue
        out += [a, b, c] if i % 2 == 0 else [b, a, c]
    return out


def parse_part(d, e):
    o = e.data
    prim = struct.unpack_from("<H", d, o)[0]
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
    return prim, mat, infos, rows, raw


def vectors(d, e, n):
    return [struct.unpack_from(f"<{n}f", d, e.data + 4 * n * i) for i in range(e.count)]


def to_gltf(v):
    """Original data is left-handed (Direct3D); glTF is right-handed. Mirroring X converts it
    (front stays -Z) and also turns the original clockwise triangles into glTF front faces."""
    return (-v[0], v[1], v[2])


def quads_to_list(corners):
    """Unindexed quad list (4 consecutive corners each) -> list of corner triples."""
    out = []
    for i in range(0, len(corners) - 3, 4):
        a, b, c, e = corners[i:i + 4]
        out += [a, b, c, a, c, e]
    return out


EFFECT_FLARE, EFFECT_EMITTER, EFFECT_SHADOW = 2, 3, 4  # ef u32 at 0x00


def article_effects(d, art):
    """The article's ef entries (docs/formats/crp.md, "Efekty"): flares (light glows, look in
    GameData/Render/flare.dat), particle emitters (with "up", the basis row the system's emit.y
    speed runs along) and shadows. Positions are local to the tr matrix
    when the article has one, else world; both mirrored like to_gltf. IDs are stored byte-reversed."""
    out = []
    for e in art.sub:
        if e.tag != "ef" or e.length < 0x2C:
            continue
        kind = struct.unpack_from("<I", d, e.data)[0]
        pos = to_gltf(struct.unpack_from("<3f", d, e.data + 8))
        if kind == EFFECT_FLARE:
            vec = to_gltf(struct.unpack_from("<3f", d, e.data + 0x14))
            fid = d[e.data + 0x24:e.data + 0x28][::-1]
        elif kind == EFFECT_EMITTER and e.length >= 0x38:
            vec = to_gltf(struct.unpack_from("<3f", d, e.data + 0x18))  # first of the basis rows
            up = to_gltf(struct.unpack_from("<3f", d, e.data + 0x24))  # second row: the emit axis
            fid = d[e.data + 0x30:e.data + 0x34]
        else:
            continue
        entry = {"kind": kind, "id": fid.decode("latin1"), "position": pos, "direction": vec}
        if kind == EFFECT_EMITTER:
            entry["up"] = up
        out.append(entry)
    return out


def article_matrix(d, art):
    """The article's tr matrix (placed objects) as a glTF column-major matrix, mirrored like to_gltf.

    tr holds a Direct3D row-vector matrix (rows = axes, translation in floats 12..14); the same 16
    floats read column-major give the glTF matrix, and S M S with S = diag(-1, 1, 1, 1) flips the
    elements that mix X with another axis."""
    tr = find(art.sub, "tr")
    if tr is None:
        return None
    m = list(struct.unpack_from("<16f", d, tr.data))
    for i in (1, 2, 3, 4, 8, 12):
        m[i] = -m[i]
    return m


def cross(a, b, c):
    u = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
    v = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
    return (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])


def orient_up(tris, verts):
    """Turn ground triangles (lists of (vertex, uv) corners) in place to face up. Walls (|normal y|
    < UP_MIN) take the facing of a neighbour: a consistent neighbour runs their shared edge the
    other way round."""
    edges, todo, queue = {}, set(), []
    for i, tri in enumerate(tris):
        n = cross(*(verts[vi] for vi, _ in tri))
        length = (n[0] * n[0] + n[1] * n[1] + n[2] * n[2]) ** 0.5
        if n[1] < -UP_MIN * length:
            tris[i] = tri = [tri[1], tri[0], tri[2]]
            STATS["flipped_up"] += 1
        if abs(n[1]) < UP_MIN * length:
            todo.add(i)
        else:
            queue.append(i)
        for k in range(3):
            a, b = tri[k][0], tri[(k + 1) % 3][0]
            edges.setdefault(frozenset((a, b)), []).append(i)
    while queue and todo:
        i = queue.pop()
        tri = tris[i]
        for k in range(3):
            a, b = tri[k][0], tri[(k + 1) % 3][0]
            for j in edges.get(frozenset((a, b)), ()):
                if j not in todo:
                    continue
                todo.discard(j)
                other = [vi for vi, _ in tris[j]]
                if any(other[m] == a and other[(m + 1) % 3] == b for m in range(3)):
                    tris[j] = [tris[j][1], tris[j][0], tris[j][2]]  # same direction: opposite facing
                    STATS["flipped_up"] += 1
                queue.append(j)


def article_mesh(d, art, level, part_level, materials, sources=False, up=False):
    """Return (translation, {material key: (positions, normals, uvs, indices)}) or None.

    The original's winding is not consistent (half of the 356 A inner hood, a quarter of the
    farmland terrain face the wrong way; the game drew them double-sided). Triangles are turned to
    agree with the stored normals (nm); without nm and with up=True (track ground) they are turned
    to face up, walls like their neighbours (orient_up). Counts go to STATS (flipped_by_normal, flipped_up, dropped).

    With sources=True a third item {material key: [source vt index per output vertex]} is added
    (e.g. to attach per-vertex damage offsets as morph targets).

    level: index of vt/nm/uv entries; part_level: level in the pr index (pr index = part_level << 12 | n).
    materials: {mt index: key}; parts are grouped into one primitive per key.
    """
    vt = find(art.sub, "vt", level)
    if vt is None:
        return None
    verts = [to_gltf(v) for v in vectors(d, vt, 4)]
    nm = find(art.sub, "nm", level)
    norms = [to_gltf(n) for n in vectors(d, nm, 4)] if nm is not None and nm.count == vt.count else None
    uv_e = find(art.sub, "uv", level)
    uvs = vectors(d, uv_e, 2) if uv_e is not None else None
    tr = find(art.sub, "tr", level)
    offset = to_gltf(struct.unpack_from("<3f", d, tr.data + 48)) if tr is not None else (0.0, 0.0, 0.0)
    prims = {}
    part_no = 0
    while True:
        pe = find(art.sub, "pr", (part_level << 12) | part_no)
        if pe is None:
            break
        part_no += 1
        prim, mat, infos, rows, raw = parse_part(d, pe)
        key = materials.get(mat, -1)
        if INDEX_VERTEX not in rows:
            # No index rows: vertices and UVs run on from the offsets in the info rows.
            vt_adj, uv_adj = infos.get(0, 0), infos.get(2, 0)
            corners = [(vt_adj + k, uv_adj + k if uvs is not None else -1) for k in range(pe.count)]
        else:
            vt_off, vt_adj = rows[INDEX_VERTEX], infos.get(0, 0)
            uv_off, uv_adj = rows.get(INDEX_UV), infos.get(2, 0)
            corners = [(raw[vt_off + k] + vt_adj,
                        raw[uv_off + k] + uv_adj if uvs is not None and uv_off is not None else -1)
                       for k in range(pe.count)]
        pos, nrm, tex, idx, seen = prims.setdefault(key, ([], [], [], [], {}))
        if prim == PRIM_STRIP:
            corners = strip_to_list(corners)
        elif prim == PRIM_QUADS:
            corners = quads_to_list(corners)
        else:
            corners = corners[:len(corners) - len(corners) % 3]
        tris = []
        for t in range(0, len(corners), 3):
            tri = corners[t:t + 3]
            if any(vi >= len(verts) for vi, _ in tri):
                STATS["dropped"] += 1
                continue  # drop the whole triangle, never shift the following ones
            tris.append(tri)
        if norms:
            for i, tri in enumerate(tris):
                n = cross(*(verts[vi] for vi, _ in tri))
                s = [sum(norms[vi][k] for vi, _ in tri) for k in range(3)]
                if n[0] * s[0] + n[1] * s[1] + n[2] * s[2] < 0.0:
                    tris[i] = [tri[1], tri[0], tri[2]]
                    STATS["flipped_by_normal"] += 1
        elif up:
            orient_up(tris, verts)
        for tri in tris:
            for vi, ui in tri:
                if (vi, ui) not in seen:
                    seen[(vi, ui)] = len(pos)
                    pos.append(verts[vi][:3])
                    nrm.append(norms[vi][:3] if norms else None)
                    tex.append(uvs[ui] if 0 <= ui < len(uvs) else (0.0, 0.0))
                idx.append(seen[(vi, ui)])
    out, src = {}, {}
    for k, (pos, nrm, tex, idx, seen) in prims.items():
        if len(idx) >= 3:
            order = [0] * len(pos)
            for (vi, _), i in seen.items():
                order[i] = vi
            if any(n is None for n in nrm):
                pos, nrm, tex, idx, order = smooth_normals(pos, tex, idx, order)
            out[k] = (pos, nrm, tex, idx)
            src[k] = order
    return (offset, out, src) if sources else (offset, out)


def smooth_normals(pos, tex, idx, order):
    """Area-weighted vertex normals for meshes without stored normals, split at creases: a corner
    averages only the faces around its vertex within CREASE of its own face (cliff edges, walls on
    the ground), so no face gets a normal from the other side of a sharp edge. Returns (pos, nrm,
    tex, idx, order) with vertices duplicated where they are split."""
    faces, around = [], [[] for _ in pos]
    for t in range(0, len(idx), 3):
        n = cross(*(pos[i] for i in idx[t:t + 3]))
        faces.append(n)
        for i in idx[t:t + 3]:
            around[i].append(t // 3)
    unit = []
    for x, y, z in faces:
        length = (x * x + y * y + z * z) ** 0.5
        unit.append((x / length, y / length, z / length) if length > 1e-12 else (0.0, 0.0, 0.0))
    out_pos, out_nrm, out_tex, out_idx, out_order, made = [], [], [], [], [], {}
    for t in range(0, len(idx), 3):
        f = unit[t // 3]
        for i in idx[t:t + 3]:
            group = tuple(g for g in around[i]
                          if g == t // 3 or sum(a * b for a, b in zip(unit[g], f)) >= CREASE_COS)
            if (i, group) not in made:
                acc = [sum(faces[g][k] for g in group) for k in range(3)]
                length = (acc[0] ** 2 + acc[1] ** 2 + acc[2] ** 2) ** 0.5
                made[(i, group)] = len(out_pos)
                out_pos.append(pos[i])
                out_nrm.append(tuple(a / length for a in acc) if length > 1e-12 else (0.0, 1.0, 0.0))
                out_tex.append(tex[i])
                out_order.append(order[i])
            out_idx.append(made[(i, group)])
    return out_pos, out_nrm, out_tex, out_idx, out_order


def write_gltf(out_path, nodes_data, material_spec, generator, extras=None):
    """Write <out>.gltf + <out>.bin.

    nodes_data: list of dicts {name, offset, prims, group (optional), matrix (optional, glTF
    column-major, replaces offset), targets (optional: {"names": [...], material key: [[offset per
    vertex] per name]}, glTF morph targets)}; nodes with a group become
    children of one empty node per group.
    material_spec(key) -> {"name": str, "uri": png file or None, "alpha": glTF alphaMode or None}.
    extras: stored as asset.extras (converter statistics read by tools/mesh_check.py).
    """
    stem = os.path.splitext(os.path.basename(out_path))[0]
    buf = bytearray()
    gl = {"asset": {"version": "2.0", "generator": generator, **({"extras": extras} if extras else {})},
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
        targets = nd.get("targets")
        for key, (pos, nrm, tex, idx) in sorted(nd["prims"].items(), key=lambda kv: kv[0]):
            prim = {
                "attributes": {"POSITION": add("<3f", [tuple(p) for p in pos], "VEC3", 34962, True),
                               "NORMAL": add("<3f", [tuple(n) for n in nrm], "VEC3", 34962),
                               "TEXCOORD_0": add("<2f", [tuple(t) for t in tex], "VEC2", 34962)},
                "indices": add("<I", idx, "SCALAR", 34963),
                "material": material(key)}
            if targets:
                # Every primitive of a mesh needs the same targets; zero offsets where a zone is absent.
                per_name = targets.get(key) or [[(0.0, 0.0, 0.0)] * len(pos) for _ in targets["names"]]
                prim["targets"] = [{"POSITION": add("<3f", [tuple(o) for o in offs], "VEC3", 34962, True)}
                                   for offs in per_name]
            mesh["primitives"].append(prim)
        if targets:
            mesh["extras"] = {"targetNames": list(targets["names"])}
            mesh["weights"] = [0.0] * len(targets["names"])
        gl["meshes"].append(mesh)
        node = {"name": nd["name"], "mesh": len(gl["meshes"]) - 1}
        if nd.get("matrix"):
            node["matrix"] = list(nd["matrix"])
        elif any(nd["offset"]):
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
