"""Convert the original's sky of each track (GameData/Track/Sky/<Track>.txt, .bin, .fsh) to JSON.

Format: docs/formats/sky.md (decoded from Porsche.exe, 15. 11. 2026). Per track:
    <Track>.txt  sky levels by computer capability: type (basic, multinormal ...), per weather
                 region A and B the sky maps, scales, wind, move ratio and warp, then the cloud
                 textures; text, "#" comments, values one per line
    <Track>.bin  SkyCnfig (29148 B, version 9): horizon ring (start angle, horz tile grid, height,
                 16 tiles), sky dome (size, curvature, height, rotation) and tables keyed by road
                 slice; the first one blends weather region A into B along the track
    <Track>.fsh  the textures, converted by tools/fsh2png.py to decomposed/GameData/Track/Sky/<Track>/

The file names differ in case from the track names (farmland -> Farmland.txt, forest.txt next to
Forest.bin); Porsche.exe opens them by track name on a case-insensitive file system and falls back
to default.txt / default.bin / default.fsh.

Writes decomposed/GameData/Track/<track>/<track>_sky.json for every converted track:
    {"source", "folder": "GameData/Track/Sky/<Track>", "textures": {name: png file in folder},
     "levels": [{"capability", "type", "blocks_sun", "regions": [A, B], "clouds": [3 names]}],
     "horizon": {...} | null, "dome": {...} | null, "region_blend": [[slice, 0..1], ...]}
    region = {"layers": [{"map", "scale": [x, y], "wind": [speed, direction_deg]}],
              "move_ratio", "warp": [speed, amount]}

Usage:
    python3 tools/sky.py sources/GameData/Track decomposed/GameData/Track
"""
import json
import os
import struct
import sys

from common import find_file

SKY_DIR = "Sky"
CONFIG_SIZE = 0x71DC
HORIZON_RADIUS = 400.0  # FUN_00459d30: ring of 16 segments around the camera
HORIZON_SEGMENTS = 16
TABLE_ENTRIES = 400
REGION_BLEND = 0x377 * 4  # 400 x (u32 slice, f32 value), -1 = unused (FUN_0045a2c0)
LAYER_TYPES = {"basic", "multinormal", "multiadditive", "multiattenuate", "multimodulate",
               "freecloud", "basicwater", "multinormalwater", "multiadditivewater",
               "multiattenuatewater", "multimodulatewater", "additive", "config"}


def tokens(text):
    """Values of the .txt, comments and blank lines left out."""
    out = []
    for line in text.splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            out.append(line)
    return out


def num(value):
    try:
        return float(value)
    except ValueError:
        return 0.0


def texture(name):
    return None if name.lower() == "none" else name


def parse_levels(text):
    """BEGIN ... END blocks. Multi* levels have 3 layers per region, basic ones 1."""
    levels, toks, i = [], tokens(text), 0
    while i < len(toks):
        if toks[i].upper() != "BEGIN":
            i += 1
            continue
        end = next((j for j in range(i + 1, len(toks)) if toks[j].upper() == "END"), len(toks))
        block = toks[i + 1:end]
        i = end + 1
        if len(block) < 3:
            continue
        capability, kind, blocks_sun = block[0].upper(), block[1].lower(), block[2].upper() == "YES"
        rest = block[3:]
        if kind.startswith("basic"):
            regions = []
            for r in range(2):
                v = rest[r * 10:r * 10 + 10]
                if len(v) < 10:
                    break
                regions.append({
                    "layers": [{"map": texture(v[0]), "map2": texture(v[1]), "texture": texture(v[2]),
                                "scale": [num(v[3]), num(v[4])], "wind": [num(v[6]), num(v[7])]}],
                    "move_ratio": num(v[5]), "warp": [num(v[8]), num(v[9])]})
            clouds = [r["layers"][0]["texture"] for r in regions[:1]]
        else:  # multi*: per region 3 maps, 3 x scales, 3 y scales, move ratio, 3 wind speeds,
            # 3 wind directions, warp speed, warp amount (FUN_0045b5a0); then 3 cloud textures
            regions = []
            for r in range(2):
                v = rest[r * 18:r * 18 + 18]
                if len(v) < 18:
                    break
                layers = [{"map": texture(v[k]), "scale": [num(v[3 + k]), num(v[6 + k])],
                           "wind": [num(v[10 + k]), num(v[13 + k])]} for k in range(3)]
                regions.append({"layers": layers, "move_ratio": num(v[9]), "warp": [num(v[16]), num(v[17])]})
            clouds = [texture(c) for c in rest[36:39]]
        levels.append({"capability": capability, "type": kind, "blocks_sun": blocks_sun,
                       "regions": regions, "clouds": clouds})
    return levels


