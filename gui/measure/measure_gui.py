#!/usr/bin/env python3
"""Start a GUI command, wait for it to be ready, then sample the whole process tree while idle.

usage: measure_gui.py [--idle SECONDS] -- COMMAND...
Prints startup time, process count, RSS and PSS (sum over the tree) and idle CPU.
"""
import argparse
import os
import subprocess
import sys
import time

import psutil


def tree(p):
    try:
        return [p] + p.children(recursive=True)
    except psutil.NoSuchProcess:
        return []


def mem(procs):
    rss = pss = 0
    for q in procs:
        try:
            rss += q.memory_info().rss
            pss += q.memory_full_info().pss
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass
    return rss, pss


def cpu_seconds(procs):
    total = 0.0
    for q in procs:
        try:
            t = q.cpu_times()
            total += t.user + t.system
        except psutil.NoSuchProcess:
            pass
    return total


ap = argparse.ArgumentParser()
ap.add_argument("--idle", type=float, default=15)
ap.add_argument("--settle", type=float, default=3)
ap.add_argument("--no-ready", action="store_true", help="the command prints no READY line: just wait --settle")
ap.add_argument("cmd", nargs=argparse.REMAINDER)
a = ap.parse_args()
cmd = a.cmd[1:] if a.cmd and a.cmd[0] == "--" else a.cmd

t0 = time.monotonic()
proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
ready_ms = None
if not a.no_ready:
    for line in proc.stdout:
        if line.startswith("READY"):
            ready_ms = (time.monotonic() - t0) * 1000
            print("app says:", line.strip())
            break
p = psutil.Process(proc.pid)
time.sleep(a.settle)
procs = tree(p)
cpu0, w0 = cpu_seconds(procs), time.monotonic()
time.sleep(a.idle)
procs = tree(p)
cpu1, w1 = cpu_seconds(procs), time.monotonic()
rss, pss = mem(procs)
print(f"processes       : {len(procs)}")
print("start to ready  : " + (f"{ready_ms:.0f} ms (wall, includes interpreter start)" if ready_ms else "not measured"))
print(f"memory RSS      : {rss / 2**20:.0f} MiB (counts shared pages once per process)")
print(f"memory PSS      : {pss / 2**20:.0f} MiB (shared pages divided between processes)")
print(f"idle CPU        : {(cpu1 - cpu0) / (w1 - w0) * 100:.1f}% of one core over {w1 - w0:.0f} s")
for q in procs:
    try:
        print(f"   {q.pid:>7} {q.name():<22} pss {q.memory_full_info().pss / 2**20:6.0f} MiB")
    except psutil.NoSuchProcess:
        pass
for q in reversed(procs):
    try:
        q.terminate()
    except psutil.NoSuchProcess:
        pass
try:
    proc.wait(5)
except subprocess.TimeoutExpired:
    proc.kill()
