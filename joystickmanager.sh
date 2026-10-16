#!/usr/bin/env bash
set -u

runtime_dir=/run/joystickmanager
slots_file="$runtime_dir/slots.tsv"
max_players=8
switchpro_helper=/usr/local/libexec/joystickmanager-switchpro-leds
mkdir -p "$runtime_dir"
touch "$slots_file"

write_led() { local p=$1 v=$2; [ -e "$p" ] && printf '%s\n' "$v" >"$p" 2>/dev/null || true; }
read_file() { [ -r "$1" ] && cat "$1" || true; }

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

assign_slot() {
    local id=$1 row s
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
    local prefix=$1 slot=$2 controller_id=${3:-} n v mask
    case "$slot" in
        1) mask=1;; 2) mask=2;; 3) mask=4;; 4) mask=8;;
        5) mask=9;; 6) mask=10;; 7) mask=12;; 8) mask=13;;
        *) mask=0;;
    esac
    for n in 1 2 3 4; do
        v=0
        (( mask & (1 << (n - 1)) )) && v=1
        write_led "/sys/class/leds/$prefix:green:player-$n/brightness" "$v"
        write_led "/sys/class/leds/$prefix::sony$n/brightness" "$v"
    done
    if [ -x "$switchpro_helper" ] && [ -e "/sys/class/leds/$prefix:blue:player-5/brightness" ]; then
        if [ -n "$controller_id" ]; then
            "$switchpro_helper" --prefix "$prefix" --id "$controller_id" --mask "$mask" >/dev/null 2>&1 || true
        else
            "$switchpro_helper" --prefix "$prefix" --mask "$mask" >/dev/null 2>&1 || true
        fi
    fi
}

set_home_led() {
    local prefix=$1 home max
    home="/sys/class/leds/$prefix:blue:player-5/brightness"
    [ -e "$home" ] || return 0
    max=$(read_file "${home%/brightness}/max_brightness")
    [ -n "$max" ] || max=1
    write_led "$home" "$max"
}

sync_combined_joycon_leds() {
    local slot=$1 p name prefix
    for p in /sys/class/input/event*; do
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
        name=$(read_file "/sys/class/input/$event/device/name")
        case "$name" in
            'Joy-Con (L)'|'Joy-Con (R)') continue;;
        esac
        printf '%s\t%s\t%s\t%s\n' "$id" "$slot" "$prefix" "$event"
    done <"$slots_file" >"$slots_file.tmp"
    mv "$slots_file.tmp" "$slots_file"
}

set_battery_led() {
    local prefix=$1 slot=$2 state=$3 charging=$4 phase=$5 v led

    # O hid-nintendo atual expõe o LED HOME azul como player-5, mas o
    # brightness pode mudar sem produzir uma alteração física. Não usamos
    # esse estado como indicação falsa: a indicação de bateria permanece no
    # LED do jogador, que é efetivamente controlável.
    if [ "$charging" -eq 1 ]; then
        v=$((phase % 2))
    elif [ "$state" = low ] || [ "$state" = critical ]; then
        v=$(( phase == 0 ? 1 : 0 ))
    else
        v=1
    fi

    for led in "/sys/class/leds/$prefix:green:player-$slot/brightness" "/sys/class/leds/$prefix::sony$slot/brightness"; do
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
    local event=$1 name path id prefix slot tmp
    name=$(read_file "/sys/class/input/$event/device/name")
    case "$name" in 'PLAYSTATION(R)3 Controller'|'Pro Controller'|'Joy-Con (L)'|'Joy-Con (R)'|'Nintendo Switch Combined Joy-Cons');;*) return;;esac
    path="/sys/class/input/$event/device"
    if [ "$name" = 'Nintendo Switch Combined Joy-Cons' ]; then
        collapse_physical_joycons
        id="joycond:$event"
        prefix=-
    else
        id=$(controller_id "$path" || true); prefix=$(controller_parent "$path" || true)
        [ -n "$id" ] && [ -n "$prefix" ] || return
    fi
    slot=$(assign_slot "$id"); [ "$slot" -gt 0 ] || return
    tmp="$slots_file.tmp"
    awk -F '\t' -v i="$id" -v p="$prefix" -v e="$event" 'BEGIN{OFS="\t"}$1==i{$3=p;$4=e}{print}' "$slots_file" >"$tmp"
    mv "$tmp" "$slots_file"
    [ "$prefix" != - ] && { set_player_leds "$prefix" "$slot" "$id"; set_home_led "$prefix"; } || sync_combined_joycon_leds "$slot"
}

