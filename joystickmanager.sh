#!/usr/bin/env bash
set -u

runtime_dir=${JOYMANAGER_RUNTIME_DIR:-/run/joystickmanager}
sys_input=${JOYMANAGER_SYS_INPUT:-/sys/class/input}
sys_leds=${JOYMANAGER_SYS_LEDS:-/sys/class/leds}
sys_power=${JOYMANAGER_SYS_POWER:-/sys/class/power_supply}
# Each LED write on a Pro Controller/Joy-Con is an HID subcommand. Rewriting
# everything every 2 s cycle overloads the controller ("exceeded max attempts" errors and
# timeout drops). LEDs are only re-applied every JOYMANAGER_LED_REFRESH
# seconds (0 = every cycle, the old behavior; off = once per connected device, then never
# again); real changes are written immediately. Anything else falls back to 10.
led_refresh=${JOYMANAGER_LED_REFRESH:-10}
case "$led_refresh" in off) ;; ''|*[!0-9]*) led_refresh=10;; esac
slots_file="$runtime_dir/slots.tsv"
max_players=8
idle_timeout=${JOYMANAGER_IDLE_TIMEOUT:-300}
# 0 turns the idle power-off off; anything else must be a whole number of seconds.
case "$idle_timeout" in ''|*[!0-9]*) idle_timeout=300;; esac
# Settings changed at run time (command channel, docs/command-channel.md) are kept in a small file and
# win over the unit's Environment= after a restart.
state_dir=${JOYMANAGER_STATE_DIR:-/var/lib/joystickmanager}
settings_file="$state_dir/settings"
cmd_fifo="$runtime_dir/command.fifo"
ack_dir="$runtime_dir/ack"
cmd_fd_ok=0
valid_idle_timeout() { [[ $1 =~ ^[0-9]+$ ]] && { [ "$1" -eq 0 ] || { [ "$1" -ge 60 ] && [ "$1" -le 86400 ]; }; }; }
load_settings() {
    local k v
    [ -r "$settings_file" ] || return 0
    while IFS='=' read -r k v; do
        case "$k" in idle_timeout) if valid_idle_timeout "$v" 2>/dev/null; then idle_timeout=$v; fi;; esac
    done <"$settings_file"
    return 0
}
load_settings
# "experimental" and "planned" controllers in controllers.tsv are only used with JOYMANAGER_EXPERIMENTAL=1.
experimental=${JOYMANAGER_EXPERIMENTAL:-0}
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)
# Pro Controller LED helper: JOYMANAGER_SWITCHPRO_HELPER, or next to wherever this script is
# installed (install.sh: /usr/local/libexec; packages: /usr/lib/joystickmanager or /usr/libexec).
switchpro_helper=${JOYMANAGER_SWITCHPRO_HELPER:-}
if [ -z "$switchpro_helper" ]; then
    for f in "$script_dir/../libexec/joystickmanager-switchpro-leds" "$script_dir/../lib/joystickmanager/switchpro-leds"; do
        [ -x "$f" ] && { switchpro_helper=$f; break; }
    done
fi
mkdir -p "$runtime_dir"
touch "$slots_file"

write_led() { local p=$1 v=$2; [ -e "$p" ] && printf '%s\n' "$v" >"$p" 2>/dev/null || true; }
# First line of a sysfs attribute (all of them are one-liners). "read" is a builtin: no cat process.
read_file() { local l=''; [ -r "$1" ] && { IFS= read -r l <"$1" || true; printf '%s\n' "$l"; }; return 0; }

# Path to the profile table. If JOYMANAGER_PROFILES is set it is the only
# candidate; without a table, register_event uses the fixed name list (legacy).
profiles_path() {
    local f
    if [ -n "${JOYMANAGER_PROFILES:-}" ]; then
        [ -r "$JOYMANAGER_PROFILES" ] && { printf '%s\n' "$JOYMANAGER_PROFILES"; return 0; }
        return 1
    fi
    for f in /usr/local/share/joystickmanager/controllers.tsv /usr/share/joystickmanager/controllers.tsv "$script_dir/controllers.tsv"; do
        [ -r "$f" ] && { printf '%s\n' "$f"; return 0; }
    done
    return 1
}

