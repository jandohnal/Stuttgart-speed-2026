"""Convert the opponents' car profiles (.ais) and the AI steering setup (TRAFCFG.DAT) to JSON.

Format: docs/formats/ais.md. An .ais file is 304 bytes: the car family name
(32 bytes, zero padded), table A (24 float32), table B (40 float32) and 16
zero bytes. TRAFCFG.DAT is 27 int32 values; field names and types come from
TRAFCFG.DES (the original's editor description), Fixed fields are 16.16.

Usage:
    python3 tools/ais2json.py sources/GameData/Simulation decomposed/GameData/Simulation
"""
import json
import os
import struct
import sys

from common import find_file

AIS_SIZE = 304
TABLE_A = 24
TABLE_B = 40

# TRAFCFG.DES order: (name, fixed point); "NOT USED" fields are named as in the .DES.
GENERAL = [
    ("latvelcalc_lookahead", False),  # how far ahead to calculate lateral velocity (slices)
    ("min_lookahead", False),  # min metres to look ahead for the target direction
    ("max_lookahead", False),
    ("look_ahead_factor", True),  # speed to number of slices ahead for the target direction
    ("skid_value", True),  # for calculating front / rear skid
]
CONTROL = [
    ("dlpos_to_dlvel", True),  # delta lateral position -> desired lateral velocity
    ("max_dlvel", True),
    ("dlvel_to_clacc", True),  # delta desired lateral velocity -> lateral acceleration
    ("max_clacc_not_used", True),
    ("dangle_to_dav", True),  # delta angle -> desired angular velocity
    ("max_dav", True),
    ("dav_to_aa", True),  # delta desired angular velocity -> angular acceleration
    ("max_aa_not_used", True),
    ("vel_limit_range", True),  # under this speed lateral and angular velocity are limited
    ("lat_vel_limit_factor", True),
    ("ang_vel_limit_factor", True),
]


def read_ais(path):
    data = open(path, "rb").read()
    if len(data) != AIS_SIZE or any(data[32 + 4 * (TABLE_A + TABLE_B):]):
        raise ValueError(f"{path}: unexpected size or tail")
    a = struct.unpack_from(f"<{TABLE_A}f", data, 32)
    b = struct.unpack_from(f"<{TABLE_B}f", data, 32 + 4 * TABLE_A)
    return {
        "name": data[:32].split(b"\0")[0].decode("latin1").strip(),
        "table_a": [round(v, 3) for v in a],
        "table_b": [round(v, 3) for v in b],
    }


def read_trafcfg(path):
    raw = struct.unpack("<27i", open(path, "rb").read())
    values = iter(raw)

    def take(fields):
        return {name: round(next(values) / 65536, 4) if fixed else next(values) for name, fixed in fields}

    out = take(GENERAL)
    out["in_control"] = take(CONTROL)
    out["out_of_control"] = take(CONTROL)
    return out


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    src, dst = sys.argv[1], sys.argv[2]
    ais_dir = find_file(src, "AICarData")
    profiles = {}
    for f in sorted(os.listdir(ais_dir)):
        if f.lower().endswith(".ais"):
            profiles[os.path.splitext(f)[0].lower()] = read_ais(os.path.join(ais_dir, f))
    out = {
        "source": "AICarData/*.ais",
        "fields": "table_a: 24 values rising 8..30 (hypothesis: look-ahead in m by speed band); "
                  "table_b: 40 values falling (hypothesis: max speed in m/s by corner sharpness)",
        "profiles": profiles,
    }
    os.makedirs(os.path.join(dst, "AICarData"), exist_ok=True)
    with open(os.path.join(dst, "AICarData", "ais.json"), "w", encoding="utf-8") as f:
        json.dump(out, f, indent=1)
    print(f"ais.json: {len(profiles)} profiles")

    cfg = read_trafcfg(find_file(find_file(src, "AI"), "TRAFCFG.DAT"))
    cfg = {"source": "AI/TRAFCFG.DAT", "names": "AI/TRAFCFG.DES", **cfg}
    os.makedirs(os.path.join(dst, "AI"), exist_ok=True)
    with open(os.path.join(dst, "AI", "trafcfg.json"), "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=1)
    print("trafcfg.json:", json.dumps(cfg["in_control"]))


if __name__ == "__main__":
    main()
