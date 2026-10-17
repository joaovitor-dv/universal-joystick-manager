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
    check "the service settings are included" "{'led_refresh': '10', 'idle_timeout': 1800, 'experimental': False}" "$(jget "$f" 'd["service"]')"
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
         t_idle_cycle_does_not_spawn_per_node_processes t_udev_rule_for_pro_controller; do
    printf '# %s\n' "$t"; run "$t"
done
printf '\n%s failure(s)\n' "$fails"
exit "$fails"
