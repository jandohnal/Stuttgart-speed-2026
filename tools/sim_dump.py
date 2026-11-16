"""Dump NFS5 .sim car physics files to JSON.

Field map: docs/formats/sim.md. The fields beyond the basic ones are exported as
raw values under "unknown" (the game reads them there by offset) and, for those
whose meaning Porsche.exe confirmed, also by name under "fields" (file units).

Usage:
    python3 tools/sim_dump.py sources/GameData/Simulation/CarData decomposed/GameData/Simulation/cars.json
Without the second argument the JSON goes to standard output.
"""
import json
import os
import struct
import sys

ENGINE_POS = {0: "rear", 1: "mid", 2: "front"}
INDUCTION = {0: "natural", 1: "turbo", 2: "supercharged"}
# Offset: name of the fields read from "unknown" by meaning (docs/formats/sim.md, Porsche.exe).
NAMED = {
    0x054: "shift_delay_ticks", 0x058: "gear_efficiency_pct", 0x098: "engine_brake_pct",
    0x0F0: "front_grip_pct", 0x0F4: "grip", 0x0F8: "load_transfer_pct", 0x0FC: "steer_lock",
    0x104: "brake_decel_ms2", 0x108: "brake_front_pct", 0x10C: "downforce_front",
    0x110: "downforce_rear", 0x114: "pitch_damping_pct", 0x118: "roll_damping_pct",
    0x11C: "suspension_stiffness", 0x124: "ride_height_mm", 0x128: "pitch_per_accel",
    0x12C: "roll_per_accel", 0x130: "lateral_transfer_split", 0x134: "pitch_limit",
    0x138: "roll_limit", 0x13C: "ai_speed_scale", 0x140: "ai_profile_factor", 0x144: "ai_table_factor",
}


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
        "induction": INDUCTION.get(i32(d, 0x4C), i32(d, 0x4C)),
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
        "fields": {name: unknown["0x%03X" % o] for o, name in NAMED.items() if "0x%03X" % o in unknown},
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
