"""Convert EA FSH (SHPI) texture archives to PNG.

Format: docs/formats/fsh.md. Each image in an archive becomes one RGBA PNG,
plus an index.json with entry names, record types, sizes and metadata.

Usage:
    python3 tools/fsh2png.py sources/GameData/CarModel/356a.fsh decomposed/GameData/CarModel/356a
    python3 tools/fsh2png.py sources decomposed          # whole tree, mirrors folders
"""
import json
import os
import re
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from refpack import decompress  # noqa: E402

# Image record types: bytes per pixel. Bit 0x80 set = RefPack-compressed pixels.
IMAGE_BPP = {0x7B: 1, 0x7D: 4, 0x7E: 2, 0x7F: 3, 0x78: 2, 0x6D: 2}
# Palette record types: bytes per entry.
PALETTE_BPE = {0x29: 2, 0x2A: 4, 0x2D: 2, 0x24: 3, 0x22: 3}
TEXT_TYPES = {0x6F, 0x70}


def rgba_from_16(v, kind):
    if kind == "1555":
        return ((v >> 10 & 31) * 255 // 31, (v >> 5 & 31) * 255 // 31, (v & 31) * 255 // 31,
                255 if v & 0x8000 else 0)
    if kind == "565":
        return ((v >> 11 & 31) * 255 // 31, (v >> 5 & 63) * 255 // 63, (v & 31) * 255 // 31, 255)
    if kind == "4444":
        return ((v >> 8 & 15) * 17, (v >> 4 & 15) * 17, (v & 15) * 17, (v >> 12 & 15) * 17)
    raise ValueError(kind)


def decode_palette(t, data, count):
    pal = []
    for i in range(count):
        if t == 0x2A:
            b, g, r, a = data[4 * i:4 * i + 4]
            pal.append((r, g, b, a))
        elif t == 0x29:
            pal.append(rgba_from_16(struct.unpack_from("<H", data, 2 * i)[0], "565"))
        elif t == 0x2D:
            pal.append(rgba_from_16(struct.unpack_from("<H", data, 2 * i)[0], "1555"))
        elif t == 0x24:
            r, g, b = data[3 * i:3 * i + 3]
            pal.append((r, g, b, 255))
        elif t == 0x22:
            r, g, b = (min(255, c * 4) for c in data[3 * i:3 * i + 3])
            pal.append((r, g, b, 255))
    return pal


def decode_image(t, w, h, px, palette):
    """Return w*h*4 RGBA bytes."""
    out = bytearray(w * h * 4)
    n = w * h
    if t == 0x7B:
        if palette is None:
            palette = [(i, i, i, 255) for i in range(256)]
        for i in range(n):
            out[4 * i:4 * i + 4] = bytes(palette[px[i]] if px[i] < len(palette) else (0, 0, 0, 0))
    elif t == 0x7D:
        for i in range(n):
            b, g, r, a = px[4 * i:4 * i + 4]
            out[4 * i:4 * i + 4] = bytes((r, g, b, a))
    elif t == 0x7F:
        for i in range(n):
            b, g, r = px[3 * i:3 * i + 3]
            out[4 * i:4 * i + 4] = bytes((r, g, b, 255))
    else:
        kind = {0x7E: "1555", 0x78: "565", 0x6D: "4444"}[t]
        for i, (v,) in enumerate(struct.iter_unpack("<H", px[:2 * n])):
            out[4 * i:4 * i + 4] = bytes(rgba_from_16(v, kind))
    return bytes(out)


def write_png(path, w, h, rgba):
    raw = b"".join(b"\0" + rgba[y * w * 4:(y + 1) * w * 4] for y in range(h))

    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)

    with open(path, "wb") as fh:
        fh.write(b"\x89PNG\r\n\x1a\n")
        fh.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)))
        fh.write(chunk(b"IDAT", zlib.compress(raw, 6)))
        fh.write(chunk(b"IEND", b""))


