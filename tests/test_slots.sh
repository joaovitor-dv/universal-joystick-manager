#!/usr/bin/env bash
# Player numbering (connection order), controller profile and LED tests, using a fake sysfs.
# Usage: tests/test_slots.sh   (exit status = number of failures)
# shellcheck disable=SC2154,SC2034  # variables come from the sourced joystickmanager.sh and are read by its functions
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

A=AA:AA:AA:AA:AA:01 B=BB:BB:BB:BB:BB:02 C=CC:CC:CC:CC:CC:03 D=DD:DD:DD:DD:DD:04
fails=0

setup() {
    T=$(mktemp -d)
    export JOYMANAGER_RUNTIME_DIR="$T/run" JOYMANAGER_SYS_INPUT="$T/input"
    # use the repository table, never one installed on the machine running the tests
    export JOYMANAGER_PROFILES="$here/controllers.tsv"
    export JOYMANAGER_LED_SETTLE=0           # most tests want the LEDs written at once; the settle tests set it
    export JOYMANAGER_STATE_DIR="$T/state"   # settings saved at run time never go to the machine's /var/lib
    mkdir -p "$T/run" "$T/input" "$T/dev"
    # shellcheck source=../joystickmanager.sh
    source "$here/joystickmanager.sh"
}

# connect <event> <mac> [name]
connect() {
    local ev=$1 mac=$2 name=${3:-Pro Controller} d
    d="$T/dev/0005:057E:2009.$mac"
    mkdir -p "$d" "$sys_input/$ev"
    printf '%s\n' "$mac" >"$d/uniq"
    printf '%s\n' "$name" >"$d/name"
    ln -sfn "$d" "$sys_input/$ev/device"
    register_event "$ev"
}
disconnect() { rm -rf "${sys_input:?}/$1"; }
slot_of() { awk -F '\t' -v i="$1" '$1==i{print $2}' "$slots_file"; }

check() { # description expected got
    if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"
    else printf 'FAIL - %s (expected=%s got=%s)\n' "$1" "$2" "$3"; _f=$((_f+1)); fi
}

run() { # runs scenario $1 in an isolated subshell and adds up the failures
    local rc
    ( _f=0; setup; "$1"; exit "$_f" ); rc=$?
    fails=$((fails+rc))
}

t_arrival_order() {
    connect event1 $A; connect event2 $B; connect event3 $C
    check "A arrives first  -> slot 1" 1 "$(slot_of $A)"
    check "B arrives second -> slot 2" 2 "$(slot_of $B)"
    check "C arrives last   -> slot 3" 3 "$(slot_of $C)"
}

t_freed_slot_goes_to_next_arrival() {
    connect event1 $A; connect event2 $B; connect event3 $C
    disconnect event2; cleanup_missing
    connect event4 $D
    check "D takes the slot freed by B" 2 "$(slot_of $D)"
    check "A and C keep their slots" "1 3" "$(slot_of $A) $(slot_of $C)"
}

t_reconnect_with_stale_row_not_yet_cleaned() {
    # A and B drop; the periodic cleanup (2 s) has not run yet; B comes back.
    connect event1 $A; connect event2 $B; connect event3 $C
    disconnect event1; disconnect event2
    connect event4 $B
    check "reconnected B enters as a new arrival (lowest free slot)" 1 "$(slot_of $B)"
    check "C keeps slot 3" 3 "$(slot_of $C)"
}

t_same_controller_still_present_keeps_slot() {
    # BT -> USB switch: the same MAC shows up on another event while the old one still exists.
    connect event1 $A; connect event2 $B
    connect event5 $B
    check "B (still present) keeps slot 2" 2 "$(slot_of $B)"
    check "no duplicate row for B" 1 "$(grep -c "^$B" "$slots_file")"
}

t_pro_controller_over_usb_is_registered() {
    # Over USB the kernel prefixes the device name with the manufacturer and there is an IMU node.
    local d="$T/dev/0003:057E:2009.0016"
    mkdir -p "$d" "$sys_input/event7" "$sys_input/event8"
    printf '%s\n' $A >"$d/uniq"
    printf 'Nintendo Co., Ltd. Pro Controller\n' >"$d/name"
    ln -sfn "$d" "$sys_input/event7/device"
    printf 'Nintendo Co., Ltd. Pro Controller (IMU)\n' >"$d/name_imu"
    mkdir -p "$T/dev/imu"; printf '%s\n' $A >"$T/dev/imu/uniq"
    printf 'Nintendo Co., Ltd. Pro Controller (IMU)\n' >"$T/dev/imu/name"
    mv "$T/dev/imu" "$T/dev/0003:057E:2009.0016-imu"
    ln -sfn "$T/dev/0003:057E:2009.0016-imu" "$sys_input/event8/device"
    register_event event7; register_event event8
    check "Pro Controller over USB gets slot 1" 1 "$(slot_of $A)"
    check "IMU node does not add an extra row" 1 "$(wc -l <"$slots_file")"
}

t_connectable_is_reasserted() {
    # Fake btmgmt on PATH: ensure_connectable must call it with "connectable on".
    mkdir -p "$T/bin"
    printf '#!/bin/sh\necho "$@" >>"%s/btmgmt.log"\n' "$T" >"$T/bin/btmgmt"; chmod +x "$T/bin/btmgmt"
    PATH="$T/bin:$PATH" ensure_connectable; PATH="$T/bin:$PATH" ensure_connectable
    check "btmgmt connectable on is called on every re-assertion" "connectable on connectable on" "$(tr '\n' ' ' <"$T/btmgmt.log" | sed 's/ $//')"
}

# fake_input <event> <name> <vid> <pid> [js]  (non-HID device, like xpad)
fake_input() {
    local ev=$1 d="$T/dev/in-$1"
    mkdir -p "$d/id" "$sys_input/$ev"
    printf '%s\n' "$2" >"$d/name"; printf '%s\n' "$3" >"$d/id/vendor"; printf '%s\n' "$4" >"$d/id/product"
    printf 'usb-fake/%s\n' "$ev" >"$d/phys"
    [ "${5:-}" = js ] && mkdir -p "$d/js0"
    ln -sfn "$d" "$sys_input/$ev/device"
}
profile_of() { profile_for_event "$1" 2>/dev/null | cut -f1; }