has_js() { compgen -G "$sys_input/$1/device/js*" >/dev/null; }

# profile_for_event EVENT -> prints "family<TAB>state" for the first matching rule.
# Fails if nothing matches or if the matching rule is not enabled yet.
profile_for_event() {
    local ev=$1 table name vid pid fam match status rest
    table=$(profiles_path) || return 1
    name=$(read_file "$sys_input/$ev/device/name")
    vid=$(read_file "$sys_input/$ev/device/id/vendor")
    pid=$(read_file "$sys_input/$ev/device/id/product")
    while IFS=$'\t' read -r fam match status rest; do
        case "$fam" in ''|'#'*) continue;; esac
        # shellcheck disable=SC2254  # the "name:" rule is a glob on purpose (e.g. "Microsoft X-Box 360 pad*")
        case "$match" in
            name:*) case "$name" in ${match#name:}) ;; *) continue;; esac;;
            vid:*) [ "${match#vid:}" = "$vid" ] && has_js "$ev" || continue;;
            vidpid:*) [ "${match#vidpid:}" = "$vid:$pid" ] && has_js "$ev" || continue;;
            *) continue;;
        esac
        if [ "$status" != validated ] && [ "$experimental" != 1 ]; then return 1; fi
        printf '%s\t%s\n' "$fam" "$status"; return 0
    done <"$table"
    return 1
}

is_supported_controller() {
    local ev=$1 name=$2
    if profiles_path >/dev/null; then profile_for_event "$ev" >/dev/null; return; fi
    case "$name" in 'PLAYSTATION(R)3 Controller'|'Pro Controller'|'Nintendo Co., Ltd. Pro Controller'|'Joy-Con (L)'|'Joy-Con (R)'|'Nintendo Switch Combined Joy-Cons') return 0;; esac
    return 1
}

controller_parent() {
    local p=$1 n
    p=$(readlink -f "$p" 2>/dev/null || true)
    while [ -n "$p" ] && [ "$p" != / ]; do
        n=$(basename "$p")
        case "$n" in 0005:*|0003:*) printf '%s\n' "$n"; return 0;; esac
        p=$(dirname "$p")
    done
    return 1
}

controller_id() {
    local p=$1
    p=$(readlink -f "$p" 2>/dev/null || true)
    while [ -n "$p" ] && [ "$p" != / ]; do
        if [ -r "$p/uniq" ] && [ -s "$p/uniq" ]; then read_file "$p/uniq"; return 0; fi
        p=$(dirname "$p")
    done
    return 1
}

row_for_id() { awk -F '\t' -v i="$1" '$1==i{print;exit}' "$slots_file"; }
row_for_prefix() { awk -F '\t' -v p="$1" '$3==p{print;exit}' "$slots_file"; }
slot_in_use() { awk -F '\t' -v s="$1" '$2==s{x=1}END{exit !x}' "$slots_file"; }

# Player identity follows connection order: rows whose event has already
# disappeared are removed before any assignment, so a controller that
# reconnects does not inherit its old slot just because it has the same MAC.
# A controller that is still present (e.g. a Bluetooth -> USB switch) keeps its slot.
assign_slot() {
    local id=$1 row s
    cleanup_missing
    row=$(row_for_id "$id")
    if [ -n "$row" ]; then printf '%s\n' "$row" | cut -f2; return; fi
    for ((s=1; s<=max_players; s++)); do
        if ! slot_in_use "$s"; then
            printf '%s\t%s\t-\t-\n' "$id" "$s" >>"$slots_file"
            printf '%s\n' "$s"; return
        fi
    done
    printf '0\n'
}

