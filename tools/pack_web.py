#!/usr/bin/env python3
"""Pack decomposed/ into zip packs for the web build of the game.

Usage: python3 tools/pack_web.py [decomposed] [build/web/data]

Packs follow the data folders, so the game derives a pack's name from the car or track
it needs (game/scripts/data_packs.gd, Main.race_packs). They hold data of the original
game: keep them out of git and off public hosts (D-039).

A track pack also gets the track's HDRI skies (assets/hdri/, game/scripts/sky_lighting.gd)
shrunk to SKY_WIDTH, as sky/<entry>_<day|night>.hdr: the full 20-28 MB skies were too big
for the browser, and the procedural sky lit the tracks quite differently (D-043).
"""
import argparse
import json
import math
import re
import sys
import zipfile
from pathlib import Path, PurePosixPath

# Written by the conversion tools for checking, never read by the game.
SKIPPED_SUFFIXES = ("_check.json", "_topology.json")
# Zip paths are relative to res://, where OriginalAssets finds them (stuttgart/data_root.web).
MOUNT = PurePosixPath("decomposed")
GAME = Path(__file__).resolve().parent.parent / "game"
REPO = GAME.parent
HDRI = REPO / "assets/hdri"
HDRI_CATALOG = REPO / "data/hdri.json"
SKY_WIDTH = 1024  # px; the sun is found on a 256 px copy anyway
TIMES = ("day", "night")
SFX_FOLDERS = ("GameData/Sounds/SND_coll", "GameData/Sounds/track/waterfall huge_129")


def files_in(folder, suffixes, recursive=False):
    found = folder.rglob("*") if recursive else folder.iterdir()
    return [f for f in sorted(found)
            if f.is_file() and f.suffix.lower() in suffixes and not f.name.endswith(SKIPPED_SUFFIXES)]


def core_files(root):
    files = files_in(root / "GameData/Simulation", {".json"}, recursive=True)
    files += files_in(root / "GameData/Render", {".json", ".png"}, recursive=True)
    files += files_in(root / "FEData/Data", {".json"})
    files += [f for f in sorted((root / "FEData/TrackArt").rglob("000_*.png"))]
    return files


def night_tracks(root):
    """GameData/Track/tracks.json for the core pack: the night flag of every track (<track>_lights.json,
    tools/track2gltf.py), read by the menu before the track's pack is loaded (Main.is_night_track)."""
    index = {}
    for lights in sorted((root / "GameData/Track").glob("*/*_lights.json")):
        if lights.name != f"{lights.parent.name}_lights.json":
            continue
        data = json.loads(lights.read_text(encoding="utf-8"))
        if "night" not in data:
            sys.exit(f"{lights} has no night flag - convert the track again (tools/track2gltf.py)")
        index[lights.parent.name] = {"night": data["night"]}
    name = (MOUNT / "GameData/Track/tracks.json").as_posix()
    return {name: (json.dumps(index, indent=1) + "\n").encode("utf-8")}


def project_files():
    """Our own files the game reads raw (res://...); an export holds only their imported form."""
    files = []
    for pattern in ("ui/icons/*.svg", "ui/fonts/*.ttf", "assets/particles/**/*.png"):
        files += sorted(GAME.glob(pattern))
    return files


def model_packs(root, kind, prefix):
    """One pack per folder holding <name>/<name>.gltf; subfolders (advanced/, original/ ...) stay out,
    except a track's env/ (light decals on the cars, <track>_decals.json) and the textures of its
    original sky (Sky/<Track>/ named in <track>_sky.json, tools/sky.py, D-045)."""
    packs = {}
    for folder in sorted((root / "GameData" / kind).iterdir()):
        if (folder / f"{folder.name}.gltf").is_file():
            packs[prefix + folder.name] = files_in(folder, {".gltf", ".bin", ".png", ".json"})
            if (folder / "env").is_dir():
                packs[prefix + folder.name] += files_in(folder / "env", {".png"})
            packs[prefix + folder.name] += sky_files(root, folder)
    return packs


