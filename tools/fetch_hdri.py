"""Download CC0 sky HDRIs from Poly Haven listed in data/hdri.json.

Usage (from the repo root):
    python3 tools/fetch_hdri.py                 # 4k .hdr for all tracks
    python3 tools/fetch_hdri.py --res 2k        # smaller (lighting only)
    python3 tools/fetch_hdri.py --track farmland --track monaco
    python3 tools/fetch_hdri.py --alternatives  # also the alternative skies

Files go to assets/hdri/<id>_<res>.hdr (ignored by git; re-download any time).
Poly Haven assets are CC0, see https://polyhaven.com/license
"""
import argparse
import json
import os
import sys
import urllib.request

API = "https://api.polyhaven.com/files/{}"
UA = {"User-Agent": "stuttgart-speed-fetch-hdri/1.0"}


def get_json(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
        return json.load(r)


def download(url, path, size):
    if os.path.exists(path) and os.path.getsize(path) == size:
        print(f"  ok (cached) {os.path.basename(path)}")
        return
    tmp = path + ".part"
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=600) as r, open(tmp, "wb") as f:
        done = 0
        while chunk := r.read(1 << 20):
            f.write(chunk)
            done += len(chunk)
            print(f"\r  {os.path.basename(path)} {done / 1e6:.1f}/{size / 1e6:.1f} MB", end="", flush=True)
    os.replace(tmp, path)
    print()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--res", default="4k", help="1k, 2k, 4k, 8k (default 4k)")
    ap.add_argument("--fmt", default="hdr", choices=["hdr", "exr"])
    ap.add_argument("--track", action="append", help="only these tracks (repeatable)")
    ap.add_argument("--alternatives", action="store_true", help="also download alternative skies")
    ap.add_argument("--out", default="assets/hdri")
    a = ap.parse_args()

    cfg = json.load(open("data/hdri.json"))
    ids = []
    for name, t in cfg["tracks"].items():
        if not a.track or name in a.track:
            ids += [t["day"], t["night"]]
    if a.alternatives:
        for group in cfg["alternatives"].values():
            ids += group
    ids = list(dict.fromkeys(ids))

    os.makedirs(a.out, exist_ok=True)
    failed = []
    for i, asset in enumerate(ids, 1):
        print(f"[{i}/{len(ids)}] {asset}")
        try:
            f = get_json(API.format(asset))["hdri"][a.res][a.fmt]
            download(f["url"], os.path.join(a.out, f"{asset}_{a.res}.{a.fmt}"), f["size"])
        except Exception as e:  # keep going, report at the end
            print(f"  FAILED: {e}")
            failed.append(asset)
    print(f"done, {len(ids) - len(failed)} ok, {len(failed)} failed {failed or ''}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
