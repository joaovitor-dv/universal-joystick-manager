# Hardware checklist

One sitting, in this order. Each step says what to do, what to expect, and what to keep. Everything that is not on a real controller is already covered by `tools/check.sh`; these are the checks that **cannot** be automated.

The same list is what a volunteer needs to validate a controller family (see [CONTRIBUTING.md](../CONTRIBUTING.md)): do steps 0, 1 and 5 (plus the step for your model), and send the report.

Needed: the controllers you want to test, `sudo`, and about an hour (step 2 alone takes 30 minutes).

## 0. Start from the code you mean to test

```bash
sudo ./install.sh                  # installs this checkout's service; add --with-bridge for step 6
sudo systemctl restart joystickmanager
tools/collect-report.sh            # baseline: writes ~/ujm-report-DATE.txt
```

In the report, **"installed script" and "repository script" must show the same hash.** If they differ, you are testing the installed copy, not the checkout. Keep the baseline report.

Controllers can stay off until step 1.

## 1. Service cost with controllers connected

Connect every controller you have (Bluetooth and USB), wait a minute, then:

```bash
tools/measure-service.sh 60
```

Expect a few percent of one core at most. With no controllers the service uses about 0.4%; with controllers the cost has never been measured, so **the number is the result**: write it down with the number of controllers it printed.

## 2. Soak: 30 minutes, Pro Controller and Joy-Con R

With the idle timeout at its default of 300 s (`systemctl show joystickmanager -p Environment`), keep the Pro Controller and the Joy-Con R connected and use them now and then for 30 minutes.

```bash
journalctl -u joystickmanager -n 200 --no-pager | grep -iE "error|exceeded|fail" || echo "no errors"
tools/measure-service.sh 60
```

Expect: no controller dropped by itself, LEDs unchanged, no "exceeded max attempts" in the journal, the same CPU as step 1. Keep: the journal output and the number.

## 3. `JOYMANAGER_LED_REFRESH=off`

```bash
sudo systemctl edit joystickmanager      # add the two lines below, save
```
```ini
[Service]
Environment=JOYMANAGER_LED_REFRESH=off
```
```bash
sudo systemctl restart joystickmanager
```

1. Turn on the Pro Controller: LED 1 appears. Wait two minutes: it must **not** flash or change (nothing is rewritten).
2. Plug the USB cable in and out: the player LED comes back once and stays.
3. Repeat with `joycond` running (`systemctl is-active joycond`), including a Joy-Con pair.

Expect: LEDs stay correct without the periodic rewrite. If the firmware loses the LEDs after some time, say after how long: that is the answer. Remove the drop-in afterwards (`sudo systemctl revert joystickmanager`) and restart.

## 4. Joy-Con R HOME LED

Check it three ways, each time looking at the controller and at the kernel value:

```bash
for d in /sys/class/leds/*:blue:player-5; do echo "$d $(cat $d/brightness)/$(cat $d/max_brightness)"; done
```

1. **Joy-Con R alone:** the HOME button light should be on (value 15, maximum).
2. **A `joycond` pair:** the right Joy-Con's light should also be on (this was fixed after an earlier gap: the pair never lit it).
3. **After turning it off and on again.**

Expect: light on and value 15 in all three. Say whether the light's physical effect matches the sysfs value (an old note claimed they could disagree; the cause was probably the LED write storm fixed in v0.6.1).

## 5. `state.json`

```bash
python3 -m json.tool /run/joystickmanager/state.json
```

Expect one entry per connected controller with `player`, `transport`, `battery` and `player_led_mask` as in [state.md](state.md); the file changes when you connect or disconnect one, and `updated` does not move while nothing changes. Keep the file (the report masks the addresses).

## 6. Idle power-off

```bash
sudo systemctl edit joystickmanager      # use a short timeout for the test
```
```ini
[Service]
Environment=JOYMANAGER_IDLE_TIMEOUT=120
```
```bash
sudo systemctl restart joystickmanager
```

1. Pro Controller on Bluetooth, untouched for 2 minutes: it must disconnect (and reconnect with HOME).
2. Same, but press a button every minute: it must stay connected.
3. Pro Controller on USB, untouched for 3 minutes: it must **not** be disconnected.

Remove the drop-in afterwards (`sudo systemctl revert joystickmanager`) and restart.

These three scenarios are about the idle power-off. They are **not** the "original tests 3, 4 and 6" that gate returning the default timeout to 300 s: those are step 8.

## 7. The D-Bus bridge on the real system bus

