"""Convert NFS5 AI configuration CSVs to JSON.

Format: docs/formats/ai-csv.md. Every CSV has a compiled twin (.bin): a stream
of int32 values, where numbers after "!FIXED" are 16.16 fixed point (truncated)
and numbers after "!INT" are plain integers. Each parser rebuilds that stream
from the parsed data and compares it with the .bin, so the JSON is verified.

Usage:
    python3 tools/ai_csv2json.py sources/GameData/Simulation/AI decomposed/GameData/Simulation/AI
"""
import csv
import io
import json
import os
import re
import struct
import sys

from common import find_file


class Stream:
    """Values in .bin order."""

    def __init__(self):
        self.values = []

    def int(self, v):
        self.values.append(int(v))

    def fixed(self, v):
        self.values.append(int(float(v) * 65536))


def read_rows(path):
    text = open(path, encoding="latin1", newline="").read().replace("\x85", "\n")
    return [[c.strip() for c in row] for row in csv.reader(io.StringIO(text))]


def is_num(s):
    return bool(re.fullmatch(r"-?\d+(\.\d+)?", s or ""))


def cell(row, i):
    return row[i] if i < len(row) else ""


def snake(s):
    return re.sub(r"[^a-z0-9]+", "_", re.sub(r"([a-z])([A-Z])", r"\1_\2", s.strip()).lower()).strip("_")


def header(rows, st):
    verbose = next(int(r[1]) for r in rows if r and r[0].lower().startswith("verbose"))
    st.int(verbose)
    return {"verbose": verbose}


def symbols(rows):
    out = {}
    for r in rows:
        if "Symbol:" in r:
            i = r.index("Symbol:")
            out[cell(r, i + 1).lower()] = (int(cell(r, i + 2)), cell(r, i + 3))
    return out


def personality_id(s):
    m = re.match(r"Personality\s*(\d+)", s)
    return int(m.group(1)) if m else None


# --- glue.csv / hhglue.csv: catch-up ("rubber band") speed multipliers ---------------

def parse_glue(rows, st):
    out = header(rows, st)
    out["description"] = "Opponent speed multiplier by distance to the player (ahead -> behind)"
    out["rows"] = []
    fixed = False
    for r in rows:
        if r and r[0] == "!FIXED":
            fixed = True
        elif fixed and is_num(cell(r, 1)):
            st.fixed(r[1])
            out["rows"].append({"player": cell(r, 3), "speed_multiplier": float(r[1])})
    return out


# --- prsonal.csv: opponent personalities ---------------------------------------------

def parse_personalities(rows, st):
    out = header(rows, st)
    sym = symbols(rows)
    out["levels"] = {"low": 0, "medium": 1, "high": 2, "extreme": 3}
    out["trait_descriptions"], out["personalities"] = {}, []
    current = None
    for r in rows:
        if r and personality_id(r[0]) is not None:
            current = {"id": personality_id(r[0]), "name": cell(r, 1), "traits": {}}
            out["personalities"].append(current)
        elif current is not None and r and r[0] == "" and cell(r, 1) and cell(r, 2).lower() in sym:
            key = snake(r[1])
            value = sym[r[2].lower()][0]
            st.int(value)
            current["traits"][key] = value
            if cell(r, 3):
                out["trait_descriptions"][key] = r[3]
    return out


# --- SCRIPTS.CSV: reactions to player actions -----------------------------------------

def parse_scripts(rows, st):
    out = header(rows, st)
    sym = symbols(rows)
    out["reactions"] = {name.upper(): {"id": v, "description": d} for name, (v, d) in sym.items()}
    out["personalities"] = []
    current, action = None, None
    for r in rows:
        if r and personality_id(r[0]) is not None:
            current = {"id": personality_id(r[0]), "name": cell(r, 1), "scripts": {}}
            out["personalities"].append(current)
        elif current is not None and cell(r, 3).lower() in sym and is_num(cell(r, 4)):
            if cell(r, 1):
                action = snake(r[1])
                current["scripts"][action] = []
            value = sym[r[3].lower()][0]
            st.int(value)
            st.int(r[4])
            current["scripts"][action].append({"reaction": r[3].upper(), "time_s": int(r[4])})
    return out


# --- SPREAD.CSV: target lap times and speed spread between opponents -------------------

def parse_spread(rows, st):
    out = header(rows, st)
    sym = symbols(rows)
    out["track_lap_times_s"], out["tables"] = [], []
    table = None
    for r in rows:
        first = r[0] if r else ""
        if cell(r, 1) == "Track" and is_num(cell(r, 2)):
            st.int(r[2])
            st.int(r[3])
            out["track_lap_times_s"].append({"track": int(r[2]), "lap_time_s": int(r[3])})
        elif cell(r, 2) == "END":
            st.int(sym["end"][0])
            st.int(sym["end"][0])
        elif first.startswith("Fixed Spread Table"):
            table = {"name": first.replace("Fixed Spread Table for", "").strip(), "factors": {}}
            out["tables"].append(table)
        elif first.startswith("Number of Spread Tables"):
            out["timed_table_count"] = int(cell(r, 3))
            st.int(r[3])
        elif first.startswith("Use Interpolation"):
            out["interpolation"] = bool(sym[cell(r, 3).lower()][0])
            st.int(sym[cell(r, 3).lower()][0])
        elif cell(r, 1).startswith("Spread Table"):
            table = {"name": r[1], "factors": {}}
            out["tables"].append(table)
        elif cell(r, 1) == "Time (s)" and table is not None:
            table["time_s"] = int(r[2])
            st.int(r[2])
        elif table is not None and first == "" and cell(r, 1) and is_num(cell(r, 2)):
            st.fixed(r[2])
            table["factors"][r[1]] = float(r[2])
    return out


