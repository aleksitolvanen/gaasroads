#!/usr/bin/env python3
"""Serve Builds/ locally for testing the web export.

The threaded build needs SharedArrayBuffer, which browsers only enable on
cross-origin-isolated pages - so a plain `python -m http.server` won't work.

Usage: python serve_web.py [port]
"""
import sys
from functools import partial
from http.server import HTTPServer, SimpleHTTPRequestHandler


class Handler(SimpleHTTPRequestHandler):
    extensions_map = SimpleHTTPRequestHandler.extensions_map | {".wasm": "application/wasm"}

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        super().end_headers()


port = int(sys.argv[1]) if len(sys.argv) > 1 else 8060
httpd = HTTPServer(("127.0.0.1", port), partial(Handler, directory="Builds"))
print(f"Serving Builds/ at http://127.0.0.1:{port}/GaasRoads.html")
httpd.serve_forever()