# slot_mask SLOT [REVERSE] -> the 4-bit player LED mask (bit 0 = LED 1); REVERSE=1 mirrors it (right Joy-Con).
slot_mask() {
    local slot=$1 reverse=${2:-0} mask
    case "$slot" in
        1) mask=1;; 2) mask=2;; 3) mask=4;; 4) mask=8;;
        5) mask=9;; 6) mask=10;; 7) mask=12;; 8) mask=13;;
        *) mask=0;;
    esac
    if [ "$reverse" -eq 1 ]; then
        case "$slot" in
            1) mask=8;; 2) mask=4;; 3) mask=2;; 4) mask=1;;
            5) mask=9;; 6) mask=5;; 7) mask=3;; 8) mask=7;;
        esac
    fi
    printf '%s\n' "$mask"
}

set_player_leds() {
    local prefix=$1 slot=$2 controller_id=${3:-} reverse=${4:-0} n v mask=''
    [ -z "$controller_id" ] || mask=${led_manual[$controller_id]:-}
    [ -n "$mask" ] || mask=$(slot_mask "$slot" "$reverse")
    for n in 1 2 3 4; do
        v=0
        (( mask & (1 << (n - 1)) )) && v=1
        write_led "$sys_leds/$prefix:green:player-$n/brightness" "$v"
        write_led "$sys_leds/$prefix::sony$n/brightness" "$v"
    done
    if [ -x "$switchpro_helper" ] && [ -e "$sys_leds/$prefix:blue:player-5/brightness" ]; then
        if [ -n "$controller_id" ]; then
            "$switchpro_helper" --prefix "$prefix" --id "$controller_id" --mask "$mask" >/dev/null 2>&1 || true
        else
            "$switchpro_helper" --prefix "$prefix" --mask "$mask" >/dev/null 2>&1 || true
        fi
    fi
}

set_home_led() {
    local prefix=$1 home max
    home="$sys_leds/$prefix:blue:player-5/brightness"
    [ -e "$home" ] || return 0
    [ -z "${home_off[$prefix]:-}" ] || return 0
    max=$(read_file "${home%/brightness}/max_brightness")
    [ -n "$max" ] || max=1
    write_led "$home" "$max"
}

sync_combined_joycon_leds() {
    local slot=$1 p name prefix
    for p in "$sys_input"/event*; do
        [ -e "$p" ] || continue
        name=$(read_file "$p/device/name")
        case "$name" in
            'Joy-Con (L)'|'Joy-Con (R)')
                prefix=$(controller_parent "$p/device" || true)
                # set_home_led does nothing on the left Joy-Con, which has no HOME LED
                [ -n "$prefix" ] && { set_player_leds "$prefix" "$slot"; set_home_led "$prefix"; }
                ;;
        esac
    done
}

collapse_physical_joycons() {
    local id slot prefix event name
    while IFS=$'\t' read -r id slot prefix event; do
        [ -n "$id" ] || continue
        name=$(read_file "$sys_input/$event/device/name")
        case "$name" in
            'Joy-Con (L)'|'Joy-Con (R)') continue;;
        esac
        printf '%s\t%s\t%s\t%s\n' "$id" "$slot" "$prefix" "$event"
    done <"$slots_file" >"$slots_file.tmp"
    mv "$slots_file.tmp" "$slots_file"
}

now_s() { date +%s; }

# led_refresh_due PREFIX -> success if led_refresh seconds have passed since the last re-apply.
declare -gA led_last_refresh=() led_last_battery=()
# led_manual[ID]=mask: a pattern set by hand (SetPlayerLeds) that wins over the slot pattern.
# home_off[PREFIX]=1: the HOME LED was turned off by hand (SetHomeLed).
declare -gA led_manual=() home_off=()
led_refresh_due() {
    local k=$1 now last
    now=$(now_s); last=${led_last_refresh[$k]:--1}
    # "off": only the first pass for each connected device (its HID prefix changes on every
    # connection); after that only real changes (battery, charging blink) are written.
    if [ "$led_refresh" = off ]; then
        [ "$last" -lt 0 ] || return 1
        led_last_refresh[$k]=$now; return 0
    fi
    if [ "$led_refresh" -le 0 ] 2>/dev/null || [ "$last" -lt 0 ] || [ $((now - last)) -ge "$led_refresh" ]; then
        led_last_refresh[$k]=$now; return 0
    fi
    return 1
}

