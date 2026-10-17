#!/usr/bin/env python3
"""A stand-in for the shell service's command channel. Logs every request to $RUNTIME/service.log.

Mode file $RUNTIME/service.mode: "silent" never answers, "reject" answers with an error."""
import os
import sys

rt = os.environ["JOYMANAGER_RUNTIME_DIR"]
fifo, ack_dir, log = os.path.join(rt, "command.fifo"), os.path.join(rt, "ack"), os.path.join(rt, "service.log")
os.mkfifo(fifo, 0o600)
fd = os.open(fifo, os.O_RDWR)
os.makedirs(ack_dir, exist_ok=True)
print("READY", flush=True)
buf = b""
while True:
    chunk = os.read(fd, 4096)
    if not chunk:
        break
    buf += chunk
    while b"\n" in buf:
        raw, buf = buf.split(b"\n", 1)
        parts = raw.decode("utf-8").split("\t")
        if parts[0] != "REQ" or len(parts) < 3:
            continue
        reqid, command, args = parts[1], parts[2], parts[3:]
        with open(log, "a", encoding="utf-8") as fh:
            fh.write("\t".join([command, *args]) + "\n")
        mode = ""
        try:
            with open(os.path.join(rt, "service.mode"), encoding="utf-8") as fh:
                mode = fh.read().strip()
        except OSError:
            pass
        if mode == "silent":
            continue
        tmp = os.path.join(ack_dir, reqid + ".tmp")
        with open(tmp, "w", encoding="utf-8") as fh:
            fh.write("error\tnope, said the service\n" if mode == "reject" else "ok\n")
        os.replace(tmp, os.path.join(ack_dir, reqid))