def parse(d):
    """Yield entries: dict(name, records=[(type, w, h, misc, payload)])."""
    if d[:2] == b"\x10\xfb":
        d = decompress(d)[0]
    if d[:4] != b"SHPI":
        raise ValueError("not an SHPI archive")
    n = struct.unpack_from("<I", d, 8)[0]
    dir_id = d[12:16].decode("latin1")
    heads = [(d[16 + 8 * i:20 + 8 * i].decode("latin1"), struct.unpack_from("<I", d, 20 + 8 * i)[0])
             for i in range(n)]
    ends = sorted({o for _, o in heads} | {len(d)})
    entries = []
    for name, off in heads:
        end = next(e for e in ends if e > off)
        o, records = off, []
        while True:
            hdr, w, h = struct.unpack_from("<IHH", d, o)
            t, nxt = hdr & 0xFF, hdr >> 8
            rec_end = o + nxt if nxt else end
            records.append((t, w, h, d[o + 8:o + 16], d[o + 16:rec_end]))
            if not nxt:
                break
            o += nxt
        entries.append({"name": name, "records": records})
    return dir_id, entries


def safe(name):
    s = re.sub(r"[^A-Za-z0-9_.-]", "_", name.strip("\0 ").strip())
    return s or "_"


def convert(src, out_dir):
    dir_id, entries = parse(open(src, "rb").read())
    os.makedirs(out_dir, exist_ok=True)
    index = {"source": src, "dir_id": dir_id, "entries": []}
    problems = []
    for i, e in enumerate(entries):
        image, palette, info = None, None, {"name": e["name"].rstrip("\0"), "records": []}
        for t, w, h, misc, payload in e["records"]:
            info["records"].append(f"0x{t:02X}")
            base = t & 0x7F if t & 0x80 and (t & 0x7F) in IMAGE_BPP else t
            if base in IMAGE_BPP and image is None:
                if t != base:
                    payload = decompress(payload)[0]
                image = (base, w & 0x3FFF, h & 0x3FFF, payload)
                info.update(type=f"0x{base:02X}", compressed=t != base, width=w & 0x3FFF, height=h & 0x3FFF,
                            center=list(struct.unpack_from("<hh", misc, 0)),
                            position=list(struct.unpack_from("<hh", misc, 4)))
            elif t in PALETTE_BPE:
                palette = decode_palette(t, payload, min(w, len(payload) // PALETTE_BPE[t]))
                info["palette"] = f"0x{t:02X}"
            elif t in TEXT_TYPES:
                info.setdefault("text", []).append(payload.split(b"\0")[0].decode("latin1"))
        if image is None:
            problems.append(f"{e['name']!r}: no image record")
        else:
            t, w, h, px = image
            need = w * h * IMAGE_BPP[t]
            if len(px) < need:
                problems.append(f"{e['name']!r}: {len(px)} B < {need} B")
                px = px + bytes(need - len(px))
            if t == 0x7B and palette is None:
                problems.append(f"{e['name']!r}: 8-bit without palette, grayscale")
            fn = f"{i:03d}_{safe(e['name'])}.png"
            if w and h:
                write_png(os.path.join(out_dir, fn), w, h, decode_image(t, w, h, px, palette))
                info["file"] = fn
        index["entries"].append(info)
    if problems:
        index["problems"] = problems
    with open(os.path.join(out_dir, "index.json"), "w") as fh:
        json.dump(index, fh, indent=2, ensure_ascii=False)
    return len(entries), problems


def main(src, dst):
    if os.path.isfile(src):
        jobs = [(src, dst)]
    else:
        jobs = []
        for root, _, files in os.walk(src):
            for fn in sorted(files):
                if fn.lower().endswith(".fsh"):
                    rel = os.path.relpath(os.path.join(root, fn), src)
                    jobs.append((os.path.join(root, fn), os.path.join(dst, os.path.splitext(rel)[0])))
    total, bad = 0, 0
    for s, o in sorted(jobs):
        try:
            n, problems = convert(s, o)
        except Exception as ex:  # keep going, report at the end
            print(f"FAIL {s}: {ex}", file=sys.stderr)
            bad += 1
            continue
        total += n
        for p in problems:
            print(f"WARN {s}: {p}", file=sys.stderr)
    print(f"{len(jobs)} files, {total} images, {bad} failed")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