```bash
sudo ./install.sh --with-bridge
busctl call org.ujm.Manager1 /org/ujm/Manager1 org.ujm.Manager1 GetSnapshotJson
busctl call org.ujm.Manager1 /org/ujm/Manager1 org.ujm.Manager1 SetControllerAlias ss "<id from the snapshot>" "Sala"
```

Expect: the first call starts the bridge by itself (`systemctl is-active ujm-bridge` is `active` right after, `inactive` about 30 seconds after the last call) and returns your controllers as JSON. The alias call should **not** ask for a password in your desktop session (`org.ujm.manager.set-alias` is allowed for the active session); from an SSH session or a user without a session it should ask or be refused.

Then the interface and Bluetooth actions:

```bash
python3 gui/ujm_gui.py            # the pill at the top must say "D-Bus bridge", not "state.json, read-only"
busctl call org.ujm.Manager1 /org/ujm/Manager1 org.ujm.Manager1 DisconnectBluetooth s "<id>"
busctl call org.ujm.Manager1 /org/ujm/Manager1 org.ujm.Manager1 ConnectBluetooth s "<id>"
busctl call org.ujm.Manager1 /org/ujm/Manager1 org.ujm.Manager1 ScanBluetooth u 15
```

```bash
busctl call org.ujm.Manager1 /org/ujm/Manager1 org.ujm.Manager1 SetPlayerLeds su "<id>" 12     # LEDs 3 and 4 light up
busctl call org.ujm.Manager1 /org/ujm/Manager1 org.ujm.Manager1 SetPlayerLeds su "<id>" 255    # back to the player number
busctl call org.ujm.Manager1 /org/ujm/Manager1 org.ujm.Manager1 SetHomeLed sb "<id>" false     # Joy-Con R / Pro Controller only
busctl call org.ujm.Manager1 /org/ujm/Manager1 org.ujm.Manager1 SetHomeLed sb "<id>" true
busctl call org.ujm.Manager1 /org/ujm/Manager1 org.ujm.Manager1 SetIdleTimeout u 120
journalctl -u joystickmanager -n 20 --no-pager | grep "command "
```

Expect: each call answers at once; the LEDs follow, and the manual pattern **stays** while the controller charges or its battery is low (no blinking, no periodic rewrite) until you send `255`; `state.json` shows `player_led_manual` and `home_led` accordingly and `service.idle_timeout` 120; after `sudo systemctl restart joystickmanager` the timeout is still 120 (it is kept in `/var/lib/joystickmanager/settings`; delete that file to go back to the unit's value). These are the first calls of the command channel on a real service and a real system bus: keep the exact error text of anything odd (`ServiceUnavailable` means the running service is an older version; reinstall it, step 0).

Expect: the controller disconnects and reconnects, and the card disappears and returns in the window. This is the first time the bridge meets a real BlueZ and a real polkit: anything odd is the result, so keep the exact error text.

## 8. The original tests 3, 4 and 6

Recovered from the first planning notes (2026-10-15). They gated going back from a 1800 s timeout to 300 s: they passed and the maintainer authorized 300 s on 2026-10-17, which is now the default.

- **Test 3, global numbering.** Connect a DualShock 3, a Pro Controller and Joy-Cons in different orders (for example Pro, DS3, Joy-Con; then DS3, Joy-Con, Pro). Players 1 to 8 follow the **connection order**, not the Bluetooth address. Check with `cat /run/joystickmanager/slots.tsv` and the LEDs.
- **Test 4, Joy-Cons.** Original and third-party Joy-Cons, separate and combined through `joycond`. Expect one slot for the combined pair and the **same LED pattern on both sides** of the virtual controller (the right one also lights its HOME LED, step 4).
- **Test 6, battery.** Normal, charging, and low or critical, ideally with a partly discharged controller: `grep -H . /sys/class/power_supply/*controller*/{capacity,status}`. Expect the player LED of the slot to stay steady when normal, blink when charging, and show the low pattern when low or critical, and `state.json` to show the same percent and status.

Keep the slot table, `state.json` and a note for each.

## 9. Close the sitting

```bash
tools/collect-report.sh
```

Send the final report **and** the baseline from step 0, plus your notes below. Bluetooth addresses are masked; read the file before sharing.

| Step | Done | Result (numbers, what you saw) |
|---|---|---|
| 1 Service cost with controllers | | |
| 2 Soak 30 min | | |
| 3 `LED_REFRESH=off` | | |
| 4 Joy-Con R HOME LED | | |
| 5 `state.json` | | |
| 6 Idle power-off | | |
| 8 Original tests 3, 4, 6 | done | Passed, reported by the maintainer on 2026-10-17 (no report file attached, so no numbers). The default idle timeout became 300 s. |
| 7 Bridge on the system bus | | |
