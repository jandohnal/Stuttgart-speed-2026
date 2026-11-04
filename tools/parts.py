"""Extract the NFS5 performance parts and pick the Stock / Sport sets of every car.

Format: docs/formats/prt.md. FEData/Data/nfs5.prt is the parts catalogue
(0x168-byte records); every record of FEData/Data/nfs5.car lists the parts the
shop offers for that variant and the parts installed at the factory. The way a
part changes the .sim values is in docs/formats/prt.md (Porsche.exe 0x49CB50);
game/scripts/car_parts.gd applies it.

Output JSON:
    {"parts": {"<id>": {"name", "group", "category", "year", "mass_kg", "vmax_pct",
                        "effect": [c0, c4], "tyre_type", "shift_delay",
                        "gearbox": {"gears", "reverse", "ratios", "final"},
                        "torque_curve": [...]}},
     "cars": {"<variant key>": {"applies": bool, "stock": [id], "sport": [id],
                                "stock_tyre_type": 0 | 2, "tyres": {"slick": id, "rain": id}}},
     "tyre_grip": [stock, rain, slick], "formula": {name: constant}}
The variant key is the key in cars.json. stock = parts installed at the factory
(all neutral: the .sim already is the stock car); sport = the best part of
every group the car's list offers (tyres and looks left out, see best_part).
tyres: the slick / rain tyre the list offers; the factory tyre is neutral, its
type is stock_tyre_type (racing slicks on the race cars). applies = false for
the cars whose physics ignores parts in the original. tyre_grip: grip factor of
each tyre type on dry asphalt; formula: the constants of the part formulas.
tyre_grip, formula and the families without parts are read from Porsche.exe
next to FEData (sources/Porsche.exe), never kept in the repository (D-023).

Usage:
    python3 tools/parts.py sources/FEData decomposed/FEData/Data/parts.json [--report]
"""
import csv
import json
import os
import struct
import sys

PART = 0x168
CAR = 0x670
# nfs5.car (file offsets; Porsche.exe sees the record 2 bytes later)
CAR_KEY, CAR_AIS = 0xB1, 0x115  # cars.json key; AI / physics family name ("356", "GT1", "959")
OFFERED = 0x32E  # i16 count, i16 part ids: what the shop offers
INSTALLED = 0x3B6  # i16 count, i16 part ids: fitted at the factory
STRING = 0x31

# Categories (nfs5.prt 0x26)
ENGINE, BRAKES, GEARBOX, SPRINGS, SHOCKS, AERO, BODY, SWAY, TYRES, LOOKS = 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
TYRE_TYPES = {0: "stock", 1: "rain", 2: "slick"}

# Porsche.exe (official patch of 5 June 2000, docs/formats/prt.md): addresses of what the parts
# code uses. Values are read from the local exe, never copied into the repository (D-023).
# Constants of the part formulas (0x49CB50), by the name parts.json gives them.
EXE_FORMULA = {
    "engine_added_share": 0x5B4A38,  # engine parts other than a whole engine add this x their curve
    "brake_add": 0x5B2600, "brake_scale": 0x5B2468,  # 0x104 *= (c0 + add) * scale
    "spring_add": 0x5B2404, "spring_scale": 0x5B2694,  # 0x11C, 0x130 *= (c0 + add) * scale
    "spring_grip_add": 0x5B243C, "spring_grip_scale": 0x5B26A4,  # 0x0F4 *= (c0 + add) * scale
    "damper_grip_add": 0x5B263C, "damper_grip_scale": 0x5B49B0,  # shocks, sway bars: 0x0F4
    "aero_scale": 0x5B3284,  # 0x10C *= 1 + c0 * scale, 0x110 *= 1 + c4 * scale
    "tyre_weight": 0x5B2600, "tyre_third": 0x5B2680, "tyre_half": 0x5B23F0,
}
EXE_NO_PARTS = [0x5D0D28, 0x5D0D24, 0x5D0D34, 0x5D0D30]  # families whose physics ignores parts
EXE_RACE_TYRES = [0x5D0D38, 0x5D0D34, 0x5D0D30, 0x5D0D2C]  # families on racing slicks
EXE_SURFACE_GRIP_DRY = 0x5D0D50  # f32[surface][tyre type 0..2], dry weather
ASPHALT = 1  # surface row of dry asphalt
# cars.json variants without an nfs5.car record of their own: the record whose parts they get.
ALIASES = {"993coupe4s36": "993coupes436", "944tcoupes25": "944tcoupe25"}


