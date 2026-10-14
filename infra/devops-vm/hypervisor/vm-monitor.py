#!/usr/bin/env python3
"""Send one HMP command to the devops-vm QEMU monitor and print the reply.
Usage: sudo vm-monitor.py "savevm 02-keys-configured" """
import socket, sys
s = socket.socket(socket.AF_UNIX); s.connect("/workspace/pr5/vm/monitor.sock")
def until_prompt():
    buf = b""
    while not buf.endswith(b"(qemu) "):
        chunk = s.recv(4096)
        if not chunk: break
        buf += chunk
    return buf.decode(errors="replace")
until_prompt()
s.sendall((" ".join(sys.argv[1:]) + "\n").encode())
out = until_prompt().replace("\r", "")
lines = [l for l in out.split("\n") if not l.startswith("(qemu)") and "\x1b" not in l]
print("\n".join(lines).strip())