t_validated_profiles_always_active() {
    experimental=0
    fake_input event1 "PLAYSTATION(R)3 Controller" 054c 0268
    fake_input event2 "Nintendo Co., Ltd. Pro Controller" 057e 2009
    check "PS3 matches the ps3 profile" ps3 "$(profile_of event1)"
    check "Pro over USB matches switch-pro" switch-pro "$(profile_of event2)"
}

t_experimental_profiles_need_flag() {
    fake_input event1 "DualSense Wireless Controller" 054c 0ce6
    experimental=0; check "DualSense is off by default" "" "$(profile_of event1)"
    experimental=1; check "DualSense is active with the flag" dualsense "$(profile_of event1)"
}

t_vendor_rule_requires_js() {
    experimental=1
    fake_input event1 "8BitDo Pro 2" 2dc8 6003 js
    fake_input event2 "8BitDo Pro 2 Motion" 2dc8 6003
    check "8BitDo with a js node matches" 8bitdo "$(profile_of event1)"
    check "node without js (IMU/keyboard) does not match" "" "$(profile_of event2)"
}

t_extra_dualshock4_nodes_ignored() {
    experimental=1
    fake_input event1 "Wireless Controller" 054c 09cc
    fake_input event2 "Wireless Controller Motion Sensors" 054c 09cc
    fake_input event3 "Wireless Controller Touchpad" 054c 09cc
    check "main DS4 node matches" dualshock4 "$(profile_of event1)"
    check "Motion Sensors does not match" "" "$(profile_of event2)"
    check "Touchpad does not match" "" "$(profile_of event3)"
}

t_non_hid_controller_gets_slot() {
    experimental=1
    fake_input event1 "Microsoft X-Box 360 pad" 045e 028e js
    register_event event1
    check "xpad registered with 1 row" 1 "$(wc -l <"$slots_file")"
    check "xpad gets slot 1" 1 "$(cut -f2 "$slots_file")"
}

t_without_table_uses_fixed_list() {
    JOYMANAGER_PROFILES=/does/not/exist
    fake_input event1 "Pro Controller" 057e 2009
    fake_input event2 "DualSense Wireless Controller" 054c 0ce6
    is_supported_controller event1 "Pro Controller"; check "without a table, Pro Controller is ok" 0 $?
    is_supported_controller event2 "DualSense Wireless Controller"; check "without a table, DualSense is out" 1 $?
}

t_doctor_lists_controllers() {
    fake_input event1 "PLAYSTATION(R)3 Controller" 054c 0268
    fake_input event2 "DualSense Wireless Controller" 054c 0ce6
    local out; out=$(JOYMANAGER_SYS_INPUT="$sys_input" "$here/joystickmanager-doctor" 2>&1)
    check "doctor shows the PS3 as active" 1 "$(grep -c 'profile=ps3 .*-> active' <<<"$out")"
    check "doctor shows the DualSense as ignored" 1 "$(grep -c 'profile=dualsense .*ignored' <<<"$out")"
}

# leds_setup: registered Pro Controller, fake LEDs and battery, counting write_led.
leds_setup() {
    local pre="0005:057E:2009.$A" b n
    sys_leds="$T/leds"; sys_power="$T/power"; b="$T/power/nintendo_switch_controller_battery_x"
    mkdir -p "$b"
    for n in 1 2 3 4; do mkdir -p "$sys_leds/$pre:green:player-$n"; : >"$sys_leds/$pre:green:player-$n/brightness"; done
    writes=0
    write_led() { [ -e "$1" ] && writes=$((writes+1)); return 0; }
    start_idle_workers() { :; }
    now_s() { printf '%s\n' "$NOW"; }
    connect event1 $A
    ln -sfn "$T/dev/$pre" "$b/device"
    printf 'Discharging\n' >"$b/status"; printf '80\n' >"$b/capacity"
    BATT="$b"
}

t_leds_not_rewritten_within_window() {
    NOW=1000; led_refresh=10; leds_setup; writes=0
    update_batteries_once; first=$writes
    [ "$first" -gt 0 ]; check "first cycle applies the LEDs" 0 $?
    for NOW in 1002 1004 1006 1008; do update_batteries_once; done
    check "4 cycles within 10 s write nothing" "$first" "$writes"
    NOW=1010; update_batteries_once
    check "after 10 s everything is re-applied" $((first * 2)) "$writes"
}

t_refresh_zero_keeps_old_behavior() {
    NOW=1000; led_refresh=0; leds_setup; writes=0
    update_batteries_once; first=$writes
    for NOW in 1002 1004; do update_batteries_once; done
    check "refresh=0 rewrites on every cycle" $((first * 3)) "$writes"
}

t_battery_change_writes_immediately() {
    NOW=1000; led_refresh=10; leds_setup; writes=0
    update_batteries_once
    printf 'Charging\n' >"$BATT/status"; NOW=1002; before=$writes
    update_batteries_once
    check "starting to charge writes only the battery LED" $((before + 1)) "$writes"
    NOW=1006; before=$writes; update_batteries_once   # same blink phase (1006%4 == 1002%4)
    check "same blink value on the next cycle writes nothing" "$before" "$writes"
    NOW=1007; before=$writes; update_batteries_once   # opposite phase: the LED blinks
    check "opposite blink phase writes once" $((before + 1)) "$writes"
}

t_refresh_off_applies_once_then_only_changes() {
    NOW=1000; led_refresh=off; leds_setup; writes=0
    update_batteries_once; first=$writes
    [ "$first" -gt 0 ]; check "off: the first cycle applies the LEDs" 0 $?
    for ((NOW=1010; NOW<=1600; NOW+=10)); do update_batteries_once; done
    check "off: 10 simulated minutes write nothing more" "$first" "$writes"
    printf 'Charging\n' >"$BATT/status"; NOW=1602; before=$writes; update_batteries_once
    check "off: starting to charge still writes the battery LED" $((before + 1)) "$writes"
}

