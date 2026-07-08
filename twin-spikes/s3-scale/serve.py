#!/usr/bin/env python3
"""Static server with the cross-origin isolation headers Godot web (threads) needs."""
import http.server
import sys


class COIHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        super().end_headers()


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8060
    http.server.ThreadingHTTPServer(("127.0.0.1", port), COIHandler).serve_forever()
