#!/usr/bin/env python3
"""Upload the web build to the private R2 bucket behind the password Worker (D-041, docs/web.md).

Usage: python3 tools/deploy_web.py [folder] [--local --persist-to DIR]

Unchanged files are skipped, using a list of hashes kept next to the build (remote uploads only).
index.html goes last, so visitors never get a page whose files are not there yet.
Needs Node.js (npx) and `npx wrangler login`. With --local it fills wrangler's local simulator.
"""
import argparse
import hashlib
import json
import mimetypes
import shutil
import subprocess
import sys
from pathlib import Path

CONFIG = Path(__file__).parent / "web_host" / "wrangler.toml"
BUCKET = "stuttgart-speed-web"
WRANGLER = "wrangler@4"
MAX_SIZE = 315 * 1024 * 1024  # limit of `wrangler r2 object put`
TYPES = {".wasm": "application/wasm", ".pck": "application/octet-stream", ".js": "text/javascript"}


def file_hash(path):
    digest = hashlib.sha256()
    with path.open("rb") as f:
        while chunk := f.read(1 << 20):
            digest.update(chunk)
    return digest.hexdigest()


def upload(npx, key, path, where):
    content_type = TYPES.get(path.suffix) or mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    command = [npx, "--yes", WRANGLER, "r2", "object", "put", f"{BUCKET}/{key}", "--file", str(path),
               "--content-type", content_type, "--config", str(CONFIG), *where]
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"Upload of {key} failed:\n{result.stdout}\n{result.stderr}")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("folder", nargs="?", default="build/web", type=Path)
    parser.add_argument("--local", action="store_true", help="fill wrangler's local simulator instead")
    parser.add_argument("--persist-to", type=Path, help="state folder of the local simulator")
    args = parser.parse_args()
    if not (args.folder / "index.html").is_file():
        parser.error(f"{args.folder} has no index.html - export the game first (docs/web.md)")
    if not (args.folder / "data" / "manifest.json").is_file():
        parser.error(f"{args.folder}/data has no packs - run tools/pack_web.py first")
    npx = shutil.which("npx")
    if npx is None:
        sys.exit("npx not found - install Node.js")

    where = ["--local"] if args.local else ["--remote"]
    if args.local and args.persist_to:
        where += ["--persist-to", str(args.persist_to)]
    state_file = args.folder.parent / f"{args.folder.name}_deployed.json"
    done = json.loads(state_file.read_text()) if state_file.is_file() and not args.local else {}

    files = sorted((p for p in args.folder.rglob("*") if p.is_file()), key=lambda p: (p.name == "index.html", p))
    too_big = [p for p in files if p.stat().st_size > MAX_SIZE]
    if too_big:
        sys.exit(f"Over the 315 MB upload limit: {', '.join(map(str, too_big))}")

    uploaded = 0
    for number, path in enumerate(files, 1):
        key = path.relative_to(args.folder).as_posix()
        digest = file_hash(path)
        if done.get(key) == digest:
            continue
        print(f"[{number}/{len(files)}] {key} ({path.stat().st_size / 1e6:.1f} MB)", flush=True)
        upload(npx, key, path, where)
        uploaded += 1
        if not args.local:
            done[key] = digest
            state_file.write_text(json.dumps(done, indent=0))  # survives an interrupted upload
    print(f"Uploaded {uploaded} of {len(files)} files.")


if __name__ == "__main__":
    main()