t_refresh_off_new_connection_gets_leds() {
    NOW=1000; led_refresh=off; leds_setup; update_batteries_once; writes=0
    # reconnection: same controller (same MAC), new HID device and prefix
    local pre2="0005:057E:2009.0099" n
    mkdir -p "$T/dev/$pre2"; printf '%s\n' "$A" >"$T/dev/$pre2/uniq"
    for n in 1 2 3 4; do mkdir -p "$sys_leds/$pre2:green:player-$n"; : >"$sys_leds/$pre2:green:player-$n/brightness"; done
    ln -sfn "$T/dev/$pre2" "$BATT/device"
    NOW=1010; update_batteries_once
    [ "$writes" -gt 0 ]; check "off: a reconnected controller gets its LEDs again" 0 $?
}

t_invalid_led_refresh_falls_back_to_10() {
    JOYMANAGER_LED_REFRESH=abc source "$here/joystickmanager.sh"; check "an invalid value falls back to 10" 10 "$led_refresh"
    JOYMANAGER_LED_REFRESH=off source "$here/joystickmanager.sh"; check "off is kept" off "$led_refresh"
    JOYMANAGER_LED_REFRESH=0 source "$here/joystickmanager.sh"; check "0 is kept" 0 "$led_refresh"
}

# fake_bins: evtest and bluetoothctl stubs on PATH; bluetoothctl calls are logged.
fake_bins() { # $1 = evtest behavior: "idle" (no input until killed) or "fail" (exits at once)
    mkdir -p "$T/bin"
    printf '#!/bin/sh\necho "$@" >>"%s/bt.log"\n' "$T" >"$T/bin/bluetoothctl"
    if [ "$1" = idle ]; then printf '#!/bin/sh\nexec sleep 30\n' >"$T/bin/evtest"; else printf '#!/bin/sh\nexit 1\n' >"$T/bin/evtest"; fi
    chmod +x "$T/bin/bluetoothctl" "$T/bin/evtest"; : >"$T/bt.log"
    export PATH="$T/bin:$PATH"
}

t_idle_worker_disconnects_after_a_full_timeout() {
    fake_bins idle; idle_timeout=1; mkdir -p "$sys_input/event1"
    idle_worker "$A" event1 & local w=$!
    sleep 2.5; kill "$w" 2>/dev/null; wait "$w" 2>/dev/null
    check "an idle Bluetooth controller is disconnected after the timeout" 1 "$(grep -c "^disconnect $A" "$T/bt.log" | awk '{print ($1 > 0)}')"
}

t_idle_worker_never_disconnects_when_evtest_fails() {
    fake_bins fail; idle_timeout=3; mkdir -p "$sys_input/event1"
    idle_worker "$A" event1 & local w=$!
    sleep 1.5; kill "$w" 2>/dev/null; wait "$w" 2>/dev/null
    check "evtest failing at once does not disconnect the controller" 0 "$(grep -c disconnect "$T/bt.log")"
}

t_idle_workers_only_for_bluetooth() {
    printf '%s\t1\t0005:057E:2009.0001\tevent1\n%s\t2\t0003:057E:2009.0002\tevent2\njoycond:event3\t3\t-\tevent3\n' "$A" "$B" >"$slots_file"
    : >"$T/workers.log"
    idle_worker() { echo "$1" >>"$T/workers.log"; }
    start_idle_workers; wait
    check "only the Bluetooth controller gets an idle worker" "$A" "$(tr '\n' ' ' <"$T/workers.log" | sed 's/ $//')"
}

t_switchpro_helper_found_next_to_the_install() {
    local i=0 layout pre bin helper
    for layout in "local/bin:local/libexec/joystickmanager-switchpro-leds" "bin:lib/joystickmanager/switchpro-leds" "bin:libexec/joystickmanager-switchpro-leds"; do
        i=$((i + 1)); pre="$T/prefix$i"; bin="$pre/${layout%%:*}"; helper="$pre/${layout#*:}"
        mkdir -p "$bin" "$(dirname "$helper")"; cp "$here/joystickmanager.sh" "$bin/"; printf '#!/bin/sh\n' >"$helper"; chmod +x "$helper"
        # shellcheck source=/dev/null
        JOYMANAGER_SWITCHPRO_HELPER='' source "$bin/joystickmanager.sh"
        check "helper found for the ${layout%%:*} layout" "$(realpath "$helper")" "$(realpath -m "${switchpro_helper:-/none}")"
    done
    JOYMANAGER_SWITCHPRO_HELPER=/custom/helper source "$here/joystickmanager.sh"
    check "JOYMANAGER_SWITCHPRO_HELPER overrides the search" /custom/helper "$switchpro_helper"
}

# jq-free JSON reader for the state tests: jget FILE PYTHON-EXPRESSION (d = parsed document)
jget() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$1" "$2"; }

t_state_json_describes_controllers() {
    write_led() { :; }; start_idle_workers() { :; }; now_s() { printf '1000\n'; }
    connect event1 "$A"                                   # Pro Controller over Bluetooth
    local usb="$T/dev/0003:057E:2009.0016"                 # Pro Controller over USB
    mkdir -p "$usb" "$sys_input/event2"; printf '%s\n' "$B" >"$usb/uniq"; printf 'Nintendo Co., Ltd. Pro Controller\n' >"$usb/name"
    ln -sfn "$usb" "$sys_input/event2/device"; register_event event2
    connect event3 "$C" "Nintendo Switch Combined Joy-Cons" # joycond virtual pair
    sys_power="$T/power"; local b="$T/power/nintendo_switch_controller_battery_a"; mkdir -p "$b"
    ln -sfn "$T/dev/0005:057E:2009.$A" "$b/device"; printf 'Charging\n' >"$b/status"; printf '55\n' >"$b/capacity"
    update_batteries_once
    local f="$runtime_dir/state.json"
    jget "$f" 'd["format"], d["version"]' >/dev/null 2>&1; check "state.json is valid JSON" 0 $?
    check "format and version" "('ujm-state', 1)" "$(jget "$f" 'd["format"], d["version"]')"
    check "controllers are listed by player" "[1, 2, 3]" "$(jget "$f" '[c["player"] for c in d["controllers"]]')"
    check "transports" "['bluetooth', 'usb', 'virtual']" "$(jget "$f" '[c["transport"] for c in d["controllers"]]')"
    check "families from the profile table" "['switch-pro', 'switch-pro', 'joycon-combined']" "$(jget "$f" '[c["family"] for c in d["controllers"]]')"
    check "player LED masks" "[1, 2, 4]" "$(jget "$f" '[c["player_led_mask"] for c in d["controllers"]]')"
    check "battery of the Bluetooth controller" "{'percent': 55, 'status': 'Charging', 'level': 'normal'}" "$(jget "$f" 'd["controllers"][0]["battery"]')"
    check "no battery reading means null" "None" "$(jget "$f" 'd["controllers"][1]["battery"]')"
    check "the service settings are included" "{'led_refresh': '10', 'idle_timeout': 300, 'experimental': False}" "$(jget "$f" 'd["service"]')"
    check "the file is readable by everyone (the interface runs as a user)" 644 "$(stat -c %a "$f")"
}

