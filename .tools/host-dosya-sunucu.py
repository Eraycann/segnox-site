#!/usr/bin/env python3
"""Segnox VM testi - host dosya/sonuc sunucusu.

GET  /<dosya>  -> dizindeki dosyayi sunar
POST /sonuc    -> gelen govdeyi sonuc-geldi.log dosyasina yazar

Kullanim: python host-dosya-sunucu.py <dizin> <port>
"""
import http.server
import os
import socketserver
import sys

DIZIN = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.getcwd())
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8081


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=DIZIN, **kw)

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        veri = self.rfile.read(n)
        ad = self.path.split("?")[0].lstrip("/") or "sonuc"
        if not ad.endswith(".zip"):
            ad += ".zip"
        with open(os.path.join(DIZIN, ad), "wb") as f:
            f.write(veri)
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"ok":true}')

    def log_message(self, *a):
        pass


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    with Server(("0.0.0.0", PORT), Handler) as s:
        print(f"sunucu: http://0.0.0.0:{PORT}  dizin: {DIZIN}", flush=True)
        s.serve_forever()