def parse_config(data):
    """SkyCnfig (.bin): horizon, dome and the region blend table, or None for other files."""
    if len(data) < 0x4C:
        return None
    version = struct.unpack_from("<I", data, 0)[0]
    if version > 9:
        return None
    start, colour_offset, cols, rows, base, height = struct.unpack_from("<fIIIff", data, 4)
    tiles = [list(struct.unpack_from("<BB", data, 0x1C + 2 * k)) for k in range(HORIZON_SEGMENTS)]
    horizon = {"start_turns": start, "colour_offset": colour_offset, "grid": [cols, rows],
               "base": base, "height": height, "radius": HORIZON_RADIUS,
               "tiles": [{"tile": t, "flip": bool(f)} for t, f in tiles]}
    rotation, size, curvature, top = struct.unpack_from("<ffff", data, 0x3C)
    dome = {"size": size, "curvature": curvature, "height": top, "rotation_turns": rotation,
            "cells": 15}
    if len(data) >= 0xCE8:
        dome["scale"] = struct.unpack_from("<f", data, 0xCE4)[0]
    blend = []
    if version >= 9 and len(data) >= CONFIG_SIZE:
        for k in range(TABLE_ENTRIES):
            key, value = struct.unpack_from("<If", data, REGION_BLEND + 8 * k)
            if key == 0xFFFFFFFF or key > 100000:  # unused / uninitialised tail
                break
            blend.append([key, round(value, 4)])
    return {"version": version, "horizon": horizon, "dome": dome, "region_blend": blend}


def textures_in(folder):
    index = os.path.join(folder, "index.json")
    if not os.path.exists(index):
        return {}
    return {e["name"].strip(): e["file"] for e in json.load(open(index, encoding="utf-8"))["entries"]
            if "file" in e}


def sky_files(sky_src, track):
    """(txt, bin, fsh) of the track, each falling back to default.* as Porsche.exe does."""
    def pick(ext):
        return find_file(sky_src, track + ext) or find_file(sky_src, "default" + ext)
    return pick(".txt"), pick(".bin"), pick(".fsh")


def convert(src, dst, track):
    sky_src = os.path.join(src, SKY_DIR)
    txt, binf, fsh = sky_files(sky_src, track)
    if txt is None:
        return None
    folder_name = os.path.splitext(os.path.basename(fsh))[0] if fsh else "default"
    folder = os.path.join(dst, SKY_DIR, folder_name)
    config = parse_config(open(binf, "rb").read()) if binf else None
    out = {
        "source": txt.replace(os.sep, "/"),
        "folder": "GameData/Track/%s/%s" % (SKY_DIR, folder_name),
        "textures": textures_in(folder),
        "levels": parse_levels(open(txt, encoding="latin1").read()),
        "horizon": config["horizon"] if config else None,
        "dome": config["dome"] if config else None,
        "region_blend": config["region_blend"] if config else [],
    }
    path = os.path.join(dst, track, track + "_sky.json")
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=1)
    return path, out


def main(src, dst):
    tracks = sorted(t for t in os.listdir(dst)
                    if os.path.isfile(os.path.join(dst, t, t + ".gltf")))
    for track in tracks:
        result = convert(src, dst, track)
        if result is None:
            print("%s: no sky" % track, file=sys.stderr)
            continue
        path, out = result
        used = {n for lv in out["levels"] for r in lv["regions"] for layer in r["layers"]
                for n in (layer.get("map"), layer.get("texture")) if n and n != "flat"}
        used |= {c for lv in out["levels"] for c in lv["clouds"] if c and c != "flat"}
        missing = sorted(used - set(out["textures"]))
        note = " (textures not in the .fsh: %s)" % ", ".join(missing) if missing else ""
        print("%s: %s, %d levels, %d blend keys%s" % (path, out["folder"], len(out["levels"]),
                                                     len(out["region_blend"]), note))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
