#!/usr/bin/env bash
# CPU and memory of a running systemd unit, from its cgroup counters (children included).
# Reading `ps` or `times` is not enough: most of the service's work is short-lived processes.
#
#   tools/measure-service.sh [SECONDS] [UNIT]     default: 30 s, joystickmanager.service
set -u
secs=${1:-30}
unit=${2:-joystickmanager.service}
case "$secs" in ''|*[!0-9]*|0) printf 'SECONDS must be a positive integer\n' >&2; exit 2;; esac
cg=$(systemctl show -p ControlGroup --value "$unit" 2>/dev/null)
[ -n "$cg" ] && [ -r "/sys/fs/cgroup$cg/cpu.stat" ] || { printf '%s is not running or its cgroup is not readable\n' "$unit" >&2; exit 1; }
base=/sys/fs/cgroup$cg
usage() { awk '/^usage_usec/{print $2}' "$base/cpu.stat"; }
a=$(usage); t0=$(date +%s.%N)
sleep "$secs"
b=$(usage); t1=$(date +%s.%N)
mem=$(( $(cat "$base/memory.current") / 1024 ))
pids=$(cat "$base/pids.current" 2>/dev/null || echo '?')
state=${JOYMANAGER_RUNTIME_DIR:-/run/joystickmanager}/state.json
n=unknown
[ -r "$state" ] && n=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["controllers"]))' "$state" 2>/dev/null || echo unknown)
python3 - "$a" "$b" "$t0" "$t1" "$mem" "$pids" "$n" "$unit" <<'PY'
import sys
a, b, t0, t1 = map(float, sys.argv[1:5]); mem, pids, n, unit = sys.argv[5:9]
wall = t1 - t0
print(f"{unit}: CPU {(b - a) / 1e6 / wall * 100:.2f}% of one core ({(b - a) / 1000:.0f} ms over {wall:.0f} s), "
      f"memory {int(mem) / 1024:.1f} MiB, {pids} process(es), {n} controller(s) connected")
PY