class Exe:
    """Reads values of Porsche.exe by virtual address (PE sections)."""

    def __init__(self, path):
        self.data = open(path, "rb").read()
        pe = struct.unpack_from("<I", self.data, 0x3C)[0]
        count, opt = struct.unpack_from("<H", self.data, pe + 6)[0], struct.unpack_from("<H", self.data, pe + 20)[0]
        base = struct.unpack_from("<I", self.data, pe + 24 + 28)[0]
        self.sections = []
        for k in range(count):
            vsize, va, rsize, raw = struct.unpack_from("<IIII", self.data, pe + 24 + opt + 40 * k + 8)
            self.sections.append((base + va, max(vsize, rsize), raw))

    def offset(self, va):
        for start, size, raw in self.sections:
            if start <= va < start + size:
                return va - start + raw
        raise ValueError("address 0x%x outside the exe" % va)

    def f32(self, va):
        return round(struct.unpack_from("<f", self.data, self.offset(va))[0], 6)

    def text(self, va):
        o = self.offset(va)
        return self.data[o:o + 16].split(b"\0")[0].decode("latin1")


def cstr(rec, offset, size=STRING):
    return rec[offset:offset + size].split(b"\0")[0].decode("latin1")


def f32(rec, offset):
    return round(struct.unpack_from("<f", rec, offset)[0], 4)


def i16(rec, offset):
    return struct.unpack_from("<h", rec, offset)[0]


def names(locale):
    """English part names by string id from festrings.csv."""
    out = {}
    with open(locale, encoding="latin1", newline="") as f:
        for row in csv.reader(f):
            if row and row[0].isdigit() and len(row) > 1:
                out[int(row[0])] = row[1]
    return out


def parse_part(rec, texts):
    category = i16(rec, 0x26)
    group = cstr(rec, 0x28, 0x1E)
    part = {
        "name": texts.get(struct.unpack_from("<I", rec, 4)[0], ""),
        "series": cstr(rec, 0x08, 0x1E),
        "group": "Engine" if group == "Engine (Standard)" else (group or "Tyres"),
        "category": category,
        "year": i16(rec, 0x46),
        "mass_kg": f32(rec, 0x54),
        "vmax_pct": f32(rec, 0x58),
        "effect": [f32(rec, 0xC0), f32(rec, 0xC4)],
    }
    curve = [f32(rec, 0x110 + 4 * i) for i in range(21)]
    if any(curve):
        part["torque_curve"] = curve
        part["replaces_curve"] = group == "Engine"
    if category == ENGINE and group in ("Turbo", "Supercharged"):
        part["induction"] = 1 if group == "Turbo" else 2
    if category == TYRES:
        part["tyre_type"] = struct.unpack_from("<i", rec, 0xC8)[0]
    if category == GEARBOX:
        part["shift_delay"] = i16(rec, 0xEC)
        if group == "Gear Box":
            gears = i16(rec, 0xEA)
            part["gearbox"] = {
                "gears": gears,
                "final": f32(rec, 0xC0),
                "reverse": f32(rec, 0xF0),
                "ratios": [f32(rec, 0xF8 + 4 * i) for i in range(gears)],
            }
    return part


def id_list(rec, offset):
    n = i16(rec, offset)
    return [i16(rec, offset + 2 + 2 * k) for k in range(max(n, 0))]


def power(curve, redline):
    """Peak of torque x rpm (relative units) up to the redline."""
    return max((t * 500 * i for i, t in enumerate(curve) if 500 * i <= redline), default=0.0)


def best_part(group, options, sim, formula):
    """The part of `group` Sport fits: most power, braking, grip, downforce or least mass.
    Gearbox: the one with most gears whose top gear still reaches the car's top speed, ties
    to the shortest gearing."""
    first = options[0]
    category = first["category"]
    if category == ENGINE:
        curve = sim["torque_curve_lbft_per_500rpm"] + [0.0] * 21
        def gain(p):
            c = p.get("torque_curve")
            if c is None:
                return power(curve, sim["redline_rpm"])
            if p.get("replaces_curve"):
                return power(c, sim["redline_rpm"])
            share = formula["engine_added_share"]
            return power([a + share * b for a, b in zip(curve, c)], sim["redline_rpm"])
        return max(options, key=gain)
    if category in (BRAKES, SPRINGS, SHOCKS, SWAY):
        return max(options, key=lambda p: p["effect"][0])
    if category == AERO:
        return max(options, key=lambda p: p["effect"][0] + p["effect"][1])
    if category == BODY:
        return min(options, key=lambda p: p["mass_kg"])
    if category == GEARBOX:
        if group != "Gear Box":
            return min(options, key=lambda p: p["shift_delay"])
        tyre = sim["tyre"]
        circumference = (tyre["rim_in"] * 25.4 + 2 * tyre["width_mm"] * tyre["aspect_pct"] / 100) / 1000 * 3.14159
        def top_mph(p):
            g = p["gearbox"]
            return sim["redline_rpm"] / (g["ratios"][-1] * g["final"]) * circumference * 60 / 1609.34
        fast = [p for p in options if top_mph(p) >= 0.98 * sim["top_speed_mph"]] or [max(options, key=top_mph)]
        return max(fast, key=lambda p: (p["gearbox"]["gears"], -p["shift_delay"], -top_mph(p)))
    return None