set_battery_led() {
    local prefix=$1 slot=$2 state=$3 charging=$4 phase=$5 force=${6:-1} v led

    # The current hid-nintendo exposes the blue HOME LED as player-5, but its
    # brightness can change without any physical change. We do not use that
    # state as a false indication: the battery indication stays on the
    # player LED, which is actually controllable.
    if [ "$charging" -eq 1 ]; then
        v=$((phase % 2))
    elif [ "$state" = low ] || [ "$state" = critical ]; then
        v=$(( phase == 0 ? 1 : 0 ))
    else
        v=1
    fi

    # With no value change and no forced re-apply, there is nothing to write.
    if [ "$force" -ne 1 ] && [ "${led_last_battery[$prefix:$slot]:-}" = "$v" ]; then return 0; fi
    led_last_battery[$prefix:$slot]=$v

    for led in "$sys_leds/$prefix:green:player-$slot/brightness" "$sys_leds/$prefix::sony$slot/brightness"; do
        write_led "$led" "$v"
    done
}

battery_state() {
    local cap=$1 level=$2
    if [ -n "$cap" ] && [ "$cap" -le 10 ] 2>/dev/null; then printf 'critical\n'
    elif [ -n "$cap" ] && [ "$cap" -le 25 ] 2>/dev/null; then printf 'low\n'
    elif [ "$level" = Critical ]; then printf 'critical\n'
    elif [ "$level" = Low ]; then printf 'low\n'
    else printf 'normal\n'; fi
}

register_event() {
    local event=$1 name path id prefix slot tmp reverse known prev
    name=$(read_file "$sys_input/$event/device/name")
    is_supported_controller "$event" "$name" || { ignored_events[$event]=1; return; }
    unset "ignored_events[$event]"
    path="$sys_input/$event/device"
    if [ "$name" = 'Nintendo Switch Combined Joy-Cons' ]; then
        collapse_physical_joycons
        id="joycond:$event"
        prefix=-
    else
        id=$(controller_id "$path" || true); prefix=$(controller_parent "$path" || true)
        if [ -z "$id" ] || [ -z "$prefix" ]; then
            # Non-HID drivers (e.g. xpad) have no uniq and no 0003/0005 parent: numbering only, no LEDs.
            id="phys:$(read_file "$path/phys")"
            [ "$id" != phys: ] || id="path:$(basename "$(readlink -f "$path" 2>/dev/null)")"
            prefix=-
        fi
    fi
    # Controller already registered on this same event (periodic scan): do not re-apply LEDs;
    # that is handled by the throttled refresh in update_batteries_once.
    known=0; prev=$(row_for_id "$id")
    [ -n "$prev" ] && [ "$(printf '%s\n' "$prev" | cut -f4)" = "$event" ] && known=1
    slot=$(assign_slot "$id"); [ "$slot" -gt 0 ] || return
    tmp="$slots_file.tmp"
    awk -F '\t' -v i="$id" -v p="$prefix" -v e="$event" 'BEGIN{OFS="\t"}$1==i{$3=p;$4=e}{print}' "$slots_file" >"$tmp"
    mv "$tmp" "$slots_file"
    [ "$known" -eq 1 ] && return
    if [ "$prefix" != - ]; then
        reverse=0
        [ "$name" = 'Joy-Con (R)' ] && reverse=1
        set_player_leds "$prefix" "$slot" "$id" "$reverse"
        set_home_led "$prefix"
    else
        sync_combined_joycon_leds "$slot"
    fi
}