t_state_json_escapes_and_is_only_rewritten_on_change() {
    write_led() { :; }; start_idle_workers() { :; }; now_s() { printf '%s\n' "$NOW"; }
    experimental=1; NOW=1000
    fake_input event1 '8BitDo "Pro" 2 \ edition' 2dc8 6003 js
    register_event event1; update_batteries_once
    local f="$runtime_dir/state.json" ino
    check "quotes and backslashes in names are escaped" '8BitDo "Pro" 2 \ edition' "$(jget "$f" 'd["controllers"][0]["name"]')"
    ino=$(stat -c %i "$f"); NOW=1010; update_batteries_once
    check "nothing changed: the file is not rewritten (same inode, same timestamp)" "$ino 1000" "$(stat -c %i "$f") $(jget "$f" 'd["updated"]')"
    disconnect event1; NOW=1020; update_batteries_once
    check "a disconnection rewrites it" "[] 1020" "$(jget "$f" 'd["controllers"]') $(jget "$f" 'd["updated"]')"
}

t_combined_pair_lights_the_right_joycon_home_led() {
    sys_leds="$T/leds"; start_idle_workers() { :; }
    local mac n pre
    for side in L R; do
        [ "$side" = L ] && mac=$C || mac=$D
        pre="0005:057E:2009.$mac"   # the prefix connect() creates
        for n in 1 2 3 4; do mkdir -p "$sys_leds/$pre:green:player-$n"; : >"$sys_leds/$pre:green:player-$n/brightness"; done
        connect "event$([ "$side" = L ] && echo 1 || echo 2)" "$mac" "Joy-Con ($side)"
    done
    # only the right Joy-Con has a HOME LED (as hid-nintendo exposes it), off at connection
    pre="0005:057E:2009.$D"; mkdir -p "$sys_leds/$pre:blue:player-5"; printf '0\n' >"$sys_leds/$pre:blue:player-5/brightness"; printf '15\n' >"$sys_leds/$pre:blue:player-5/max_brightness"
    connect event3 "$A" "Nintendo Switch Combined Joy-Cons"
    check "combined pair: the right Joy-Con HOME LED is turned on" 15 "$(cat "$sys_leds/$pre:blue:player-5/brightness")"
    check "combined pair: the left Joy-Con gets no HOME LED file" 0 "$(find "$sys_leds" -name "*2009.$C:blue*" | wc -l)"
}

# ---- command channel -------------------------------------------------------------------------
led_fixture() { # PREFIX [home]: fake player LEDs (and the HOME LED) of one controller
    local p=$1 n d
    for n in 1 2 3 4; do d="$sys_leds/$p:green:player-$n"; mkdir -p "$d"; printf '0\n' >"$d/brightness"; done
    if [ "${2:-}" = home ]; then d="$sys_leds/$p:blue:player-5"; mkdir -p "$d"; printf '0\n' >"$d/brightness"; printf '15\n' >"$d/max_brightness"; fi
}
leds_of() { local n out=''; for n in 1 2 3 4; do out+="$(cat "$sys_leds/$1:green:player-$n/brightness") "; done; printf '%s\n' "${out% }"; }
home_of() { cat "$sys_leds/$1:blue:player-5/brightness"; }
req() { handle_command "$(printf 'REQ\t%s\t%s\t%s\t%s' "$1" "$2" "${3:-}" "${4:-}")" 2>/dev/null; }   # reqid command arg1 arg2
ack() { tr '\t' '|' <"$ack_dir/$1" 2>/dev/null; }
cmd_setup() { sys_leds="$T/leds"; sys_power="$T/power"; mkdir -p "$sys_leds" "$sys_power"; start_idle_workers() { :; }; now_s() { printf '1000\n'; }; }
charging_battery() { local b="$T/power/nintendo_switch_controller_battery_a"; mkdir -p "$b"; ln -sfn "$T/dev/0005:057E:2009.$1" "$b/device"; printf 'Charging\n' >"$b/status"; printf '55\n' >"$b/capacity"; }

t_command_player_leds_survive_refresh_and_battery_blinking() {
    cmd_setup; local pre="0005:057E:2009.$A"; led_fixture "$pre"
    connect event1 "$A"; charging_battery "$A"
    check "starts with the slot pattern (LED 1)" "1 0 0 0" "$(leds_of "$pre")"
    req aaaaaaa01 player_leds "$A" 12
    check "the request is acknowledged" ok "$(ack aaaaaaa01)"
    check "the pattern is applied at once" "0 0 1 1" "$(leds_of "$pre")"
    led_refresh=0; update_batteries_once; now_s() { printf '1001\n'; }; update_batteries_once
    check "a refresh and the charging blink leave a manual pattern alone" "0 0 1 1" "$(leds_of "$pre")"
    local f="$runtime_dir/state.json"
    check "state.json shows the manual pattern" "(12, True)" "$(jget "$f" '(d["controllers"][0]["player_led_mask"], d["controllers"][0]["player_led_manual"])')"
    req aaaaaaa02 player_leds "$A" 255
    check "255 goes back to the automatic pattern" "1 0 0 0" "$(leds_of "$pre")"
    update_batteries_once
    check "state.json is automatic again" "(1, False)" "$(jget "$f" '(d["controllers"][0]["player_led_mask"], d["controllers"][0]["player_led_manual"])')"
}

