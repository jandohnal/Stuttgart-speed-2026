#!/usr/bin/env python3
"""Folder for uploading the web build by hand in the Cloudflare dashboard (D-041, docs/web.md).

Usage: python3 tools/package_web.py [build/web] [--out build/cloudflare]

The folder holds bucket/ (files for R2, same layout as the build), worker.js and NAVOD.md
with the steps. It contains packs made from the original game's data: never publish it.
"""
import argparse
import shutil
import sys
from pathlib import Path

HOST = Path(__file__).parent / "web_host"


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("folder", nargs="?", default="build/web", type=Path)
    parser.add_argument("--out", default="build/cloudflare", type=Path)
    args = parser.parse_args()
    if not (args.folder / "index.html").is_file():
        parser.error(f"{args.folder} has no index.html - export the game first (docs/web.md)")
    if not (args.folder / "data" / "manifest.json").is_file():
        parser.error(f"{args.folder}/data has no packs - run tools/pack_web.py first")
    if args.out.exists():
        if not (args.out / "NAVOD.md").is_file():
            sys.exit(f"{args.out} exists and is not a package from this tool - choose another --out")
        shutil.rmtree(args.out)

    shutil.copytree(args.folder, args.out / "bucket")
    shutil.copy2(HOST / "worker.js", args.out / "worker.js")
    shutil.copy2(HOST / "NAVOD.md", args.out / "NAVOD.md")

    files = [p for p in (args.out / "bucket").rglob("*") if p.is_file()]
    in_data = sum(1 for p in files if p.parent.name == "data")
    size = sum(p.stat().st_size for p in files)
    print(f"{args.out}: {len(files) - in_data} files in bucket/, {in_data} in bucket/data/, {size / 1e6:.0f} MB")
    print(f"Steps: {args.out / 'NAVOD.md'}")


if __name__ == "__main__":
    main()
