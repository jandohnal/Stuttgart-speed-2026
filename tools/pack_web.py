#!/usr/bin/env python3
"""Pack decomposed/ into zip packs for the web build of the game.

Usage: python3 tools/pack_web.py [decomposed] [build/web/data]

Packs follow the data folders, so the game derives a pack's name from the car or track
it needs (game/scripts/data_packs.gd, Main.race_packs). They hold data of the original
game: keep them out of git and off public hosts (D-039).
"""
import argparse
import json
import sys
import zipfile
from pathlib import Path, PurePosixPath

# Written by the conversion tools for checking, never read by the game.
SKIPPED_SUFFIXES = ("_check.json", "_topology.json")
# Zip paths are relative to res://, where OriginalAssets finds them (stuttgart/data_root.web).
MOUNT = PurePosixPath("decomposed")
GAME = Path(__file__).resolve().parent.parent / "game"
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


def project_files():
    """Our own files the game reads raw (res://...); an export holds only their imported form."""
    files = []
    for pattern in ("ui/icons/*.svg", "ui/fonts/*.ttf", "assets/particles/**/*.png"):
        files += sorted(GAME.glob(pattern))
    return files


def model_packs(root, kind, prefix):
    """One pack per folder holding <name>/<name>.gltf; subfolders (advanced/, original/ ...) stay out."""
    packs = {}
    for folder in sorted((root / "GameData" / kind).iterdir()):
        if (folder / f"{folder.name}.gltf").is_file():
            packs[prefix + folder.name] = files_in(folder, {".gltf", ".bin", ".png", ".json"})
    return packs


def sound_packs(root):
    packs = {"sfx": []}
    for folder in SFX_FOLDERS:
        packs["sfx"] += files_in(root / folder, {".wav", ".json"}, recursive=True)
    for folder in sorted((root / "GameData/Sounds").glob("sd*")):
        if folder.is_dir() and not folder.name.endswith("16"):
            packs["engine-" + folder.name] = files_in(folder, {".wav", ".json"}, recursive=True)
    return packs


def check_gltf_files(name, files):
    """Every file a glTF refers to must be in its pack."""
    present = set(files)
    for gltf in (f for f in files if f.suffix == ".gltf"):
        data = json.loads(gltf.read_text(encoding="utf-8"))
        for entry in data.get("images", []) + data.get("buffers", []):
            uri = entry.get("uri", "")
            if uri and not uri.startswith("data:") and (gltf.parent / uri) not in present:
                sys.exit(f"{name}: {gltf.name} needs {uri}, which is not in the pack")


def write_pack(path, root, files, extra=()):
    with zipfile.ZipFile(path, "w", zipfile.ZIP_STORED) as archive:
        for file in files:
            archive.write(file, (MOUNT / file.relative_to(root).as_posix()).as_posix())
        for file in extra:
            archive.write(file, file.relative_to(GAME).as_posix())


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("decomposed", nargs="?", default="decomposed", type=Path)
    parser.add_argument("out", nargs="?", default="build/web/data", type=Path)
    args = parser.parse_args()
    if not (args.decomposed / "GameData").is_dir():
        sys.exit(f"{args.decomposed} has no GameData - run tools/build_data.py first")

    packs = {"core": core_files(args.decomposed)}
    packs.update(model_packs(args.decomposed, "CarModel", "car-"))
    packs.update(model_packs(args.decomposed, "Track", "track-"))
    packs.update(sound_packs(args.decomposed))

    args.out.mkdir(parents=True, exist_ok=True)
    manifest = {"version": 1, "packs": {}}
    for name, files in packs.items():
        check_gltf_files(name, files)
        path = args.out / f"{name}.zip"
        write_pack(path, args.decomposed, files, project_files() if name == "core" else ())
        manifest["packs"][name] = {"size": path.stat().st_size}
    (args.out / "manifest.json").write_text(json.dumps(manifest, indent=1) + "\n", encoding="utf-8")

    total = sum(p["size"] for p in manifest["packs"].values())
    print(f"{len(packs)} packs, {total / 1048576:.0f} MB in {args.out}")


if __name__ == "__main__":
    main()