t_command_player_leds_manual_pattern_is_forgotten_when_the_controller_leaves() {
    cmd_setup; local pre="0005:057E:2009.$A"; led_fixture "$pre"
    connect event1 "$A"; req aaaaaaa03 player_leds "$A" 5
    disconnect event1; cleanup_missing
    check "the manual pattern is dropped with the connection" "" "${led_manual[$A]:-}"
    connect event1 "$A"
    check "a reconnection gets the automatic pattern again" "1 0 0 0" "$(leds_of "$pre")"
}

t_command_player_leds_refuses_what_it_cannot_do() {
    cmd_setup; local pre="0005:057E:2009.$A"; led_fixture "$pre"
    connect event1 "$A"
    connect event2 "$B"            # no LED files for this one
    connect event3 "$C" "Nintendo Switch Combined Joy-Cons"
    req bbbbbbb01 player_leds "$A" 16;   check "mask 16 is refused" "error|mask must be 0-15, or 255 to go back to the automatic pattern" "$(ack bbbbbbb01)"
    req bbbbbbb02 player_leds "$A" abc;  check "a non-numeric mask is refused" "error" "$(ack bbbbbbb02 | cut -d'|' -f1)"
    req bbbbbbb03 player_leds "$A" "-1"; check "a negative mask is refused" "error" "$(ack bbbbbbb03 | cut -d'|' -f1)"
    req bbbbbbb04 player_leds "ZZ:ZZ" 3; check "an unknown controller is refused" "error|no connected controller with that id" "$(ack bbbbbbb04)"
    req bbbbbbb05 player_leds "$B" 3;    check "a controller without player LEDs is refused" "error|this controller has no player LEDs the service can write" "$(ack bbbbbbb05)"
    req bbbbbbb06 player_leds "joycond:event3" 3; check "the joycond pair is refused" "error" "$(ack bbbbbbb06 | cut -d'|' -f1)"
    check "the LEDs were not touched by any refused request" "1 0 0 0" "$(leds_of "$pre")"
    check "nothing is remembered from refused requests" "" "${led_manual[*]:-}"
}

t_command_ignores_malformed_requests() {
    cmd_setup
    req "../../etc" idle_timeout 120; req short idle_timeout 120; handle_command "garbage line" 2>/dev/null
    handle_command "$(printf 'XXX\tccccccc01\tidle_timeout\t120')" 2>/dev/null
    check "no answer file for a bad id, a short id or another tag" 0 "$(ls "$ack_dir" 2>/dev/null | wc -l)"
    check "and nothing was changed" 300 "$idle_timeout"
    req ccccccc02 reboot now;  check "an unknown command is refused" "error|unknown command" "$(ack ccccccc02)"
    req ccccccc03 idle_timeout "120; touch $T/pwned"; check "an argument with shell syntax is just refused" "error" "$(ack ccccccc03 | cut -d'|' -f1)"
    check "and was not executed" no "$([ -e "$T/pwned" ] && echo yes || echo no)"
}

t_command_home_led_can_be_turned_off_and_stays_off() {
    cmd_setup; local pre="0005:057E:2009.$A"; led_fixture "$pre" home
    connect event1 "$A"; charging_battery "$A"
    check "the HOME LED is on after the connection" 15 "$(home_of "$pre")"
    req ddddddd01 home_led "$A" off; check "off is acknowledged" ok "$(ack ddddddd01)"
    check "the HOME LED is off" 0 "$(home_of "$pre")"
    led_refresh=0; update_batteries_once
    check "a refresh does not turn it on again" 0 "$(home_of "$pre")"
    check "state.json says so" off "$(jget "$runtime_dir/state.json" 'd["controllers"][0]["home_led"]')"
    req ddddddd02 home_led "$A" on; check "on brings it back to full" 15 "$(home_of "$pre")"
    update_batteries_once; check "state.json says on" on "$(jget "$runtime_dir/state.json" 'd["controllers"][0]["home_led"]')"
}

t_command_home_led_refuses_controllers_without_one() {
    cmd_setup; led_fixture "0005:057E:2009.$A"; connect event1 "$A"; update_batteries_once
    req eeeeeee01 home_led "$A" on;  check "no HOME LED: refused" "error|this controller has no HOME LED" "$(ack eeeeeee01)"
    req eeeeeee02 home_led "$A" maybe; check "a value other than on/off is refused" "error|the value must be on or off" "$(ack eeeeeee02)"
    check "state.json reports unsupported" unsupported "$(jget "$runtime_dir/state.json" 'd["controllers"][0]["home_led"]')"
}

t_command_idle_timeout_is_validated_applied_and_kept() {
    cmd_setup; local n=0
    req fffffff01 idle_timeout 120; check "120 s is accepted" ok "$(ack fffffff01)"
    check "it is applied" 120 "$idle_timeout"
    check "it is written to the settings file" "idle_timeout=120" "$(cat "$settings_file")"
    update_batteries_once
    check "state.json shows the new value" 120 "$(jget "$runtime_dir/state.json" 'd["service"]["idle_timeout"]')"
    local bad
    for bad in 30 59 86401 99999999999999999999 abc -5 ""; do
        req "fffffff0$((++n))" idle_timeout "$bad"
    done
    check "values outside 0 or 60-86400 and non-numbers are refused" 120 "$idle_timeout"
    check "and the file is unchanged" "idle_timeout=120" "$(cat "$settings_file")"
    idle_timeout=300; load_settings
    check "after a restart the saved value wins over the environment" 120 "$idle_timeout"
    printf 'idle_timeout=5\nsomething=else\n' >"$settings_file"; idle_timeout=300; load_settings
    check "an invalid saved value is ignored" 300 "$idle_timeout"
    state_dir=/proc/nonexistent; settings_file="$state_dir/settings"; idle_timeout=300
    req fffffff20 idle_timeout 300
    check "an unwritable state directory refuses the change" "error|the setting could not be saved" "$(ack fffffff20)"
    check "and does not apply it" 300 "$idle_timeout"
}