# stop_idle_worker PIDFILE: the worker and the evtest pipeline it started (killing only the worker leaves them running).
stop_idle_worker() {
    local pid
    [ -r "$1" ] || return 0
    pid=$(cat "$1")
    [[ $pid =~ ^[0-9]+$ ]] && { pkill -P "$pid" 2>/dev/null || true; kill "$pid" 2>/dev/null || true; }
    rm -f "$1"
}
# Everything the main process started, for its exit trap.
stop_children() {
    stop_idle_workers
    [ -z "${monitor_pid:-}" ] || { pkill -P "$monitor_pid" 2>/dev/null || true; kill "$monitor_pid" 2>/dev/null || true; }
    return 0
}
stop_idle_workers() { local p; for p in "$runtime_dir"/idle.*.pid; do [ -e "$p" ] && stop_idle_worker "$p"; done; return 0; }

cleanup_missing() {
    local id slot prefix event pid
    while IFS=$'\t' read -r id slot prefix event; do
        [ -n "$id" ] || continue
        if [ "$event" != - ] && [ ! -e "$sys_input/$event" ]; then
            stop_idle_worker "$runtime_dir/idle.$slot.pid"; unset "led_manual[$id]"
        else printf '%s\t%s\t%s\t%s\n' "$id" "$slot" "$prefix" "$event"; fi
    done <"$slots_file" >"$slots_file.tmp"
    mv "$slots_file.tmp" "$slots_file"
}

idle_worker() {
    local id=$1 event=$2 start
    case "$id" in [0-9A-Fa-f][0-9A-Fa-f]:*) ;; *) return;; esac
    while [ -e "$sys_input/$event" ]; do
        start=$(now_s)
        if timeout "$idle_timeout" stdbuf -oL evtest "/dev/input/$event" 2>/dev/null | grep -m1 -q 'Event:'; then continue; fi
        [ -e "$sys_input/$event" ] || break
        # Only a full timeout without any input means idle. If evtest is missing or stopped
        # early (permissions, device going away), do not disconnect: wait and look again.
        if [ $(( $(now_s) - start )) -lt "$idle_timeout" ]; then sleep 5; continue; fi
        bluetoothctl disconnect "$id" >/dev/null 2>&1 || true
        # short pause before checking whether the device is gone
        sleep 0.25
    done
}

start_idle_workers() {
    local id slot prefix event pid
    [ "$idle_timeout" -gt 0 ] 2>/dev/null || return 0
    while IFS=$'\t' read -r id slot prefix event; do
        [ -n "$id" ] && [ "$event" != - ] || continue
        # Idle power-off is a Bluetooth disconnect: only Bluetooth HID devices (bus 0005) get a worker.
        case "$prefix" in 0005:*) ;; *) continue;; esac
        pid="$runtime_dir/idle.$slot.pid"
        if [ ! -r "$pid" ] || ! kill -0 "$(cat "$pid")" 2>/dev/null; then idle_worker "$id" "$event" 8<&- & printf '%s\n' "$!" >"$pid"; fi
    done <"$slots_file"
}

# The periodic scan used to re-read every input node (keyboards, mice, touchpads...) each
# cycle and match it against the profile table: about 1000 processes every 2 s, ~10% of a core
# on an idle desktop. Nodes already examined and not a supported controller are skipped
# until they are re-created (newer than the previous scan) or every rescan_every scans.
declare -gA ignored_events=()
scan_count=0
rescan_every=30
scan_existing() {
    local p e stamp="$runtime_dir/scan.stamp"
    (( scan_count++ % rescan_every == 0 )) && ignored_events=()
    for p in "$sys_input"/event*; do
        [ -e "$p" ] || continue
        e=${p##*/}
        if [ -n "${ignored_events[$e]:-}" ] && ! [ "$p" -nt "$stamp" ]; then continue; fi
        register_event "$e"
    done
    : >"$stamp"
}

monitor_udev() {
    local action='' event='' line
    while IFS= read -r line; do
        case "$line" in
            ACTION=add) action=add; event='';;
            ACTION=remove) action=remove;;
            DEVNAME=/dev/input/event*) event=${line##*/};;
            DEVPATH=*) if [ "$action" = add ] && [ -n "$event" ]; then register_event "$event"; action=''; event=''; fi;;
        esac
    done < <(udevadm monitor --udev --subsystem-match=input --property 2>/dev/null)
}

