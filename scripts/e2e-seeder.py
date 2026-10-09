#!/usr/bin/env python3
"""Semeador do E2E: o hold de aprovacao do fork dura no maximo 300 s, entao cada teste pede o
seu na hora. Uso: e2e-seeder.py PORTA caminho/e2e-server.sh
  GET /health
  POST /seed/approval/<tag>   -> e2e-server.sh seed-approval <tag>
  POST /seed/ask/<tag>        -> e2e-server.sh seed-ask <tag>
  POST /seed/chatline/<tag>   -> e2e-server.sh seed-chatline <tag>
Escuta so em loopback (o simulador do macOS enxerga o loopback do runner)."""
import re
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT, SCRIPT = int(sys.argv[1]), sys.argv[2]


class H(BaseHTTPRequestHandler):
    def _send(self, code, body):
        data = body.encode()
        self.send_response(code)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        self._send(200 if self.path == "/health" else 404, "ok\n")

    def do_POST(self):
        m = re.fullmatch(r"/seed/(approval|ask|chatline)/([A-Za-z0-9_-]{1,32})", self.path)
        if not m:
            return self._send(404, "rota?\n")
        r = subprocess.run([SCRIPT, "seed-" + m.group(1), m.group(2)], capture_output=True, text=True, timeout=90)
        self._send(200 if r.returncode == 0 else 500, r.stderr[-800:])

    def log_message(self, *a):
        pass


HTTPServer(("127.0.0.1", PORT), H).serve_forever()