def sky_files(root, folder):
    """The PNGs of the original sky the track's <track>_sky.json uses; exits when one is missing."""
    sky_json = folder / f"{folder.name}_sky.json"
    if not sky_json.is_file():
        return []
    sky = json.loads(sky_json.read_text(encoding="utf-8"))
    files = []
    for name, file in sorted(sky.get("textures", {}).items()):
        path = root / sky["folder"] / file
        if not path.is_file():
            sys.exit(f"{sky_json.name} needs {sky['folder']}/{file}, which is missing")
        files.append(path)
    return files


def sound_packs(root):
    packs = {"sfx": []}
    for folder in SFX_FOLDERS:
        packs["sfx"] += files_in(root / folder, {".wav", ".json"}, recursive=True)
    for folder in sorted((root / "GameData/Sounds").glob("sd*")):
        if folder.is_dir() and not folder.name.endswith("16"):
            packs["engine-" + folder.name] = files_in(folder, {".wav", ".json"}, recursive=True)
    return packs


def sky_entry(track):
    """Track name -> sky entry shared by its variants (monaco3 -> monaco), as sky_lighting.gd."""
    return track.rstrip("0123456789") or track


def sky_source(hdri, entry, time):
    """The HDRI the desktop game uses for this entry and time (sky_lighting.gd hdri_path), or None."""
    own = hdri / f"{entry}_{time}.hdr"
    if own.is_file():
        return own
    if HDRI_CATALOG.is_file():
        catalog = json.loads(HDRI_CATALOG.read_text(encoding="utf-8")).get("tracks", {})
        sky_id = catalog.get(entry, {}).get(time, "")
        for res in ("4k", "2k", "8k", "1k"):
            if sky_id and (hdri / f"{sky_id}_{res}.hdr").is_file():
                return hdri / f"{sky_id}_{res}.hdr"
    return None


def read_hdr(path):
    """Radiance HDR (flat or run-length encoded RGBE) -> (width, height, [scanline bytes RGBE ...])."""
    data = path.read_bytes()
    pos = 0
    while True:  # header lines up to an empty one, then the size line
        end = data.index(b"\n", pos)
        line = data[pos:end]
        pos = end + 1
        if not line.strip():
            break
    end = data.index(b"\n", pos)
    size = re.fullmatch(rb"-Y (\d+) \+X (\d+)", data[pos:end].strip())
    if not size:
        sys.exit(f"{path}: unsupported HDR orientation {data[pos:end]!r}")
    height, width = int(size[1]), int(size[2])
    pos = end + 1
    rows = []
    for _ in range(height):
        if 8 <= width < 32768 and data[pos] == 2 and data[pos + 1] == 2 and not data[pos + 2] & 0x80:
            pos += 4
            planes = []
            for _channel in range(4):
                plane = bytearray()
                while len(plane) < width:
                    count = data[pos]
                    if count > 128:
                        plane += bytes([data[pos + 1]]) * (count - 128)
                        pos += 2
                    else:
                        plane += data[pos + 1:pos + 1 + count]
                        pos += 1 + count
                planes.append(plane)
            row = bytearray(width * 4)
            for channel, plane in enumerate(planes):
                row[channel::4] = plane
            rows.append(bytes(row))
        else:
            rows.append(data[pos:pos + width * 4])
            pos += width * 4
    return width, height, rows