t_command_idle_timeout_zero_means_never_and_stops_the_workers() {
    cmd_setup; unset -f start_idle_workers; source "$here/joystickmanager.sh"   # the real start_idle_workers
    connect event1 "$A"
    req ggggggg01 idle_timeout 0; check "0 is accepted" ok "$(ack ggggggg01)"
    ls "$runtime_dir"/idle.*.pid >/dev/null 2>&1; check "no idle worker is started when the timeout is 0" 2 $?
    check "state.json shows 0" 0 "$(update_batteries_once; jget "$runtime_dir/state.json" 'd["service"]["idle_timeout"]')"
    ls "$runtime_dir"/idle.*.pid >/dev/null 2>&1; check "still none after a cycle" 2 $?
}

t_command_idle_timeout_stops_a_running_worker_and_its_pipeline() {
    cmd_setup
    bash -c 'sleep 300 & wait' & local worker=$!
    sleep 0.3; local child; child=$(pgrep -P "$worker" | head -1)
    printf '%s\n' "$worker" >"$runtime_dir/idle.1.pid"
    req hhhhhhh01 idle_timeout 120
    sleep 0.3
    kill -0 "$worker" 2>/dev/null; check "the worker is stopped" 1 $?
    kill -0 "$child" 2>/dev/null; check "and so is the evtest pipeline it started (not left behind)" 1 $?
    check "its pid file is gone" no "$([ -e "$runtime_dir/idle.1.pid" ] && echo yes || echo no)"
}

t_command_channel_through_the_fifo_and_the_real_loop() {
    local rt="$T/rt2" st="$T/state2" i ms t0 t1
    mkdir -p "$rt" "$T/leds" "$T/power"
    JOYMANAGER_RUNTIME_DIR=$rt JOYMANAGER_STATE_DIR=$st JOYMANAGER_SYS_INPUT="$T/input" JOYMANAGER_SYS_LEDS="$T/leds" \
        JOYMANAGER_SYS_POWER="$T/power" JOYMANAGER_PROFILES="$here/controllers.tsv" setsid bash "$here/joystickmanager.sh" 2>/dev/null &
    local pid=$!
    for i in $(seq 40); do [ -p "$rt/command.fifo" ] && [ -e "$rt/state.json" ] && break; sleep 0.1; done
    check "the service creates its FIFO, readable only by its owner" 600 "$(stat -c %a "$rt/command.fifo" 2>/dev/null)"
    t0=$(date +%s%N)
    printf 'REQ\tiiiiiii01\tidle_timeout\t120\t\n' >"$rt/command.fifo"
    for i in $(seq 30); do [ -e "$rt/ack/iiiiiii01" ] && break; sleep 0.05; done
    t1=$(date +%s%N); ms=$(( (t1 - t0) / 1000000 ))
    check "the answer is ok" ok "$(cat "$rt/ack/iiiiiii01" 2>/dev/null)"
    check "the answer comes at once, not at the next 2 s cycle (took ${ms} ms)" yes "$([ "$ms" -lt 1500 ] && echo yes || echo no)"
    check "the ack directory is private" 700 "$(stat -c %a "$rt/ack" 2>/dev/null)"
    for i in $(seq 30); do [ "$(jget "$rt/state.json" 'd["service"]["idle_timeout"]' 2>/dev/null)" = 120 ] && break; sleep 0.1; done
    check "state.json follows in the next cycle" 120 "$(jget "$rt/state.json" 'd["service"]["idle_timeout"]')"
    check "the setting is saved" "idle_timeout=120" "$(cat "$st/settings" 2>/dev/null)"
    printf 'REQ\tiiiiiii02\thome_led\tnobody\ton\n' >"$rt/command.fifo"
    for i in $(seq 30); do [ -e "$rt/ack/iiiiiii02" ] && break; sleep 0.05; done
    check "an unknown controller is refused over the FIFO too" "error" "$(cut -f1 "$rt/ack/iiiiiii02" 2>/dev/null)"
    kill -TERM "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; sleep 0.5
    check "the FIFO is removed when the service stops" no "$([ -e "$rt/command.fifo" ] && echo yes || echo no)"
    check "nothing it started is left running (no stray udev monitor)" 0 "$(pgrep -s "$pid" 2>/dev/null | wc -l)"
    kill -TERM -- "-$pid" 2>/dev/null || true
}

t_battery_is_found_when_the_id_is_not_above_the_battery_device() {
    # Real kernels: the battery hangs off the HID device and "uniq" is on the input device below it.
    cmd_setup; connect event1 "$A"
    local b="$T/power/sony_controller_battery_x" hid="$T/hidonly/0005:057E:2009.$A"
    mkdir -p "$b" "$hid"; ln -sfn "$hid" "$b/device"; printf 'Discharging\n' >"$b/status"; printf '80\n' >"$b/capacity"
    update_batteries_once
    check "the battery is read through the HID prefix" "{'percent': 80, 'status': 'Discharging', 'level': 'normal'}" "$(jget "$runtime_dir/state.json" 'd["controllers"][0]["battery"]')"
}

t_battery_without_capacity_reports_the_status_only() {
    cmd_setup; connect event1 "$A"   # a Pro Controller on a cable: Charging, no capacity file
    local b="$T/power/nintendo_switch_controller_battery_x" hid="$T/hidonly/0005:057E:2009.$A"
    mkdir -p "$b" "$hid"; ln -sfn "$hid" "$b/device"; printf 'Charging\n' >"$b/status"
    update_batteries_once
    check "no percent, but the status" "{'percent': None, 'status': 'Charging', 'level': 'normal'}" "$(jget "$runtime_dir/state.json" 'd["controllers"][0]["battery"]')"
}

t_scan_does_not_resolve_known_controllers_again() {
    cmd_setup; plug event5 'Pro Controller' "$A"
    scan_existing                       # registers it (the first scan also clears the caches)
    : >"$T/calls"   # a file, not a variable: the functions run in command substitutions
    controller_id() { echo x >>"$T/calls"; return 1; }; controller_parent() { echo x >>"$T/calls"; return 1; }
    scan_existing; scan_existing
    check "a registered controller is not resolved again each cycle" 0 "$(wc -l <"$T/calls")"
    unset -f controller_id controller_parent
}

