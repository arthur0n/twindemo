#!/usr/bin/env python3
"""Static server with the cross-origin isolation headers Godot web (threads) needs.

  python3 serve.py <dir> [port]

Serves <dir> with COOP:same-origin + COEP:require-corp so a threads build reaches
crossOriginIsolated (SharedArrayBuffer). A no-threads build ignores the headers and
serves fine either way — this is the COI-correct server the recipe would promote.
"""
import http.server
import os
import sys


class COIHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        super().end_headers()


if __name__ == "__main__":
    directory = sys.argv[1] if len(sys.argv) > 1 else "."
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 8070
    os.chdir(directory)
    http.server.ThreadingHTTPServer(("127.0.0.1", port), COIHandler).serve_forever()
