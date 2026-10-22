# Service state snapshot (`state.json`)

The service publishes what it knows in `/run/joystickmanager/state.json` (inside `JOYMANAGER_RUNTIME_DIR`). It is the first, read-only step of the local API that the graphical interface will use instead of its simulated data. A D-Bus interface, when it comes, will expose the same model.

- **Format:** `"format": "ujm-state"`, `"version": 1`. A change that removes or renames a field bumps the version; new fields may be added without a bump.
- **When:** checked every service cycle (about 2 s), but the file is rewritten **only when something other than `updated` changed**, so an idle system does not rewrite it.
- **How:** written to `state.json.tmp` and renamed, so a reader never sees a half-written file. Mode `644`: readable by user applications.
- **Privacy:** it contains Bluetooth addresses of the connected controllers, as `bluetoothctl` already shows to local users. Do not paste it publicly without masking them.

## Example

```json
{
  "updated": 1792198928,
  "format": "ujm-state",
  "version": 1,
  "service": { "led_refresh": "10", "idle_timeout": 1800, "experimental": false },
  "controllers": [
    {
      "id": "20:1C:3A:XX:XX:XX",
      "player": 1,
      "name": "Pro Controller",
      "family": "switch-pro",
      "transport": "bluetooth",
      "hid": "0005:057E:2009.0031",
      "event": "event30",
      "player_led_mask": 1,
      "player_leds": true,
      "player_led_manual": false,
      "home_led": "on",
      "battery": { "percent": 55, "status": "Charging", "level": "normal" }
    }
  ]
}
```

## Fields

| Field | Type | Meaning |
|---|---|---|
| `updated` | integer | Unix time of the last change. |
| `service.led_refresh` | string | `JOYMANAGER_LED_REFRESH` as the service understood it (`"10"`, `"0"`, `"off"`). |
| `service.idle_timeout` | integer | Seconds before an idle Bluetooth controller is disconnected; `0` means never. It can be changed at run time and is then kept across restarts. |
| `service.experimental` | boolean | Whether experimental controller profiles are enabled. |
| `controllers[]` | array | Connected controllers, ordered by player number. |
| `id` | string | Stable identity: the Bluetooth address for HID controllers, `joycond:<event>` for the virtual Joy-Con pair, `phys:...`/`path:...` for drivers without one (for example `xpad`). |
| `player` | integer | Player slot, 1-8, by connection order. |
| `name` | string | Input device name reported by the kernel. |
| `family` | string or null | Profile family from `controllers.tsv` (`switch-pro`, `joycon`, `ps3`, ...). |
| `transport` | string | `bluetooth`, `usb`, `virtual` (joycond pair) or `other`. |
| `hid` | string or null | HID device (`bus:vendor:product.instance`); a new connection gets a new one. |
| `event` | string | Input event node, `/dev/input/<event>`. |
| `player_led_mask` | integer | The 4-bit player LED pattern the service applies (bit 0 = LED 1); mirrored for the right Joy-Con. |
| `player_leds` | boolean | The controller has player-number LEDs the service can drive. `false` for the Xbox One and Series controllers (a HOME light only) and for the DualShock 4 and DualSense (an RGB light only); the interface should not draw numbering for them. Absent in older services: treat as `true`. |
| `player_led_manual` | boolean | `true` when the player LEDs were set by hand through the [command channel](command-channel.md) (then `player_led_mask` is that pattern and the service does not refresh or blink them). |
| `home_led` | string | `on` or `off` (what the service last asked of the HOME LED) or `unsupported` when the controller has none **that the service can drive**. The controller itself lights it for only about 15 s per command, so `on` does not mean it is lit now. |
| `battery` | object or null | `percent` (integer or null: a Pro Controller on a cable reports its status but no percentage), `status` (`Charging`, `Discharging`, `Full`, ...) and `level` (`normal`, `low`, `critical`). `null` when the driver exposes no battery. The joycond virtual pair has none: its Joy-Cons report their own. |

## Player LED patterns

The player number is shown with the LEDs below (LED 1 is the first LED of the controller). The Pro Controller, DualShock 3, Xbox 360, the left Joy-Con, and the combined Joy-Con pair all use the **standard** column. The right Joy-Con on its own uses the **mirrored** column, which is the bit reversal of the standard one, because its LEDs run in the opposite direction. The same pattern can therefore look the same on different controllers; only the physical position of the lit LED tells them apart.

| Player | Standard (`player_led_mask`) | LEDs | Right Joy-Con alone (mirrored) | LEDs |
|---|---|---|---|---|
| 1 | 1 | 1 | 8 | 4 |
| 2 | 2 | 2 | 4 | 3 |
| 3 | 4 | 3 | 2 | 2 |
| 4 | 8 | 4 | 1 | 1 |
| 5 | 9 | 1+4 | 9 | 1+4 |
| 6 | 10 | 2+4 | 5 | 1+3 |
| 7 | 12 | 3+4 | 3 | 1+2 |
| 8 | 13 | 1+3+4 | 11 | 1+2+4 |
| 9 | 3 | 1+2 | 12 | 3+4 |
| 10 | 5 | 1+3 | 10 | 2+4 |

The service numbers up to 10 players. An eleventh controller is connected but gets no number and no LED.

## What each controller has

Hardware facts reported by the maintainer; whether the kernel exposes a light as something the service can drive is what `player_leds` and `home_led` report.

| Controller | Player-number LEDs | HOME LED | Other light |
|---|---|---|---|
| Pro Controller | yes | yes | |
| Joy-Con R, and the `joycond` pair | yes | yes (the right one) | |
| Joy-Con L | yes | no | |
| DualShock 3 | yes | no | |
| Xbox One, Xbox Series X/S | **no** | yes (its only light) | |
| DualShock 4, DualSense | **no** | no | RGB light bar, not driven by UJM |

**Joy-Cons and `joycond`.** A left and a right Joy-Con merged by `joycond` show up as one `Nintendo Switch Combined Joy-Cons` controller (`transport: virtual`) with one `player`; the two Joy-Cons it stands for have no entry of their own, a free Joy-Con keeps its own. The service tells them apart by the permission of the Joy-Con's input node, which `joycond` sets to root-only (0600) while it holds the Joy-Con; checked on hardware with a gray pair left free and a white pair merged (button presses reached each free Joy-Con's own node, and only the combined device for the merged ones).

Numbering still exists in software for all of them (the `player` field); it just has no LED to show it on.

**Third-party Joy-Cons** (tested with a gray pair, which is **not** supported: see the README) answer to the same commands but behave differently: they accept a player pattern, show it for a few seconds and go back to LED 1 on their own, and the right one never lights its HOME LED. Keeping a pattern there would take a command every few seconds, which is what drops the link, so UJM does not try: they show LED 1. The identifier (`057E:2006` / `2007`) is the same as an original's, so they cannot be told apart; `player_leds` says the controller has LEDs, not that they will stay as asked. The same goes for the HOME LED of any controller, which the controller turns off by itself about 15 s after each command.

## Reading it

```bash
cat /run/joystickmanager/state.json
python3 -m json.tool /run/joystickmanager/state.json
```

A client should re-read the file when it changes (for example with inotify on the directory, watching for the rename) rather than polling quickly.