t_scan_registers_a_registered_node_that_was_replaced() {
    cmd_setup; plug event5 'Pro Controller' "$A"
    scan_existing; scan_existing
    rm -rf "${sys_input:?}/event5"; plug event5 'Pro Controller' "$B"
    scan_existing
    check "event5 re-created as another controller is picked up" 2 "$(slot_of "$B")"
}

t_player_leds_capability_follows_the_leds_the_controller_has() {
    cmd_setup
    experimental=1   # the Xbox profiles are experimental
    led_fixture "0005:057E:2009.$A" home                 # Switch controller: numbering LEDs and a HOME LED
    local hid="0005:045E:02FD.0001" d="$sys_leds/0005:045E:02FD.0001:blue:player-5"
    mkdir -p "$d"; printf '0\n' >"$d/brightness"; printf '15\n' >"$d/max_brightness"   # an Xbox-like controller: HOME LED only
    connect event1 "$A"
    mkdir -p "$T/dev/$hid"; printf '%s\n' "$B" >"$T/dev/$hid/uniq"; printf 'Xbox Wireless Controller\n' >"$T/dev/$hid/name"
    mkdir -p "$sys_input/event2"; ln -sfn "$T/dev/$hid" "$sys_input/event2/device"; register_event event2
    update_batteries_once
    local f="$runtime_dir/state.json"
    check "a controller with numbering LEDs says so" True "$(jget "$f" 'd["controllers"][0]["player_leds"]')"
    check "a HOME-LED-only controller has no player LEDs" False "$(jget "$f" 'd["controllers"][1]["player_leds"]')"
    req iiiiiii10 player_leds "$B" 3
    check "player LEDs are refused on it" "error|this controller has no player LEDs the service can write" "$(ack iiiiiii10)"
    check "while its HOME LED is still reported" "['on', 'on']" "$(jget "$f" '[c["home_led"] for c in d["controllers"]]')"
}

t_nintendo_leds_wait_until_the_controller_has_settled() {
    cmd_setup; led_settle=6; led_refresh=off
    local pre="0005:057E:2009.$A"; led_fixture "$pre" home
    connect event1 "$A"; charging_battery "$A"; printf 'Discharging\n' >"$T/power/nintendo_switch_controller_battery_a/status"   # no charging blink
    check "nothing is written when a Nintendo controller registers" "0 0 0 0 0" "$(leds_of "$pre") $(home_of "$pre")"
    now_s() { printf '1000\n'; }; update_batteries_once
    now_s() { printf '1005\n'; }; update_batteries_once
    check "nor during its first 5 s" "0 0 0 0 0" "$(leds_of "$pre") $(home_of "$pre")"
    now_s() { printf '1006\n'; }; update_batteries_once
    check "after 6 s the pattern and the HOME LED are written" "1 0 0 0 15" "$(leds_of "$pre") $(home_of "$pre")"
    printf '0\n' >"$sys_leds/$pre:blue:player-5/brightness"
    now_s() { printf '1030\n'; }; update_batteries_once
    check "with LED_REFRESH=off they are written once and not again" 0 "$(home_of "$pre")"
}

t_nintendo_leds_with_a_periodic_refresh_also_wait() {
    cmd_setup; led_settle=6; led_refresh=10
    local pre="0005:057E:2009.$A"; led_fixture "$pre" home
    connect event1 "$A"; charging_battery "$A"; printf 'Discharging\n' >"$T/power/nintendo_switch_controller_battery_a/status"
    now_s() { printf '2000\n'; }; update_batteries_once
    check "no LED write in the first cycle" "0 0 0 0 0" "$(leds_of "$pre") $(home_of "$pre")"
    now_s() { printf '2007\n'; }; update_batteries_once
    check "the first write comes after the settle time" "1 0 0 0 15" "$(leds_of "$pre") $(home_of "$pre")"
}

t_other_controllers_still_get_their_leds_at_once() {
    cmd_setup; led_settle=6; led_refresh=off
    local pre="0005:054C:0268.$A" d="$T/dev/0005:054C:0268.$A" n
    for n in 1 2 3 4; do mkdir -p "$sys_leds/$pre::sony$n"; printf '0\n' >"$sys_leds/$pre::sony$n/brightness"; done
    mkdir -p "$d" "$sys_input/event1"; printf '%s\n' "$A" >"$d/uniq"; printf 'PLAYSTATION(R)3 Controller\n' >"$d/name"; ln -sfn "$d" "$sys_input/event1/device"
    register_event event1
    check "a DualShock 3 is written on registration, as before" "1000" "$(for n in 1 2 3 4; do printf '%s' "$(cat "$sys_leds/$pre::sony$n/brightness")"; done)"
}

t_home_led_is_lit_once_per_connection_and_not_kept_alive() {
    # The controller keeps the HOME LED lit for ~15 s per command; keeping it lit would cost commands
    # that drop the link, so the periodic refresh must not send it again.
    cmd_setup; led_refresh=10
    local pre="0005:057E:2009.$A"; led_fixture "$pre" home
    connect event1 "$A"; charging_battery "$A"; printf 'Discharging\n' >"$T/power/nintendo_switch_controller_battery_a/status"
    now_s() { printf '1000\n'; }; update_batteries_once
    check "the HOME LED is lit when the controller connects" 15 "$(home_of "$pre")"
    printf '0\n' >"$sys_leds/$pre:blue:player-5/brightness"        # what the controller did on its own after ~15 s
    printf '1\n' >"$sys_leds/$pre:green:player-2/brightness"
    now_s() { printf '1010\n'; }; update_batteries_once
    check "a periodic refresh rewrites the player LEDs" "1 0 0 0" "$(leds_of "$pre")"
    check "but does not send the HOME LED again" 0 "$(home_of "$pre")"
    req hhhhhhh10 home_led "$A" on
    check "SetHomeLed still lights it on request" 15 "$(home_of "$pre")"
}

