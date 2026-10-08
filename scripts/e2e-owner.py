#!/usr/bin/env python3
"""Cliente "dono" do E2E: anexa `tuios attach <sessao>` a um PTY e fica vivo, como o
TUIOS aberto no PC. Sem um dono anexado o celular (satelite) gravaria o foco da sessao
e o teste do foco separado nao provaria nada.

uso: e2e-owner.py <log> <cmd> [args...]
"""
import fcntl
import os
import pty
import struct
import sys
import termios

log_path = sys.argv[1]
cmd = sys.argv[2:]
pid, fd = pty.fork()
if pid == 0:
    os.environ["TERM"] = "xterm-256color"
    os.execvp(cmd[0], cmd)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
with open(log_path, "ab", buffering=0) as log:
    tail = b""
    while True:
        try:
            data = os.read(fd, 65536)
        except OSError:
            break
        if not data:
            break
        tail = (tail + data)[-4000:]
        # Responde a consulta de cursor (CSI 6n) como um terminal de verdade faria.
        if b"\x1b[6n" in data:
            os.write(fd, b"\x1b[1;1R")
    log.write(tail)