def convert(fe, exe_path, sims):
    exe = Exe(exe_path)
    formula = {name: exe.f32(va) for name, va in EXE_FORMULA.items()}
    no_parts = {exe.text(va).lower() for va in EXE_NO_PARTS}
    race_tyres = {exe.text(va).lower() for va in EXE_RACE_TYRES}
    tyre_grip = [exe.f32(EXE_SURFACE_GRIP_DRY + 4 * (ASPHALT * 3 + k)) for k in range(3)]
    texts = names(os.path.join(fe, "Locale", "festrings.csv"))
    prt = open(os.path.join(fe, "Data", "nfs5.prt"), "rb").read()
    parts = {}
    for r in range(len(prt) // PART):
        rec = prt[r * PART:(r + 1) * PART]
        parts[i16(rec, 0)] = parse_part(rec, texts)
    car = open(os.path.join(fe, "Data", "nfs5.car"), "rb").read()
    records = {}  # lower-case key -> first record that offers parts (police and factory records repeat it)
    for r in range(len(car) // CAR):
        rec = car[r * CAR:(r + 1) * CAR]
        key = cstr(rec, CAR_KEY).lower()
        if key not in records and any(i in parts for i in id_list(rec, OFFERED)):
            records[key] = rec
    cars = {}
    for key, sim in sims.items():
        rec = records.get(key.lower()) or records.get(ALIASES.get(key.lower(), ""))
        if rec is None:
            continue
        offered = [i for i in id_list(rec, OFFERED) if i in parts]
        family = cstr(rec, CAR_AIS).lower()
        groups = {}
        for i in offered:
            p = parts[i]
            if p["category"] not in (TYRES, LOOKS):
                groups.setdefault((p["category"], p["group"]), []).append(dict(p, id=i))
        sport = []
        for (category, group), options in sorted(groups.items()):
            best = best_part(group, options, sim, formula)
            if best is not None:
                sport.append(best["id"])
        tyres = {}
        for i in offered:
            kind = TYRE_TYPES.get(parts[i].get("tyre_type", -1))
            if parts[i]["category"] == TYRES and kind in ("slick", "rain") and kind not in tyres:
                tyres[kind] = i
        cars[key] = {
            "applies": family not in no_parts,
            "stock_tyre_type": 2 if family in race_tyres else 0,
            "stock": [i for i in id_list(rec, INSTALLED) if i in parts],
            "sport": sport,
            "tyres": tyres,
        }
    used = {i for c in cars.values() for i in c["stock"] + c["sport"] + list(c["tyres"].values())}
    return {
        "parts": {str(i): p for i, p in sorted(parts.items()) if i in used},
        "cars": cars,
        "tyre_grip": tyre_grip,
        "formula": formula,
    }


def report(out):
    """Markdown table: car -> parts Sport fits and the tyres on offer."""
    parts = out["parts"]
    lines = ["| Auto | Sport | Pneumatiky |", "| --- | --- | --- |"]
    for key, car in out["cars"].items():
        sport = ", ".join(parts[str(i)]["name"] for i in car["sport"]) if car["applies"] else "– (originál díly ignoruje)"
        tyres = ", ".join(["sériové"] + [k for k in ("slick", "rain") if k in car["tyres"]]) if car["applies"] else "–"
        lines.append("| %s | %s | %s |" % (key, sport, tyres))
    return "\n".join(lines)


def main():
    args = [a for a in sys.argv[1:] if a != "--report"]
    if len(args) != 2:
        sys.exit(__doc__)
    fe, target = args
    exe_path = os.path.join(os.path.dirname(os.path.normpath(fe)), "Porsche.exe")
    sims_path = os.path.join(os.path.dirname(target), "..", "..", "GameData", "Simulation", "cars.json")
    sims = json.load(open(sims_path, encoding="utf-8"))
    out = convert(fe, exe_path, sims)
    os.makedirs(os.path.dirname(target) or ".", exist_ok=True)
    with open(target, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=1, ensure_ascii=False)
    print("%d parts, %d cars -> %s" % (len(out["parts"]), len(out["cars"]), target), file=sys.stderr)
    if "--report" in sys.argv:
        print(report(out))


if __name__ == "__main__":
    main()
