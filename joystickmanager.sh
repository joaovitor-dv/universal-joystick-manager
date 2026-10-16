#!/usr/bin/env bash
set -u

runtime_dir=${JOYMANAGER_RUNTIME_DIR:-/run/joystickmanager}
sys_input=${JOYMANAGER_SYS_INPUT:-/sys/class/input}
sys_leds=${JOYMANAGER_SYS_LEDS:-/sys/class/leds}
sys_power=${JOYMANAGER_SYS_POWER:-/sys/class/power_supply}
# Each LED write on a Pro Controller/Joy-Con is an HID subcommand. Rewriting
# everything every 2 s cycle overloads the controller ("exceeded max attempts" errors and
# timeout drops). LEDs are only re-applied every JOYMANAGER_LED_REFRESH
# seconds (0 = every cycle, the old behavior); real changes are written immediately.
led_refresh=${JOYMANAGER_LED_REFRESH:-10}
slots_file="$runtime_dir/slots.tsv"
max_players=8
idle_timeout=${JOYMANAGER_IDLE_TIMEOUT:-1800}
switchpro_helper=/usr/local/libexec/joystickmanager-switchpro-leds
# "experimental" and "planned" controllers in controllers.tsv are only used with JOYMANAGER_EXPERIMENTAL=1.
experimental=${JOYMANAGER_EXPERIMENTAL:-0}
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)
mkdir -p "$runtime_dir"
touch "$slots_file"

write_led() { local p=$1 v=$2; [ -e "$p" ] && printf '%s\n' "$v" >"$p" 2>/dev/null || true; }
read_file() { [ -r "$1" ] && cat "$1" || true; }

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

set_player_leds() {
    local prefix=$1 slot=$2 controller_id=${3:-} reverse=${4:-0} n v mask
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
                [ -n "$prefix" ] && set_player_leds "$prefix" "$slot"
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
led_refresh_due() {
    local k=$1 now last
    now=$(now_s); last=${led_last_refresh[$k]:--1}
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
    is_supported_controller "$event" "$name" || return
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

cleanup_missing() {
    local id slot prefix event pid
    while IFS=$'\t' read -r id slot prefix event; do
        [ -n "$id" ] || continue
        if [ "$event" != - ] && [ ! -e "$sys_input/$event" ]; then
            pid="$runtime_dir/idle.$slot.pid"; [ -r "$pid" ] && kill "$(cat "$pid")" 2>/dev/null || true; rm -f "$pid"
        else printf '%s\t%s\t%s\t%s\n' "$id" "$slot" "$prefix" "$event"; fi
    done <"$slots_file" >"$slots_file.tmp"
    mv "$slots_file.tmp" "$slots_file"
}

idle_worker() {
    local id=$1 event=$2
    case "$id" in [0-9A-Fa-f][0-9A-Fa-f]:*) ;; *) return;; esac
    while [ -e "$sys_input/$event" ]; do
        timeout "$idle_timeout" stdbuf -oL evtest "/dev/input/$event" 2>/dev/null | grep -m1 -q 'Event:' || true
        [ -e "$sys_input/$event" ] || break
        bluetoothctl disconnect "$id" >/dev/null 2>&1 || true
        # hid-nintendo may restore the pairing LED pattern after an input
        # report; we re-apply the indication with low latency to keep it
        # physically stable.
        sleep 0.25
    done
}

start_idle_workers() {
    local id slot prefix event pid
    while IFS=$'\t' read -r id slot prefix event; do
        [ -n "$id" ] && [ "$event" != - ] || continue
        pid="$runtime_dir/idle.$slot.pid"
        if [ ! -r "$pid" ] || ! kill -0 "$(cat "$pid")" 2>/dev/null; then idle_worker "$id" "$event" & printf '%s\n' "$!" >"$pid"; fi
    done <"$slots_file"
}

scan_existing() { local p e; for p in "$sys_input"/event*; do [ -e "$p" ] || continue; e=$(basename "$p"); register_event "$e"; done; }

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
}

update_batteries() {
    local tick=0
    while :; do
        (( tick++ % 10 == 0 )) && ensure_connectable
        update_batteries_once
        sleep 2
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    trap 'for p in "$runtime_dir"/idle.*.pid; do [ -r "$p" ] && kill "$(cat "$p")" 2>/dev/null || true; done; exit 0' INT TERM EXIT
    scan_existing
    monitor_udev &
    update_batteries
fi
