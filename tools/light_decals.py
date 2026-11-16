"""Convert the tracks' light decal tables (GameData/Track/<track>.map) to JSON.

Format: docs/formats/map.md. A text INI read by Porsche.exe at track load: [header] with colour
factors (tint, ambient, interior, interiordiffuse, lightdecal) and `count` sections that give, for a
range of road slices (SimD), three textures from <track>.env projected onto the cars driving there
(tunnel lamps sweeping over the body, tree shade). The textures are the env maps converted by
tools/fsh2png.py to decomposed/GameData/Track/<track>/env/.

Writes <track>/<track>_decals.json:
    header:   {tint, ambient, interior, interiordiffuse, lightdecal} as [a, r, g, b]
    sections: [{first, last, open: [t1, t2, t3], covered: [t1, t2, t3], size, aspect}]
    textures: {name: "env/NNN_name.png"} for the names the sections use, except fully transparent
              ones (the original draws them, but they change nothing)

Only the keys Porsche.exe reads are kept: section 0 of most tracks also has texture1/clamp/tint/
scroll keys (an older layout) that the game ignores.

Usage:
    python3 tools/light_decals.py sources/GameData/Track decomposed/GameData/Track
    python3 tools/light_decals.py sources/GameData/Track/alps.map decomposed/GameData/Track/alps/alps_decals.json
"""
import json
import os
import re
import struct
import sys

import fsh2png
from common import find_file, source_files

HEADER_COLORS = {  # key: default (a, r, g, b) in Porsche.exe
    "tint": [1.0, 1.0, 1.0, 1.0],
    "ambient": [1.0, 0.3, 0.3, 0.3],
    "interior": [1.0, 1.0, 1.0, 1.0],
    "interiordiffuse": [1.0, 1.0, 1.0, 1.0],
    "lightdecal": [1.0, 1.0, 1.0, 1.0],
}
DEFAULT_TEXTURE = 0x30564E45  # "ENV0": not in any .env, so no decal
DEFAULT_SIZE = 6.0
DEFAULT_ASPECT = 1.0


def read_ini(text):
    """{section: {key: value}}; the first value wins when a key repeats (section0 has two texture1)."""
    sections, current = {}, None
    for line in text.splitlines():
        line = line.strip()
        m = re.match(r"^\[(.+)\]$", line)
        if m:
            current = sections.setdefault(m.group(1).strip().lower(), {})
        elif current is not None and "=" in line:
            key, value = line.split("=", 1)
            current.setdefault(key.strip().lower(), value.strip())
    return sections


def fourcc(value):
    """Texture names are 4CC stored as a decimal u32, little-endian: 540103746 = 'BT1 '."""
    return struct.pack("<I", int(value) & 0xFFFFFFFF).decode("latin1").rstrip(" \0")


def floats(value, default):
    try:
        parts = [float(p) for p in value.split(",")]
        return parts if len(parts) == 4 else default
    except (AttributeError, ValueError):
        return default


def parse(text):
    ini = read_ini(text)
    head = ini.get("header", {})
    header = {k: floats(head.get(k), d) for k, d in HEADER_COLORS.items()}
    sections = []
    for i in range(int(head.get("count", 0))):
        s = ini.get("section%d" % i)
        if s is None:
            continue

        def names(state):
            return [fourcc(s.get("texture%d.%s" % (n, state), DEFAULT_TEXTURE)) for n in (1, 2, 3)]

        sections.append({
            "first": int(s.get("startslice", 0)),
            "last": int(s.get("endslice", 0)),
            "open": names("open"),
            "covered": names("covered"),
            "size": float(s.get("texturesize", DEFAULT_SIZE)),
            "aspect": float(s.get("aspect", DEFAULT_ASPECT)),
        })
    return header, sections


def env_textures(env_path, env_dir):
    """{name: png path relative to the track folder} of the .env images that are not fully clear."""
    index_path = os.path.join(env_dir, "index.json")
    if not os.path.exists(index_path):
        fsh2png.convert(env_path, env_dir)
    files = {e["name"].rstrip(" \0"): e["file"]
             for e in json.load(open(index_path, encoding="utf-8"))["entries"] if "file" in e}
    clear = set()
    for e in fsh2png.parse(open(env_path, "rb").read())[-1]:
        t, w, h, _, px = e["records"][0]
        if t == 0x7D and not any(px[3:w * h * 4:4]):  # 32-bit BGRA, alpha 0 everywhere
            clear.add(e["name"].rstrip(" \0"))
    rel = os.path.basename(env_dir)
    return {n: "%s/%s" % (rel, f) for n, f in files.items() if n not in clear}


def convert(map_path, out_path):
    header, sections = parse(open(map_path, encoding="latin1").read())
    out_dir = os.path.dirname(out_path)
    stem = os.path.splitext(os.path.basename(map_path))[0]
    env = find_file(os.path.dirname(map_path), stem + ".env")
    available = env_textures(env, os.path.join(out_dir, "env")) if env else {}
    used = sorted({n for s in sections for n in s["open"] + s["covered"]})
    missing = [n for n in used if n not in available and n != fourcc(DEFAULT_TEXTURE)]
    data = {
        "source": map_path.replace(os.sep, "/"),
        "header": header,
        "sections": sections,
        "textures": {n: available[n] for n in used if n in available},
    }
    os.makedirs(out_dir, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=1)
    return len(sections), len(data["textures"]), missing


def main(src, dst):
    if os.path.isfile(src):
        jobs = [(src, dst)]
    else:
        jobs = [(p, os.path.join(dst, rel, rel + "_decals.json")) for p, rel in source_files(src, [".map"], False)]
    for map_path, out_path in jobs:
        n, t, missing = convert(map_path, out_path)
        # Names the .env lacks: the original finds no texture there either (FUN_0044d320 -> 0).
        note = " (%d names clear or missing: %s)" % (len(missing), ", ".join(missing)) if missing else ""
        print("%s: %d sections, %d textures%s" % (out_path, n, t, note))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
