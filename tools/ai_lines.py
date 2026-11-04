"""Convert the opponents' racing lines (.lsp) and track keys (.key) to JSON.

Format: docs/formats/lsp.md. racer/work/<track>0.lsp and <track>1.lsp hold one
2D point (-x, z in glTF axes) for every SimD road slice; the JSON stores each
point as a lateral offset from the slice centre along the slice's "right"
vector, so the line also fits the 3D slices. <track>_forward.key and
_backwards.key are (slice, value) pairs ending with (100000, 600); the meaning
of the value is not known yet.

Needs <track>_road.json from track2gltf.py. Converts every track with a road file.

Usage:
    python3 tools/ai_lines.py sources/GameData/Track decomposed/GameData/Track
"""
import json
import os
import struct
import sys

from common import find_file

KEY_END = 100000  # slice index of the closing key


def read_lsp(path):
    data = open(path, "rb").read()
    version = struct.unpack_from("<i", data, 0)[0]
    count = (len(data) - 4) // 8
    return version, [struct.unpack_from("<2f", data, 4 + i * 8) for i in range(count)]


def read_key(path):
    data = open(path, "rb").read()
    version, count = struct.unpack_from("<2i", data, 0)
    pairs = [struct.unpack_from("<if", data, 8 + i * 8) for i in range(count)]
    return version, [[s, round(v, 3)] for s, v in pairs]


def line_offsets(points, slices):
    """Lateral offset of each point from its slice (m, + = right) and the largest error along the road."""
    offsets, along = [], 0.0
    for (a, b), s in zip(points, slices):
        p, r, f = s["position"], s["right"], s["forward"]
        dx, dz = -a - p[0], b - p[2]
        offsets.append(round(dx * r[0] + dz * r[2], 3))
        along = max(along, abs(dx * f[0] + dz * f[2]))
    return offsets, along


def convert(src, track, road, out_path):
    slices = road["slices"]
    lines, report = [], []
    for k in (0, 1):
        path = find_file(os.path.join(src, "racer", "work"), f"{track}{k}.lsp")
        version, points = read_lsp(path)
        if version != 1 or len(points) != len(slices):
            raise ValueError(f"{path}: version {version}, {len(points)} points for {len(slices)} slices")
        offsets, along = line_offsets(points, slices)
        lines.append(offsets)
        on_centre = sum(1 for o in offsets if abs(o) < 0.01)
        report.append(f"line{k} {min(offsets):+.1f}..{max(offsets):+.1f} m, {on_centre} on centre, along {along:.2f} m")
    keys = {}
    for direction in ("forward", "backwards"):
        path = find_file(src, f"{track}_{direction}.key")
        if path:
            version, pairs = read_key(path)
            if version != 1 or pairs[-1][0] != KEY_END:
                raise ValueError(f"{path}: version {version}, last key {pairs[-1]}")
            keys[direction] = pairs
            report.append(f"{direction} {len(pairs) - 1} keys")
    out = {
        "source": [f"racer/work/{track}0.lsp", f"racer/work/{track}1.lsp"],
        "slice_count": len(slices),
        "fields": "lines: lateral offset per road slice, m along the slice's right vector; "
                  "keys: [slice, value], last key (100000, 600) closes the list",
        "lines": lines,
        "keys": keys,
    }
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out, f, separators=(",", ":"))
    print(f"{track}: {len(slices)} slices, " + ", ".join(report))


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    src, dst = sys.argv[1], sys.argv[2]
    for track in sorted(os.listdir(dst)):
        road_path = os.path.join(dst, track, f"{track}_road.json")
        if not os.path.isfile(road_path) or not find_file(os.path.join(src, "racer", "work"), f"{track}0.lsp"):
            continue
        road = json.load(open(road_path, encoding="utf-8"))
        convert(src, track, road, os.path.join(dst, track, f"{track}_ai.json"))


if __name__ == "__main__":
    main()
