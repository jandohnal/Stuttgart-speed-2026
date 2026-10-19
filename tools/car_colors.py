"""Extract the paint colours of the NFS5 cars from the front-end car database.

Format: docs/formats/car.md. FEData/Data/nfs5.car is a list of 0x670-byte
records, one per car variant. Each record holds the exterior palette (body
colour + two accent colours per entry, the first entry is the car's factory
colour) and the interior colours.

Output JSON:
    {"models": {"<model>": {"exterior": ["#rrggbb", ...], "interior": [...],
                            "accents": [["#rrggbb", "#rrggbb"], ...], "flags": [...]}},
     "cars": {"<variant key>": {"name": ..., "model": ..., "default": "#rrggbb",
                                "styles": {"<model>": N}}}}
Models and their palettes come from the first record of the model (the other
variants only reorder it); the default colour is per variant. styles: the
[styleN] of the model's .tpg (parts and textures, tools/crp2gltf.py) the variant
uses on each model; a key repeats for its police and factory records.

Usage:
    python3 tools/car_colors.py sources/FEData/Data/nfs5.car decomposed/FEData/Data/car_colors.json
"""
import json
import os
import struct
import sys

RECORD = 0x670
NAME, MODEL, KEY = 0x02, 0x7F, 0xB1
STRING = 0x31
EXTERIOR = 0x3E6  # u16 count, then 16-byte entries
STYLE = 0x1C0  # u8: [styleN] of the model's .tpg minus 1
ENTRY = 16


def cstr(rec, offset):
    return rec[offset:offset + STRING].split(b"\0")[0].decode("latin1")


def colour(raw):
    """[0xFF, R, G, B] -> #rrggbb."""
    return "#" + raw[1:4].hex()


def parse_record(rec):
    count = struct.unpack_from("<H", rec, EXTERIOR)[0]
    exterior, accents, flags = [], [], []
    for k in range(count):
        e = rec[EXTERIOR + 2 + ENTRY * k:EXTERIOR + 2 + ENTRY * (k + 1)]
        flags.append(struct.unpack_from("<I", e, 0)[0])
        exterior.append(colour(e[4:8]))
        accents.append([colour(e[8:12]), colour(e[12:16])])
    # 16 zero bytes, then u32 count of interior entries (one colour each, rest black).
    o = EXTERIOR + 2 + ENTRY * count + 16
    interior = []
    if o + 4 <= len(rec):
        n = struct.unpack_from("<I", rec, o)[0]
        for k in range(n):
            interior.append(colour(rec[o + 4 + ENTRY * k + 4:o + 4 + ENTRY * k + 8]))
    return {"exterior": exterior, "accents": accents, "flags": flags, "interior": interior}


def convert(data):
    if len(data) % RECORD:
        raise ValueError("size %d is not a multiple of 0x%x" % (len(data), RECORD))
    models, cars = {}, {}
    for r in range(len(data) // RECORD):
        rec = data[r * RECORD:(r + 1) * RECORD]
        model = cstr(rec, MODEL).lower()
        colours = parse_record(rec)
        if model not in models:
            models[model] = colours
        elif sorted(colours["exterior"]) != sorted(models[model]["exterior"]):
            print("warning: %s palette differs between variants" % model, file=sys.stderr)
        key = cstr(rec, KEY)
        styles = cars.get(key, {}).get("styles", {})
        styles[model] = rec[STYLE] + 1
        cars[key] = {
            "name": cstr(rec, NAME),
            "model": model,
            "default": colours["exterior"][0] if colours["exterior"] else None,
            "styles": styles,
        }
    return {"models": models, "cars": cars}


def model_styles(data):
    """{model (lower case): [style of each variant, in file order]}."""
    out = {}
    for r in range(len(data) // RECORD):
        rec = data[r * RECORD:(r + 1) * RECORD]
        out.setdefault(cstr(rec, MODEL).lower(), []).append(rec[STYLE] + 1)
    return out


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    out = convert(open(sys.argv[1], "rb").read())
    os.makedirs(os.path.dirname(sys.argv[2]) or ".", exist_ok=True)
    with open(sys.argv[2], "w") as f:
        json.dump(out, f, indent=1, ensure_ascii=False)
    print("%d models, %d cars -> %s" % (len(out["models"]), len(out["cars"]), sys.argv[2]))


if __name__ == "__main__":
    main()