# --- tuning.csv: convoy slots, car / track / weather / upgrade multipliers -------------

def parse_tuning(rows, st):
    out = header(rows, st)
    out["slots"], out["car_multipliers"], out["track_multipliers"], out["upgrades"] = [], {}, [], {}
    section = None

    def num_or_none(s, emit):
        if s == "N/A":
            emit(0)
            return None
        emit(s)
        return float(s) if "." in s else int(s)

    for r in rows:
        first = r[0] if r else ""
        if re.fullmatch(r"[A-F]( \(\w+\))?", first) and len(r) > 4:
            names = ("distance_change_time_s", "min_distance_m", "max_distance_m", "fall_back_freq_s")
            slot = {"slot": first}
            for name, v in zip(names, r[1:5]):
                slot[name] = num_or_none(v, st.int)
            out["slots"].append(slot)
        elif first.startswith("TRACK MULTIPLIERS"):
            section = "track"
        elif first.startswith("WEATHER MULTIPLIER"):
            section = "weather"
        elif first.startswith("Upgrades"):
            section = "upgrades"
        elif re.fullmatch(r"[A-Z0-9]{4}", first) and is_num(cell(r, 1)):
            vals = [float(v) for v in r[1:4]]
            for v in r[1:4]:
                st.fixed(v)
            out["car_multipliers"][first] = dict(zip(("beginner", "advanced", "expert"), vals))
        elif section == "track" and first.isdigit():
            st.fixed(first)
            st.fixed(r[4])
            st.fixed(r[7])
            out["track_multipliers"].append(
                {"track": int(first), "name": r[2], "overall": float(r[4]), "night": float(r[7])})
        elif section == "weather" and is_num(first):
            st.fixed(first)
            out["weather_curve_multiplier"] = float(first)
        elif section == "upgrades" and first and is_num(cell(r, 3)):
            vals = [r[3], r[5], r[7], r[9]]
            for v in vals:
                st.fixed(v)
            out["upgrades"][first] = dict(zip(("acceleration", "brake", "handling", "top_speed"), map(float, vals)))
    return out


def reconcile_personalities(data, expected):
    """prsonal.bin was compiled from a different CSV revision: take trait values from the
    .bin (what the game reads) and keep differing CSV values under "csv_traits"."""
    values = iter(expected[1:])
    for p in data["personalities"]:
        csv_traits = p["traits"]
        p["traits"] = {k: next(values) for k in csv_traits}
        diff = {k: v for k, v in csv_traits.items() if p["traits"][k] != v}
        if diff:
            p["csv_traits"] = diff
    data["note"] = ("Trait values come from prsonal.bin. The CSV is a different revision; "
                    "where it differs, its values are in csv_traits. SCRIPTS.CSV and SPREAD.CSV "
                    "call personalities 1-4 Blurrr, Zippy, JetBoy, Menace.")


PARSERS = {
    "glue": parse_glue,
    "hhglue": parse_glue,
    "prsonal": parse_personalities,
    "scripts": parse_scripts,
    "spread": parse_spread,
    "tuning": parse_tuning,
}


def convert(path, out_dir):
    stem = os.path.splitext(os.path.basename(path))[0].lower()
    rows, st = read_rows(path), Stream()
    data = PARSERS[stem](rows, st)
    data = {"source": os.path.basename(path), **data}
    status = "no .bin"
    bin_path = find_file(os.path.dirname(path), stem + ".bin")
    if bin_path:
        raw = open(bin_path, "rb").read()
        expected = list(struct.unpack(f"<{len(raw) // 4}i", raw))
        if expected == st.values:
            status = f"OK, matches {os.path.basename(bin_path)} ({len(expected)} values)"
        elif stem == "prsonal" and len(expected) == len(st.values):
            reconcile_personalities(data, expected)
            n = sum(a != b for a, b in zip(expected, st.values))
            status = f"OK, values taken from {os.path.basename(bin_path)} ({n} of {len(expected)} differ from CSV)"
        else:
            i = next((i for i, (a, b) in enumerate(zip(expected, st.values)) if a != b),
                     min(len(expected), len(st.values)))
            status = (f"MISMATCH with {os.path.basename(bin_path)}: {len(st.values)} vs {len(expected)} values, "
                      f"first difference at {i}")
    data["verified_against_bin"] = status.startswith("OK, matches")
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, stem + ".json"), "w") as fh:
        json.dump(data, fh, indent=2, ensure_ascii=False)
    return status


def main(src, dst):
    ok = True
    for fn in sorted(os.listdir(src)):
        stem, ext = os.path.splitext(fn)
        if ext.lower() == ".csv" and stem.lower() in PARSERS:
            status = convert(os.path.join(src, fn), dst)
            ok &= status.startswith("OK")
            print(f"{fn}: {status}")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
