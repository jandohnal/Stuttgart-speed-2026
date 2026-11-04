"""Convert the original's particle systems (GameData/Render/particle.ini) to JSON.

Format: docs/formats/particle.md. particle.ini is a text INI with [header]
numSystems and one [system#NNN] section per system (62). Numbers are kept as
they are; the integer IDs are decoded to their four-character names:
tag (key of the system, as the track `ef` sources reference it) reads as
little-endian ASCII, matid (texture in particle.fsh) as big-endian ASCII.
Colours are signed 32-bit ARGB, written as "#aarrggbb".

Output JSON:
    {"source": ..., "systems": [{"index", "name", "tag", "texture", "in_use",
      "count", "blend", "emit": [x, y, z], "emit_random": [x, y, z],
      "size": [start, end], "overall_size", "overall_speed", "lifetime",
      "lifetime_random", "weight", "weight_random", "rotation": [start, end, random],
      "colors": ["#aarrggbb" x numstates], "frames", "frame_speed", "flags",
      "air_friction", "zbias", "period": [on, off], "prime_ticks", "volume_scale_pct"}]}

Usage:
    python3 tools/particles.py sources/GameData/Render/particle.ini decomposed/GameData/Render/particles.json
"""
import json
import os
import re
import struct
import sys


def fourcc(value, order):
    raw = struct.pack(order + "I", value & 0xFFFFFFFF)
    return raw.decode("latin1") if all(32 <= b < 127 for b in raw) else None


def number(text):
    return int(text) if re.fullmatch(r"-?\d+", text) else float(text)


def read_ini(path):
    sections = {}
    current = None
    with open(path, encoding="latin1") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith(";"):
                continue
            if line.startswith("["):
                current = sections.setdefault(line[1:-1], {})
            elif "=" in line and current is not None:
                key, value = line.split("=", 1)
                current[key.strip()] = value.strip()
    return sections


def system(index, s):
    n = {k: number(v) if k != "name" else v for k, v in s.items()}
    states = int(n.get("numstates", 0))
    return {
        "index": index,
        "name": n.get("name", ""),
        "tag": fourcc(int(n["tag"]), "<"),
        "texture": fourcc(int(n["matid"]), ">"),
        "in_use": bool(n.get("inUse", 0)),
        "count": n["numparticles"],
        "blend": n["blendmode"],
        "emit": [n["emit.x"], n["emit.y"], n["emit.z"]],
        "emit_random": [n["randemit.x"], n["randemit.y"], n["randemit.z"]],
        "size": [n["startsize"], n["endsize"]],
        "overall_size": n["overallsize"],
        "overall_speed": n["overallspeed"],
        "lifetime": n["lifetime"],
        "lifetime_random": n.get("randlifetime", 0),
        "weight": n["weight"],
        "weight_random": n["randweight"],
        "rotation": [n["startrotation"], n["endrotation"], n["randrotation"]],
        "colors": ["#%08x" % (int(n["color.%d" % i]) & 0xFFFFFFFF) for i in range(states)],
        "frames": n["numframes"],
        "frame_speed": n["framespeed"],
        "flags": n["flags"],
        "air_friction": n["airFriction"],
        "zbias": n["zbias"],
        "period": [n["periodOn"], n["periodOff"]],
        "prime_ticks": n["primeTicks"],
        "volume_scale_pct": n["volumeScalePct"],
    }


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    src, dst = sys.argv[1], sys.argv[2]
    sections = read_ini(src)
    count = int(sections["header"]["numSystems"])
    systems = []
    for i in range(count):
        s = sections.get("system#%03d" % i)
        if s is None:
            sys.exit("missing [system#%03d]" % i)
        systems.append(system(i, s))
    os.makedirs(os.path.dirname(dst) or ".", exist_ok=True)
    with open(dst, "w", encoding="utf-8") as f:
        json.dump({"source": src, "systems": systems}, f, indent=1)
    print("%d systems -> %s" % (len(systems), dst))


if __name__ == "__main__":
    main()