t_udev_rule_for_pro_controller() {
    local rule="$here/udev/99-joystickmanager-procontroller-charge-only.rules"
    [ -r "$rule" ]; check "udev rule exists" 0 $?
    check "rule targets only the Pro Controller 057e:2009" 1 "$(grep -c 'idVendor}=="057e", ATTR{idProduct}=="2009"' "$rule")"
    check "rule only deauthorizes on add" 1 "$(grep -c '^ACTION=="add".*ATTR{authorized}="0"' "$rule")"
    if command -v udevadm >/dev/null 2>&1 && udevadm verify --help >/dev/null 2>&1; then
        udevadm verify "$rule" >/dev/null 2>&1; check "udevadm verify accepts the rule" 0 $?
    fi
}

# plug <event> <name> [mac]: creates an input node without registering it (the periodic scan finds it)
plug() {
    local ev=$1 name=$2 mac=${3:-} d="$T/dev/plug.$1"
    [ -z "$mac" ] || d="$T/dev/0005:057E:2009.$mac"
    mkdir -p "$d" "$sys_input/$ev"
    printf '%s\n' "$name" >"$d/name"
    [ -z "$mac" ] || printf '%s\n' "$mac" >"$d/uniq"
    ln -sfn "$d" "$sys_input/$ev/device"
}

t_scan_does_not_rematch_nodes_that_are_not_controllers() {
    plug event9 'AT Translated Set 2 keyboard'; plug event10 'Logitech USB Mouse'
    scan_existing
    local calls=0
    profile_for_event() { calls=$((calls+1)); return 1; }
    scan_existing; scan_existing
    check "keyboard and mouse are not matched against the table again" 0 "$calls"
}

t_scan_registers_a_controller_plugged_after_other_nodes() {
    plug event9 'AT Translated Set 2 keyboard'
    scan_existing
    plug event11 'Pro Controller' $A
    scan_existing
    check "a controller appearing after the keyboard was skipped still gets a slot" 1 "$(slot_of $A)"
}

t_scan_registers_a_recreated_node() {
    plug event9 'Some Keyboard'
    scan_existing
    rm -rf "${sys_input:?}/event9"
    plug event9 'Pro Controller' $B
    scan_existing
    check "event9 re-created as a controller is picked up" 1 "$(slot_of $B)"
}

t_scan_rechecks_ignored_nodes_every_so_often() {
    plug event9 'Late Name'
    scan_existing
    mv "$T/dev/plug.event9" "$T/dev/0005:057E:2009.$C"; ln -sfn "$T/dev/0005:057E:2009.$C" "$sys_input/event9/device"
    printf 'Pro Controller\n' >"$T/dev/0005:057E:2009.$C/name"; printf '%s\n' "$C" >"$T/dev/0005:057E:2009.$C/uniq"
    local i
    for ((i = 0; i <= rescan_every; i++)); do scan_existing; done
    check "a node whose name changed in place is found by the periodic full rescan" 1 "$(slot_of $C)"
}

t_idle_cycle_does_not_spawn_per_node_processes() {
    local i
    for i in $(seq 20 49); do plug "event$i" "Device $i"; done
    scan_existing
    # a cycle with nothing new must not read the profile table at all
    local reads=0
    profiles_path() { reads=$((reads+1)); return 1; }
    scan_existing
    check "second scan of 30 non-controller nodes reads no profile table" 0 "$reads"
}

for t in t_arrival_order t_freed_slot_goes_to_next_arrival \
         t_reconnect_with_stale_row_not_yet_cleaned t_same_controller_still_present_keeps_slot \
         t_pro_controller_over_usb_is_registered t_connectable_is_reasserted \
         t_validated_profiles_always_active t_experimental_profiles_need_flag \
         t_vendor_rule_requires_js t_extra_dualshock4_nodes_ignored \
         t_non_hid_controller_gets_slot t_without_table_uses_fixed_list t_doctor_lists_controllers \
         t_leds_not_rewritten_within_window t_refresh_zero_keeps_old_behavior \
         t_battery_change_writes_immediately t_refresh_off_applies_once_then_only_changes \
         t_refresh_off_new_connection_gets_leds t_invalid_led_refresh_falls_back_to_10 \
         t_idle_worker_disconnects_after_a_full_timeout t_idle_worker_never_disconnects_when_evtest_fails \
         t_idle_workers_only_for_bluetooth t_switchpro_helper_found_next_to_the_install \
         t_state_json_describes_controllers t_state_json_escapes_and_is_only_rewritten_on_change \
         t_combined_pair_lights_the_right_joycon_home_led \
         t_scan_does_not_rematch_nodes_that_are_not_controllers t_scan_registers_a_controller_plugged_after_other_nodes \
         t_scan_registers_a_recreated_node t_scan_rechecks_ignored_nodes_every_so_often \
         t_idle_cycle_does_not_spawn_per_node_processes \
         t_command_player_leds_survive_refresh_and_battery_blinking t_command_player_leds_manual_pattern_is_forgotten_when_the_controller_leaves \
         t_command_player_leds_refuses_what_it_cannot_do t_command_ignores_malformed_requests \
         t_command_home_led_can_be_turned_off_and_stays_off t_command_home_led_refuses_controllers_without_one \
         t_command_idle_timeout_is_validated_applied_and_kept t_command_idle_timeout_zero_means_never_and_stops_the_workers \
         t_command_idle_timeout_stops_a_running_worker_and_its_pipeline t_command_channel_through_the_fifo_and_the_real_loop \
         t_battery_is_found_when_the_id_is_not_above_the_battery_device t_battery_without_capacity_reports_the_status_only \
         t_scan_does_not_resolve_known_controllers_again t_scan_registers_a_registered_node_that_was_replaced \
         t_player_leds_capability_follows_the_leds_the_controller_has \
         t_nintendo_leds_wait_until_the_controller_has_settled t_nintendo_leds_with_a_periodic_refresh_also_wait \
         t_other_controllers_still_get_their_leds_at_once \
         t_home_led_is_lit_once_per_connection_and_not_kept_alive \
         t_udev_rule_for_pro_controller; do
    printf '# %s\n' "$t"; run "$t"
done
printf '\n%s failure(s)\n' "$fails"
exit "$fails"