# Without "connectable" the adapter does not answer HOME reconnection from controllers
# such as the Pro Controller. bluetoothd may clear the mode on (re)start, so it is
# re-asserted periodically instead of once.
ensure_connectable() {
    command -v btmgmt >/dev/null 2>&1 || return 0
    btmgmt connectable on >/dev/null 2>&1 || true
}

update_batteries_once() {
    local b prefix id row slot event name reverse cap level status state phase refresh
    phase=$(( $(now_s) % 4 )); cleanup_missing; scan_existing; start_idle_workers
    battery_by_prefix=()
    for b in "$sys_power"/*controller_battery_*; do
        [ -e "$b" ] || continue
        prefix=$(basename "$(readlink -f "$b/device" 2>/dev/null || true)")
        id=$(controller_id "$b/device" || true); [ -n "$prefix" ] && [ -n "$id" ] || continue
        row=$(row_for_id "$id")
        [ -n "$row" ] || row=$(row_for_prefix "$prefix")
        if [ -z "$row" ]; then row=$(awk -F '\t' '$1 ~ /^joycond:/ {print;exit}' "$slots_file"); fi
        [ -n "$row" ] || continue
        slot=$(printf '%s\n' "$row" | cut -f2); event=$(printf '%s\n' "$row" | cut -f4); name=$(read_file "$sys_input/$event/device/name"); reverse=0
        [ "$name" = 'Joy-Con (R)' ] && reverse=1
        cap=$(read_file "$b/capacity"); level=$(read_file "$b/capacity_level"); status=$(read_file "$b/status"); state=$(battery_state "$cap" "$level")
        battery_by_prefix[$prefix]="$cap"$'\t'"$status"$'\t'"$state"
        # A pattern set by hand (SetPlayerLeds) is left alone: no re-apply, no battery blinking.
        [ -z "${led_manual[$id]:-}" ] || continue
        # Every led_refresh s, re-apply the player identification before the battery
        # state; this also restores the LEDs if the controller firmware has updated them.
        refresh=0
        if led_refresh_due "$prefix"; then
            refresh=1
            set_player_leds "$prefix" "$slot" "$id" "$reverse"
            set_home_led "$prefix"
        fi
        set_battery_led "$prefix" "$slot" "$state" "$([ "$status" = Charging ] && printf 1 || printf 0)" "$phase" "$refresh"
        if [ "$refresh" -eq 1 ]; then case "$row" in joycond:*) sync_combined_joycon_leds "$slot";; esac; fi
    done
    write_state
}

# ---- state snapshot for clients (the interface) --------------------------------------------
# $runtime_dir/state.json, format "ujm-state" version 1 (documented in docs/state.md). It is
# rewritten atomically and only when something other than the timestamp changed.
declare -gA battery_by_prefix=()
state_body_last=''
json_str() {
    local s=$1
    s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\t'/\\t}; s=${s//$'\n'/\\n}; s=${s//$'\r'/}
    printf '"%s"' "$s"
}
json_int() { if [[ $1 =~ ^[0-9]+$ ]]; then printf '%s' "$1"; else printf 'null'; fi; }

write_state() {
    local id slot prefix event name family transport reverse battery cap status state first=1 body out tmp mask manual home
    body='"format":"ujm-state","version":1,"service":{"led_refresh":'"$(json_str "$led_refresh")"',"idle_timeout":'"$(json_int "$idle_timeout")"',"experimental":'"$([ "$experimental" = 1 ] && printf true || printf false)"'},"controllers":['
    while IFS=$'\t' read -r id slot prefix event; do
        [ -n "$id" ] || continue
        name=$(read_file "$sys_input/$event/device/name")
        family=$(profile_for_event "$event" 2>/dev/null | cut -f1)
        case "$id:$prefix" in
            joycond:*) transport=virtual; family=${family:-joycon-combined};;
            *:0005:*) transport=bluetooth;;
            *:0003:*) transport=usb;;
            *) transport=other;;
        esac
        reverse=0; [ "$name" = 'Joy-Con (R)' ] && reverse=1
        mask=${led_manual[$id]:-}; manual=true; [ -n "$mask" ] || { manual=false; mask=$(slot_mask "$slot" "$reverse"); }
        home=unsupported
        if [ "$prefix" != - ] && [ -e "$sys_leds/$prefix:blue:player-5/brightness" ]; then home=on; [ -z "${home_off[$prefix]:-}" ] || home=off; fi
        battery=null
        if [ "$prefix" != - ] && [ -n "${battery_by_prefix[$prefix]:-}" ]; then
            IFS=$'\t' read -r cap status state <<<"${battery_by_prefix[$prefix]}"
            battery='{"percent":'"$(json_int "$cap")"',"status":'"$(json_str "$status")"',"level":'"$(json_str "$state")"'}'
        fi
        [ "$first" -eq 1 ] || body+=','; first=0
        body+='{"id":'"$(json_str "$id")"',"player":'"$(json_int "$slot")"',"name":'"$(json_str "$name")"',"family":'"$(if [ -n "$family" ]; then json_str "$family"; else printf null; fi)"',"transport":"'"$transport"'","hid":'"$(if [ "$prefix" = - ]; then printf null; else json_str "$prefix"; fi)"',"event":'"$(json_str "$event")"',"player_led_mask":'"$mask"',"player_led_manual":'"$manual"',"home_led":"'"$home"'","battery":'"$battery"'}'
    done < <(sort -t $'\t' -k2,2n "$slots_file")
    body+=']'
    [ "$body" = "$state_body_last" ] && return 0
    out='{"updated":'"$(now_s)"','"$body"'}'
    tmp="$runtime_dir/state.json.tmp"
    printf '%s\n' "$out" >"$tmp" && chmod 644 "$tmp" && mv -f "$tmp" "$runtime_dir/state.json" && state_body_last=$body
}

# ---- command channel (docs/command-channel.md) --------------------------------------------
# The bridge writes one line per request to a FIFO that only root can open:
#   REQ <TAB> request-id <TAB> command <TAB> arg1 <TAB> arg2
# and reads the answer from $ack_dir/request-id ("ok", or "error<TAB>reason"). The service is the
# only writer of LEDs and numbering; every argument is checked here again, whatever the sender did.
open_command_channel() {
    rm -rf "$ack_dir"
    [ -p "$cmd_fifo" ] || { rm -f "$cmd_fifo"; mkfifo -m 600 "$cmd_fifo" 2>/dev/null || return 0; }
    { exec 8<>"$cmd_fifo"; } 2>/dev/null && cmd_fd_ok=1
    return 0
}

write_ack() { # REQID RESULT
    mkdir -p "$ack_dir" 2>/dev/null && chmod 700 "$ack_dir" || return 0
    printf '%s\n' "$2" >"$ack_dir/$1.tmp" && mv -f "$ack_dir/$1.tmp" "$ack_dir/$1"
}

# controller_row ID -> c_slot, c_prefix, c_event of a connected controller; fails if there is none
controller_row() {
    local row
    row=$(row_for_id "$1"); [ -n "$row" ] || return 1
    IFS=$'\t' read -r _ c_slot c_prefix c_event <<<"$row"
}

has_player_leds() {
    [ "$1" != - ] && { [ -e "$sys_leds/$1:green:player-1/brightness" ] || [ -e "$sys_leds/$1::sony1/brightness" ] || [ -e "$sys_leds/$1:blue:player-5/brightness" ]; }
}

cmd_player_leds() { # ID MASK (0-15, or 255 to go back to the automatic pattern)
    local id=$1 mask=$2 reverse=0 name
    if ! { [[ $mask =~ ^[0-9]{1,3}$ ]] && { [ "$mask" -le 15 ] || [ "$mask" -eq 255 ]; }; }; then
        cmd_result=$'error\tmask must be 0-15, or 255 to go back to the automatic pattern'; return
    fi
    controller_row "$id" || { cmd_result=$'error\tno connected controller with that id'; return; }
    has_player_leds "$c_prefix" || { cmd_result=$'error\tthis controller has no player LEDs the service can write'; return; }
    if [ "$mask" -eq 255 ]; then
        unset "led_manual[$id]" "led_last_refresh[$c_prefix]" "led_last_battery[$c_prefix:$c_slot]"
    else
        led_manual[$id]=$mask
    fi
    name=$(read_file "$sys_input/$c_event/device/name"); [ "$name" = 'Joy-Con (R)' ] && reverse=1
    set_player_leds "$c_prefix" "$c_slot" "$id" "$reverse"
    cmd_result=ok
}

cmd_home_led() { # ID on|off
    local id=$1 on home
    case "$2" in 1|on|true) on=1;; 0|off|false) on=0;; *) cmd_result=$'error\tthe value must be on or off'; return;; esac
    controller_row "$id" || { cmd_result=$'error\tno connected controller with that id'; return; }
    home="$sys_leds/$c_prefix:blue:player-5/brightness"
    if [ "$c_prefix" = - ] || [ ! -e "$home" ]; then cmd_result=$'error\tthis controller has no HOME LED'; return; fi
    if [ "$on" -eq 1 ]; then unset "home_off[$c_prefix]"; set_home_led "$c_prefix"
    else home_off[$c_prefix]=1; write_led "$home" 0; fi
    cmd_result=ok
}

cmd_idle_timeout() { # SECONDS: 0 = never, otherwise 60-86400; kept across restarts
    local n=$1 tmp="$settings_file.tmp"
    valid_idle_timeout "$n" 2>/dev/null || { cmd_result=$'error\tseconds must be 0 (never) or between 60 and 86400'; return; }
    if ! { mkdir -p "$state_dir" && printf 'idle_timeout=%s\n' "$n" >"$tmp" && mv -f "$tmp" "$settings_file"; } 2>/dev/null; then
        cmd_result=$'error\tthe setting could not be saved'; return
    fi
    idle_timeout=$n
    stop_idle_workers   # they come back with the new value on the next cycle (or not at all for 0)
    cmd_result=ok
}

handle_command() { # one line from the FIFO
    local tag reqid cmd a1 a2
    IFS=$'\t' read -r tag reqid cmd a1 a2 <<<"$1"
    [ "$tag" = REQ ] || return 0
    [[ $reqid =~ ^[A-Za-z0-9]{8,64}$ ]] || return 0
    cmd_result=''
    case "$cmd" in
        idle_timeout) cmd_idle_timeout "$a1";;
        player_leds) cmd_player_leds "$a1" "$a2";;
        home_led) cmd_home_led "$a1" "$a2";;
        *) cmd_result=$'error\tunknown command';;
    esac
    printf 'command %s: %s\n' "$cmd" "${cmd_result%%$'\t'*}" >&2
    write_ack "$reqid" "$cmd_result"
}

# The 2 s pause of the main loop is a read on the FIFO with a timeout: a builtin, so no process is
# started per cycle, and a command is answered at once instead of at the next cycle.
wait_for_commands() {
    local line rc
    if [ "$cmd_fd_ok" -ne 1 ]; then sleep 2; return; fi
    read -r -t 2 -u 8 line; rc=$?
    if [ "$rc" -eq 0 ]; then
        handle_command "$line"
        while read -r -t 0.05 -u 8 line; do handle_command "$line"; done
    elif [ "$rc" -le 128 ]; then
        sleep 2   # not a timeout: the FIFO is unusable, do not spin
    fi
}

update_batteries() {
    local tick=0
    while :; do
        (( tick++ % 10 == 0 )) && ensure_connectable
        update_batteries_once
        wait_for_commands
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    # Stop everything this process started: under systemd the cgroup does it, but a manual run
    # (or a test) used to leave the udev monitor behind.
    trap 'stop_children; rm -f "$cmd_fifo"; rm -rf "$ack_dir"; exit 0' INT TERM EXIT
    open_command_channel
    scan_existing
    monitor_udev 8<&- &
    monitor_pid=$!
    update_batteries
fi
