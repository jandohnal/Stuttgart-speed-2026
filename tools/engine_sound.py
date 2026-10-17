"""Describe the engine sound sets of NFS5 (sd*.viv converted by tools/snd2wav.py) for the game.

Format: docs/formats/bnk.md (chapter "Tabulky motoru"). For every set folder writes
<set>/engine.json: the loops the engine tables use, grouped into "load" (on throttle, *lt tables)
and "coast" (off throttle and idle, *ct tables), two layers each (the two sample groups of a
table, played together), and for every loop the engine speed it was recorded at.

The tables (CRDl) are only partly decoded: bytes 0x20..0x27 list two groups of four bank indices
(index + 1, 0 = none); the crossfade grid after them is not used yet. The recorded speed comes
from the loop's MIDI root note (PT tag 0x07): firing frequency = note frequency, a flat four
fires twice per turn, so rpm = frequency * 60 / 2 (--cylinders changes the factor).

Usage:
    python3 tools/engine_sound.py decomposed/GameData/Sounds
"""
import argparse
import json
import os

TABLES = {"load": ("elt", "clt"), "coast": ("ect", "cct")}  # exterior first, cockpit second


def note_hz(note):
    return 440.0 * 2.0 ** ((note - 69) / 12.0)


def table_slots(path):
    """The table's two groups of four bank indices (None where empty)."""
    data = open(path, "rb").read()
    if data[:4] != b"CRDl":
        raise ValueError(f"{path}: not a CRDl table")
    ids = [b + 1 if b else None for b in data[0x20:0x28]]
    return [ids[0:4], ids[4:8]]


def describe(set_dir, cylinders):
    name = os.path.basename(set_dir.rstrip("/"))
    bank_dir = os.path.join(set_dir, name)
    index = {e["index"]: e for e in json.load(open(os.path.join(bank_dir, "index.json")))["sounds"]}
    fires_per_turn = cylinders / 2.0  # four stroke
    out = {"set": name, "cylinders": cylinders, "view": "exterior", "groups": {}}
    for group, (exterior, _cockpit) in TABLES.items():
        layers = []
        for slots in table_slots(os.path.join(set_dir, f"{name}.{exterior}")):
            loops = []
            for i in slots:
                e = index.get(i)
                if e is None or "0x07" not in e.get("tags", {}):
                    continue
                note = e["tags"]["0x07"]
                loops.append({"index": i, "file": f"{name}/{e['file']}", "note": note,
                              "rpm": round(note_hz(note) * 60.0 / fires_per_turn),
                              "rate": e["rate"], "samples": e["samples"],
                              "loop_start": e.get("loop_start", 0), "loop_end": e.get("loop_end", e["samples"] - 1)})
            if loops:
                layers.append(sorted(loops, key=lambda x: x["rpm"]))
        out["groups"][group] = layers
    with open(os.path.join(set_dir, "engine.json"), "w") as fh:
        json.dump(out, fh, indent=1)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("sounds", help="decomposed/GameData/Sounds")
    ap.add_argument("--cylinders", type=int, default=4)
    a = ap.parse_args()
    for name in sorted(os.listdir(a.sounds)):
        set_dir = os.path.join(a.sounds, name)
        if not (name.startswith("sd") and os.path.exists(os.path.join(set_dir, f"{name}.elt"))):
            continue
        try:
            info = describe(set_dir, a.cylinders)
        except (ValueError, OSError) as e:
            print(f"{name}: {e}")
            continue
        summary = {g: [[l["rpm"] for l in layer] for layer in layers] for g, layers in info["groups"].items()}
        print(f"{name}: {summary}")


if __name__ == "__main__":
    main()
