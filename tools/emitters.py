"""Particle emitters of the tracks (ef entries of kind 3) with their full basis, to JSON.

The emitter's ef entry stores two basis rows (docs/formats/crp.md, "Efekty"): "direction" (the
first) and "up" (the second, the axis the system's emit.y speed runs along; particle.ini, see
docs/formats/particle.md). <track>_lights.json from track2gltf.py keeps only "direction".
Emitters on placed objects (tr matrix further than PLACED_MIN_DISTANCE from the origin) are moved
into the world; ones on prototypes at the origin (hydrants placed by events) are skipped.

Output <track>_emitters.json:
    {"source": ..., "emitters": [{"id", "article", "position", "direction", "up"}]}

Usage:
    python3 tools/emitters.py sources/GameData/Track decomposed/GameData/Track
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from crp import EFFECT_EMITTER, article_effects, article_matrix, entry_text, find, parse_crp  # noqa: E402

PLACED_MIN_DISTANCE = 50.0  # m, as in track2gltf.py


def transform(m, v, w):
    """glTF column-major 4x4 times (v, w)."""
    return [m[0] * v[0] + m[4] * v[1] + m[8] * v[2] + m[12] * w,
            m[1] * v[0] + m[5] * v[1] + m[9] * v[2] + m[13] * w,
            m[2] * v[0] + m[6] * v[1] + m[10] * v[2] + m[14] * w]


def track_emitters(path):
    d, arts, _misc = parse_crp(open(path, "rb").read())
    out = []
    for art in arts:
        name_e = find(art.sub, "Name")
        if name_e is None:
            continue
        name = entry_text(d, name_e)
        m = article_matrix(d, art)
        if m is not None and math.hypot(m[12], m[14]) <= PLACED_MIN_DISTANCE:
            continue
        for e in article_effects(d, art):
            if e["kind"] != EFFECT_EMITTER:
                continue
            pos, fwd, up = e["position"], e["direction"], e["up"]
            if m is not None:
                pos, fwd, up = transform(m, pos, 1.0), transform(m, fwd, 0.0), transform(m, up, 0.0)
            out.append({"id": e["id"], "article": name, "position": [round(x, 3) for x in pos],
                        "direction": [round(x, 4) for x in fwd], "up": [round(x, 4) for x in up]})
    return out


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    src, dst = sys.argv[1], sys.argv[2]
    for name in sorted(os.listdir(src)):
        stem, ext = os.path.splitext(name)
        if ext.lower() != ".crp":
            continue
        emitters = track_emitters(os.path.join(src, name))
        out_dir = os.path.join(dst, stem)
        if not os.path.isdir(out_dir):
            continue  # track not converted (track2gltf.py)
        with open(os.path.join(out_dir, stem + "_emitters.json"), "w", encoding="utf-8") as f:
            json.dump({"source": os.path.join(src, name), "emitters": emitters}, f, indent=1)
        ids = {}
        for e in emitters:
            ids[e["id"]] = ids.get(e["id"], 0) + 1
        print("%-12s %3d emitters %s" % (stem, len(emitters), dict(sorted(ids.items()))))


if __name__ == "__main__":
    main()