def shrink_hdr(path, target_width):
    """The HDRI averaged down to target_width (whole blocks of pixels), as flat RGBE HDR bytes."""
    width, height, rows = read_hdr(path)
    f = max(1, width // target_width)
    out_w, out_h = width // f, height // f
    scale = [math.ldexp(1.0, e - 136) if e else 0.0 for e in range(256)]  # RGBE: (m + 0.5) * 2^(e-136)
    out = bytearray()
    for oy in range(out_h):
        sums = [[0.0] * out_w for _ in range(3)]
        for row in rows[oy * f:(oy + 1) * f]:
            exps = [scale[e] for e in row[3::4]]
            for channel in range(3):
                values = [m * s for m, s in zip(row[channel::4], exps)]
                target = sums[channel]
                for ox in range(out_w):
                    target[ox] += sum(values[ox * f:(ox + 1) * f])
        for ox in range(out_w):
            r, g, b = (sums[c][ox] / (f * f) for c in range(3))
            v = max(r, g, b)
            if v < 1e-32:
                out += b"\0\0\0\0"
                continue
            mantissa, exponent = math.frexp(v)
            k = mantissa * 256.0 / v
            out += bytes((min(255, int(r * k)), min(255, int(g * k)), min(255, int(b * k)), exponent + 128))
    header = f"#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y {out_h} +X {out_w}\n".encode()
    return header + bytes(out)


def track_skies(hdri, tracks, width):
    """Pack name -> {zip path: HDR bytes}: each track pack gets its entry's day and night sky."""
    shrunk = {}
    skies = {}
    for track in tracks:
        entry = sky_entry(track)
        for time in TIMES:
            source = sky_source(hdri, entry, time)
            if source is None:
                continue
            if source not in shrunk:
                print(f"sky {source.name} -> {width} px")
                shrunk[source] = shrink_hdr(source, width)
            skies.setdefault("track-" + track, {})[f"{MOUNT}/sky/{entry}_{time}.hdr"] = shrunk[source]
    return skies


def check_gltf_files(name, files):
    """Every file a glTF refers to must be in its pack."""
    present = set(files)
    for gltf in (f for f in files if f.suffix == ".gltf"):
        data = json.loads(gltf.read_text(encoding="utf-8"))
        for entry in data.get("images", []) + data.get("buffers", []):
            uri = entry.get("uri", "")
            if uri and not uri.startswith("data:") and (gltf.parent / uri) not in present:
                sys.exit(f"{name}: {gltf.name} needs {uri}, which is not in the pack")


def write_pack(path, root, files, extra=(), generated=None):
    with zipfile.ZipFile(path, "w", zipfile.ZIP_STORED) as archive:
        for file in files:
            archive.write(file, (MOUNT / file.relative_to(root).as_posix()).as_posix())
        for file in extra:
            archive.write(file, file.relative_to(GAME).as_posix())
        for name, data in (generated or {}).items():  # flat RGBE skies shrink to about a third
            archive.writestr(name, data, compress_type=zipfile.ZIP_DEFLATED)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("decomposed", nargs="?", default="decomposed", type=Path)
    parser.add_argument("out", nargs="?", default="build/web/data", type=Path)
    parser.add_argument("--hdri", default=HDRI, type=Path, help="folder with the HDRI skies (default assets/hdri)")
    args = parser.parse_args()
    if not (args.decomposed / "GameData").is_dir():
        sys.exit(f"{args.decomposed} has no GameData - run tools/build_data.py first")

    packs = {"core": core_files(args.decomposed)}
    packs.update(model_packs(args.decomposed, "CarModel", "car-"))
    packs.update(model_packs(args.decomposed, "Track", "track-"))
    packs.update(sound_packs(args.decomposed))
    tracks = [name.removeprefix("track-") for name in packs if name.startswith("track-")]
    skies = track_skies(args.hdri, tracks, SKY_WIDTH)
    skies["core"] = {**skies.get("core", {}), **night_tracks(args.decomposed)}
    if not skies:
        print(f"no HDRI skies in {args.hdri} (tools/fetch_hdri.py): the web build keeps the procedural sky")

    args.out.mkdir(parents=True, exist_ok=True)
    manifest = {"version": 1, "packs": {}}
    for name, files in packs.items():
        check_gltf_files(name, files)
        path = args.out / f"{name}.zip"
        write_pack(path, args.decomposed, files, project_files() if name == "core" else (), skies.get(name))
        manifest["packs"][name] = {"size": path.stat().st_size}
    (args.out / "manifest.json").write_text(json.dumps(manifest, indent=1) + "\n", encoding="utf-8")

    total = sum(p["size"] for p in manifest["packs"].values())
    print(f"{len(packs)} packs, {total / 1048576:.0f} MB in {args.out}")


if __name__ == "__main__":
    main()
