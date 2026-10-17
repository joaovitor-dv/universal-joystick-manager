#!/usr/bin/env bash
# Collects what is needed to look at a problem or a test run, into ONE text file.
# The last three bytes of every Bluetooth address are masked (the vendor part stays, it helps).
# Read the file before you share it.
#
#   tools/collect-report.sh [OUTPUT_FILE]        default: ~/ujm-report-DATE.txt
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
runtime=${JOYMANAGER_RUNTIME_DIR:-/run/joystickmanager}

mask() { sed -E 's/(^|[^0-9A-Fa-f])([0-9A-Fa-f]{2})([:_-])([0-9A-Fa-f]{2})\3([0-9A-Fa-f]{2})\3[0-9A-Fa-f]{2}\3[0-9A-Fa-f]{2}\3[0-9A-Fa-f]{2}($|[^0-9A-Fa-f])/\1\2\3\4\3\5\3XX\3XX\3XX\6/g'; }
if [ "${1:-}" = "--self-test" ]; then  # used by tools/check.sh: addresses must be masked in every common spelling
    got=$(printf '%s\n' 'id 20:1C:3A:AB:CD:EF' 'dev_20_1C_3A_AB_CD_EF' 'battery_20:1c:3a:ab:cd:ef' 'hid 0005:057E:2009.0031' | mask | tr '\n' '|')
    [ "$got" = 'id 20:1C:3A:XX:XX:XX|dev_20_1C_3A_XX_XX_XX|battery_20:1c:3a:XX:XX:XX|hid 0005:057E:2009.0031|' ] && exit 0
    printf 'mask self-test failed: %s\n' "$got" >&2; exit 1
fi
out=${1:-$HOME/ujm-report-$(date +%Y%m%d-%H%M%S).txt}
section() { printf '\n===== %s =====\n' "$1"; }
run() { printf '$ %s\n' "$*"; "$@" 2>&1 || printf '(exit status %s)\n' "$?"; }

{
    printf 'UJM report, %s\n' "$(date '+%F %H:%M:%S %z')"
    section "versions"
    ( cd "$here" && git describe --tags --always --dirty 2>/dev/null | sed 's/^/source: /' )
    for f in /usr/local/bin/joystickmanager.sh /usr/bin/joystickmanager.sh; do
        [ -e "$f" ] && { printf 'installed script: %s (%s)\n' "$f" "$(sha256sum "$f" | cut -c1-12)"; }
    done
    [ -e "$here/joystickmanager.sh" ] && printf 'repository script: %s\n' "$(sha256sum "$here/joystickmanager.sh" | cut -c1-12)"
    run uname -r
    grep -E '^(PRETTY_NAME|ID)=' /etc/os-release
    run bash --version
    section "service"
    run systemctl is-active joystickmanager.service
    run systemctl show joystickmanager.service -p MainPID -p ActiveEnterTimestamp -p NRestarts -p Environment
    run systemctl is-active bluetooth.service joycond.service ujm-bridge.service
    section "service cost over 15 s"
    "$here/tools/measure-service.sh" 15 2>&1
    section "state.json"
    [ -r "$runtime/state.json" ] && cat "$runtime/state.json" || echo "(not found: is the service of this version running?)"
    section "slots.tsv"
    [ -r "$runtime/slots.tsv" ] && cat "$runtime/slots.tsv" || echo "(not found)"
    section "doctor"
    if [ -x "$here/joystickmanager-doctor" ]; then "$here/joystickmanager-doctor" 2>&1; else run joystickmanager-doctor; fi
    section "controller LEDs and batteries"
    for d in /sys/class/leds/*player* /sys/class/leds/*:blue:* /sys/class/power_supply/*controller*; do
        [ -e "$d" ] || continue
        printf '%s' "$(basename "$d")"
        for a in brightness max_brightness capacity status; do [ -r "$d/$a" ] && printf '  %s=%s' "$a" "$(cat "$d/$a")"; done
        printf '\n'
    done
    section "bluetooth adapter"
    bluetoothctl show 2>/dev/null | grep -E '^\s*(Powered|Discoverable|Pairable|Discovering|Name):' || echo "(bluetoothctl unavailable)"
    section "bridge on the system bus"
    busctl --no-pager introspect org.ujm.Manager1 /org/ujm/Manager1 2>&1 | head -5 || true
    section "service log, last 150 lines"
    journalctl -u joystickmanager.service -n 150 --no-pager 2>&1 | tail -150
    section "kernel messages about controllers, last 60 lines"
    { journalctl -k --no-pager 2>/dev/null || dmesg 2>/dev/null; } | grep -iE 'nintendo|hid-|joycon|xpad|playstation|sony|bluetooth.*(hid|input)' | tail -60
} 2>&1 | mask >"$out"

chmod 600 "$out"
printf 'Report written to %s (%s lines).\nBluetooth addresses are masked; read it before sharing.\n' "$out" "$(wc -l <"$out")"