cleanup_missing() {
    local id slot prefix event pid
    while IFS=$'\t' read -r id slot prefix event; do
        [ -n "$id" ] || continue
        if [ "$event" != - ] && [ ! -e "/sys/class/input/$event" ]; then
            pid="$runtime_dir/idle.$slot.pid"; [ -r "$pid" ] && kill "$(cat "$pid")" 2>/dev/null || true; rm -f "$pid"
        else printf '%s\t%s\t%s\t%s\n' "$id" "$slot" "$prefix" "$event"; fi
    done <"$slots_file" >"$slots_file.tmp"
    mv "$slots_file.tmp" "$slots_file"
}

idle_worker() {
    local id=$1 event=$2
    case "$id" in [0-9A-Fa-f][0-9A-Fa-f]:*) ;; *) return;; esac
    while [ -e "/sys/class/input/$event" ]; do
        timeout 300 stdbuf -oL evtest "/dev/input/$event" 2>/dev/null | grep -m1 -q 'Event:' || true
        [ -e "/sys/class/input/$event" ] || break
        bluetoothctl disconnect "$id" >/dev/null 2>&1 || true
        # O hid-nintendo pode restaurar o padrão de pareamento dos LEDs
        # após um relatório de entrada; reaplicamos a indicação com baixa
        # latência para mantê-la estável fisicamente.
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

scan_existing() { local p e; for p in /sys/class/input/event*; do [ -e "$p" ] || continue; e=$(basename "$p"); register_event "$e"; done; }

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

update_batteries() {
    local b prefix id row slot cap level status state phase
    while :; do
        phase=$(( $(date +%s) % 4 )); cleanup_missing; scan_existing; start_idle_workers
        for b in /sys/class/power_supply/*controller_battery_*; do
            [ -e "$b" ] || continue
            prefix=$(basename "$(readlink -f "$b/device" 2>/dev/null || true)")
            id=$(controller_id "$b/device" || true); [ -n "$prefix" ] && [ -n "$id" ] || continue
            row=$(row_for_id "$id")
            [ -n "$row" ] || row=$(row_for_prefix "$prefix")
            if [ -z "$row" ]; then row=$(awk -F '\t' '$1 ~ /^joycond:/ {print;exit}' "$slots_file"); fi
            [ -n "$row" ] || continue
            slot=$(printf '%s\n' "$row" | cut -f2); cap=$(read_file "$b/capacity"); level=$(read_file "$b/capacity_level"); status=$(read_file "$b/status"); state=$(battery_state "$cap" "$level")
            # Reaplica a identificação do jogador antes do estado da bateria.
            # Isso também restaura os LEDs após o firmware do controle atualizá-los.
            set_player_leds "$prefix" "$slot" "$id"
            set_home_led "$prefix"
            set_battery_led "$prefix" "$slot" "$state" "$([ "$status" = Charging ] && printf 1 || printf 0)" "$phase"
            case "$row" in joycond:*) sync_combined_joycon_leds "$slot";; esac
        done
        sleep 2
    done
}

trap 'for p in "$runtime_dir"/idle.*.pid; do [ -r "$p" ] && kill "$(cat "$p")" 2>/dev/null || true; done; exit 0' INT TERM EXIT
scan_existing
monitor_udev &
update_batteries
