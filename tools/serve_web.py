#!/usr/bin/env python3
"""Serve a Godot web export locally, with the headers the browser needs.

Usage: python3 tools/serve_web.py [folder] [--port 8000] [--bind 127.0.0.1] [--https]

Binds to this machine only by default: the folder contains packs made from the
original game's data, which must not be published (D-039).

Godot's web export runs only in a secure context (HTTPS or localhost). For a test
on another computer in the local network use --bind 0.0.0.0 --https: the server
then uses a self-signed certificate for localhost and this machine's network
addresses, made with the openssl command in build/web-cert/ (ignored by git) and
remade when the addresses change. The browser warns about it once. --cert and
--key use your own certificate instead.
"""
import argparse
import functools
import socket
import ssl
import subprocess
import sys
import tempfile
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

CERT_DIR = Path(__file__).resolve().parent.parent / "build" / "web-cert"


class Handler(SimpleHTTPRequestHandler):
    extensions_map = {
        **SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".pck": "application/octet-stream",
        ".zip": "application/zip",
    }

    timeout = 30  # s; an idle connection must not keep its thread forever

    def setup(self):
        # The TLS handshake runs here, in this connection's own thread: done in accept() it would
        # stop the whole server whenever a browser opens a connection and leaves it waiting.
        if isinstance(self.request, ssl.SSLSocket):
            self.request.settimeout(self.timeout)
            self.request.do_handshake()
        super().setup()

    def end_headers(self):
        # Required by SharedArrayBuffer in thread-enabled exports.
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        # Files may be cached, but the browser must revalidate them on each visit.
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()


def local_addresses():
    """This machine's IPv4 addresses, loopback first."""
    found = ["127.0.0.1"]
    try:  # the address the default route leaves from; nothing is sent
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("10.255.255.255", 1))
            found.append(s.getsockname()[0])
    except OSError:
        pass
    try:
        found += socket.gethostbyname_ex(socket.gethostname())[2]
    except OSError:
        pass
    return list(dict.fromkeys(a for a in found if a))


def self_signed(addresses):
    """Certificate and key for localhost and the addresses, (re)made with openssl when needed."""
    cert, key, names = CERT_DIR / "cert.pem", CERT_DIR / "key.pem", CERT_DIR / "names.txt"
    wanted = "\n".join(["localhost", *addresses])
    if cert.is_file() and key.is_file() and names.is_file() and names.read_text() == wanted:
        return cert, key
    CERT_DIR.mkdir(parents=True, exist_ok=True)
    alt = ",".join(["DNS:localhost", *(f"IP:{a}" for a in addresses)])
    config = ("[req]\ndistinguished_name = dn\nx509_extensions = ext\nprompt = no\n"
              "[dn]\nCN = Stuttgart Speed local test\n"
              f"[ext]\nsubjectAltName = {alt}\nbasicConstraints = CA:FALSE\n"
              "keyUsage = digitalSignature, keyEncipherment\nextendedKeyUsage = serverAuth\n")
    with tempfile.NamedTemporaryFile("w", suffix=".cnf", delete=False) as f:
        f.write(config)
    try:
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-sha256",
                        "-days", "825", "-keyout", str(key), "-out", str(cert), "-config", f.name],
                       check=True, capture_output=True)
    except FileNotFoundError:
        raise SystemExit("--https needs the openssl command (or pass --cert and --key)")
    except subprocess.CalledProcessError as e:
        raise SystemExit(f"openssl failed: {e.stderr.decode(errors='replace').strip()}")
    finally:
        Path(f.name).unlink()
    names.write_text(wanted)
    print(f"Made a self-signed certificate in {CERT_DIR} for {alt}")
    return cert, key


def quiet_tls_errors(handle_error):
    """Failed handshakes as one line, not a traceback. A browser refuses the self-signed
    certificate on many connections before using the exception the user accepted, so that one is
    said once per address."""
    refused = set()

    def handle(request, client_address):
        error = sys.exc_info()[1]
        if isinstance(error, ssl.SSLError) and "CERTIFICATE_UNKNOWN" in str(error):
            if client_address[0] not in refused:
                refused.add(client_address[0])
                print(f"{client_address[0]} - the browser does not trust the self-signed certificate "
                      "(normal; it uses the exception the user accepted)")
        elif isinstance(error, (ssl.SSLError, ConnectionError, TimeoutError, socket.timeout)):
            print(f"{client_address[0]} - TLS: {error.__class__.__name__}: {error}")
        else:
            handle_error(request, client_address)
    return handle


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("folder", nargs="?", default="build/web", type=Path)
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument("--bind", default="127.0.0.1")
    parser.add_argument("--https", action="store_true", help="serve over HTTPS (self-signed unless --cert/--key)")
    parser.add_argument("--cert", type=Path, help="certificate (PEM) for --https")
    parser.add_argument("--key", type=Path, help="private key (PEM) for --https")
    args = parser.parse_args()
    if (args.cert is None) != (args.key is None):
        parser.error("--cert and --key go together")
    if args.cert is not None:
        args.https = True
    if not (args.folder / "index.html").is_file():
        parser.error(f"{args.folder} has no index.html - export the game first (docs/web.md)")
    handler = functools.partial(Handler, directory=str(args.folder))
    try:
        server = ThreadingHTTPServer((args.bind, args.port), handler)
    except OSError as e:
        if e.errno in (48, 98, 10048):  # EADDRINUSE on macOS, Linux, Windows
            raise SystemExit(f"Port {args.port} is taken, probably by another serve_web.py: stop it (Ctrl+C) "
                             f"or pass another --port")
        raise
    addresses = local_addresses() if args.bind in ("0.0.0.0", "") else [args.bind]
    scheme = "http"
    if args.https:
        cert, key = (args.cert, args.key) if args.cert is not None else self_signed(addresses)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cert, key)
        server.socket = context.wrap_socket(server.socket, server_side=True, do_handshake_on_connect=False)
        server.handle_error = quiet_tls_errors(server.handle_error)
        scheme = "https"
    for address in addresses:
        print(f"Serving {args.folder} at {scheme}://{address}:{args.port}")
    if scheme == "http" and args.bind != "127.0.0.1":
        print("Other computers need --https: Godot's web export runs only over HTTPS or on localhost")
    server.serve_forever()


if __name__ == "__main__":
    main()
