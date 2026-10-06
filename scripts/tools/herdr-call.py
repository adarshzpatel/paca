#!/usr/bin/env python3
"""Send one herdr socket API request and print the reply.

    scripts/tools/herdr-call.py [--session NAME] METHOD ['{"json":"params"}']

Defaults to the paca-test session so experiments never touch your real one.
"""
import json, os, socket, sys

args = sys.argv[1:]
session = "paca-test"
if args[:1] == ["--session"]:
    session, args = args[1], args[2:]
method = args[0]
params = json.loads(args[1]) if len(args) > 1 else {}
base = os.path.expanduser("~/.config/herdr")
path = f"{base}/herdr.sock" if session == "default" else f"{base}/sessions/{session}/herdr.sock"

s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(path)
s.sendall((json.dumps({"id": "cli", "method": method, "params": params}) + "\n").encode())
buf = b""
while not buf.endswith(b"\n"):
    chunk = s.recv(65536)
    if not chunk:
        break
    buf += chunk
print(json.dumps(json.loads(buf), indent=2))
