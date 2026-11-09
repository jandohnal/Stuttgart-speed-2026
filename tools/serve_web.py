#!/usr/bin/env python3
"""Serve a Godot web export locally, with the headers the browser needs.

Usage: python3 tools/serve_web.py [folder] [--port 8000] [--bind 127.0.0.1]

Binds to this machine only by default: the folder contains packs made from the
original game's data, which must not be published (D-039).
"""
import argparse
import functools
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class Handler(SimpleHTTPRequestHandler):
    extensions_map = {
        **SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".pck": "application/octet-stream",
        ".zip": "application/zip",
    }

    def end_headers(self):
        # Required by SharedArrayBuffer in thread-enabled exports.
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        # Files may be cached, but the browser must revalidate them on each visit.
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("folder", nargs="?", default="build/web", type=Path)
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument("--bind", default="127.0.0.1")
    args = parser.parse_args()
    if not (args.folder / "index.html").is_file():
        parser.error(f"{args.folder} has no index.html - export the game first (docs/web.md)")
    handler = functools.partial(Handler, directory=str(args.folder))
    print(f"Serving {args.folder} at http://{args.bind}:{args.port}")
    ThreadingHTTPServer((args.bind, args.port), handler).serve_forever()


if __name__ == "__main__":
    main()
