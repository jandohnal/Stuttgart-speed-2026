"""Containers of the original game: EA RefPack compression (QFS, magic 0x10FB: .crp, FSH
pixels) and BIGF archives (.viv: sound banks, music, speech).

Usage:
    python3 tools/archives.py refpack sources/GameData/CarModel/356a.crp decomposed/GameData/CarModel/356a.bin
    python3 tools/archives.py bigf sources/GameData/Sounds/sd1a.viv decomposed/GameData/Sounds/sd1a
"""
import os
import struct
import sys


def decompress(d):
    """RefPack: returns (data, declared size)."""
    p = 2
    flags = (d[0] << 8) | d[1]
    if flags & 0x0100:
        p += 3
    size = (d[p] << 16) | (d[p + 1] << 8) | d[p + 2]
    p += 3
    out = bytearray()
    while p < len(d):
        b0 = d[p]
        if b0 < 0x80:
            b1 = d[p + 1]
            p += 2
            lit = b0 & 3
            out += d[p:p + lit]
            p += lit
            ln, off = ((b0 & 0x1C) >> 2) + 3, ((b0 & 0x60) << 3) + b1 + 1
        elif b0 < 0xC0:
            b1, b2 = d[p + 1], d[p + 2]
            p += 3
            lit = b1 >> 6
            out += d[p:p + lit]
            p += lit
            ln, off = (b0 & 0x3F) + 4, ((b1 & 0x3F) << 8) + b2 + 1
        elif b0 < 0xE0:
            b1, b2, b3 = d[p + 1], d[p + 2], d[p + 3]
            p += 4
            lit = b0 & 3
            out += d[p:p + lit]
            p += lit
            ln, off = ((b0 & 0x0C) << 6) + b3 + 5, ((b0 & 0x10) << 12) + (b1 << 8) + b2 + 1
        elif b0 < 0xFC:
            p += 1
            lit = ((b0 & 0x1F) << 2) + 4
            out += d[p:p + lit]
            p += lit
            continue
        else:
            p += 1
            lit = b0 & 3
            out += d[p:p + lit]
            break
        for _ in range(ln):
            out.append(out[-off])
    return bytes(out), size


def read_bigf(data):
    """{name: bytes} of a BIGF archive (big-endian directory: offset, size, zero-terminated name)."""
    if data[:4] != b"BIGF":
        raise ValueError("not a BIGF archive")
    count = struct.unpack_from(">I", data, 8)[0]
    pos, files = 16, {}
    for _ in range(count):
        offset, size = struct.unpack_from(">II", data, pos)
        end = data.index(b"\0", pos + 8)
        files[data[pos + 8:end].decode("latin1")] = data[offset:offset + size]
        pos = end + 1
    return files


def main():
    if len(sys.argv) != 4 or sys.argv[1] not in ("refpack", "bigf"):
        sys.exit(__doc__)
    cmd, src, dst = sys.argv[1:]
    data = open(src, "rb").read()
    if cmd == "refpack":
        os.makedirs(os.path.dirname(os.path.abspath(dst)), exist_ok=True)
        out, size = decompress(data)
        open(dst, "wb").write(out)
        print(src, "declared", size, "got", len(out), "OK" if size == len(out) else "MISMATCH")
    else:
        os.makedirs(dst, exist_ok=True)
        files = read_bigf(data)
        for name, payload in files.items():
            open(os.path.join(dst, name), "wb").write(payload)
        print(f"{src}: {len(files)} files")


if __name__ == "__main__":
    main()
