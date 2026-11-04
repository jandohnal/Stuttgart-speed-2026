"""Convert the NFS5 flare table (GameData/Render/flare.dat) to JSON.

Format: docs/formats/flare.md. 140-byte records, one per flare ID; track articles refer to them
from their ef entries (docs/formats/crp.md, "Efekty"). Each flare has two sprite layers (texture
from GameData/Render/common.fsh, ARGB colour, size) and an optional blink cycle in ticks.

Usage:
    python3 tools/flare.py sources/GameData/Render/flare.dat decomposed/GameData/Render/flares.json
"""
import json
import os
import struct
import sys

RECORD = 140


def fourcc(b):
    """IDs and texture names are stored byte-reversed ('anrw' = 'wrna'); 'null' = no texture."""
    s = b[::-1].decode("latin1")
    return None if s == "null" else s


def argb(v):
    return [round(((v >> s) & 0xFF) / 255.0, 4) for s in (16, 8, 0, 24)]  # RGBA


def parse(data):
    flares = {}
    for o in range(0, len(data) - RECORD + 1, RECORD):
        r = data[o:o + RECORD]
        fid = fourcc(r[0:4])
        c1, c2 = struct.unpack_from("<II", r, 0x1C)
        s1, s2 = struct.unpack_from("<ff", r, 0x34)
        mode, phase, on, off = struct.unpack_from("<4I", r, 0x4C)
        flares[fid] = {
            "layers": [{"texture": fourcc(r[4:8]), "color": argb(c1), "size": round(s1, 3)},
                       {"texture": fourcc(r[8:12]), "color": argb(c2), "size": round(s2, 3)}],
            "mode": mode,
            "blink": {"phase": phase, "on": on, "off": off} if on and off else None,
        }
    return flares


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    src, out = sys.argv[1:]
    flares = parse(open(src, "rb").read())
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with open(out, "w", encoding="utf-8") as fh:
        json.dump({"source": os.path.basename(src),
                   "fields": "layers [2]: texture (common.fsh name or null), color RGBA 0-1, size; "
                             "blink: lit while (tick - phase) mod (on + off) < on, else steady",
                   "flares": flares}, fh, indent=1)
    blinking = sorted(k for k, v in flares.items() if v["blink"])
    print(f"{src}: {len(flares)} flares, blinking {len(blinking)}: {' '.join(blinking)}")


if __name__ == "__main__":
    main()
