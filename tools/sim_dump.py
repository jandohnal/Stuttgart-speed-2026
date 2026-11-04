"""Dump NFS5 .sim car physics files to JSON.

Field map: docs/formats/sim.md. Unknown fields are exported as raw values
under "unknown" so they can be analysed later.

Usage:
    python3 tools/sim_dump.py sources/GameData/Simulation/CarData decomposed/GameData/Simulation/cars.json
Without the second argument the JSON goes to standard output.
"""
import json
import os
import struct
import sys

ENGINE_POS = {0: "rear", 1: "mid", 2: "front"}


def f32(d, o):
    return round(struct.unpack_from("<f", d, o)[0], 4)


def i32(d, o):
    return struct.unpack_from("<i", d, o)[0]


def parse(d):
    gears = i32(d, 0x50)
    torque = []
    o = 0x9C
    while o < 0xF0:
        v = f32(d, o)
        if v == 0:
            break
        torque.append(v)
        o += 4
    known = {0x40, 0x44, 0x48, 0x4C, 0x50, 0x5C, 0x60, 0x80, 0x84, 0x88, 0x8C, 0x90, 0x94}
    known |= {0x68 + 4 * i for i in range(gears)}
    known |= {0x9C + 4 * i for i in range(len(torque))}
    unknown = {f"0x{o:03X}": (f32(d, o) if abs(struct.unpack_from("<f", d, o)[0]) > 1e-30 else i32(d, o))
               for o in range(0x40, len(d), 4)
               if o not in known and d[o:o + 4] != b"\0\0\0\0"}
    return {
        "name": d[:0x20].split(b"\0")[0].decode("latin1"),
        "mass_kg": f32(d, 0x40),
        "wheelbase_mm": f32(d, 0x44),
        "engine_position": ENGINE_POS.get(i32(d, 0x48), i32(d, 0x48)),
        "turbo": bool(i32(d, 0x4C)),
        "front_torque_split_pct": f32(d, 0x5C),
        "gears": [f32(d, 0x68 + 4 * i) for i in range(gears)],
        "reverse_ratio": f32(d, 0x60),
        "final_drive": f32(d, 0x80),
        "tyre": {"width_mm": f32(d, 0x84), "aspect_pct": f32(d, 0x88), "rim_in": f32(d, 0x8C)},
        "top_speed_mph": f32(d, 0x90),
        "redline_rpm": f32(d, 0x94),
        "torque_curve_lbft_per_500rpm": torque,
        "torque_peak_nm": round(max(torque) * 1.3558, 1) if torque else None,
        "unknown": unknown,
    }


def main(folder, target=None):
    cars = {}
    for fn in sorted(os.listdir(folder)):
        if fn.lower().endswith(".sim"):
            with open(os.path.join(folder, fn), "rb") as fh:
                cars[fn[:-4]] = parse(fh.read())
    if target is None:
        json.dump(cars, sys.stdout, indent=2, ensure_ascii=False)
        return
    os.makedirs(os.path.dirname(target) or ".", exist_ok=True)
    with open(target, "w", encoding="utf-8") as fh:
        json.dump(cars, fh, indent=2, ensure_ascii=False)


if __name__ == "__main__":
    main(*sys.argv[1:3])
