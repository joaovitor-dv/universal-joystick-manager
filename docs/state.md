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
| `service.idle_timeout` | integer | Seconds before an idle Bluetooth controller is disconnected. |
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
| `battery` | object or null | `percent` (integer or null), `status` (`Charging`, `Discharging`, `Full`, ...) and `level` (`normal`, `low`, `critical`). `null` when the driver exposes no battery. The joycond virtual pair has none: its Joy-Cons report their own. |

## Reading it

```bash
cat /run/joystickmanager/state.json
python3 -m json.tool /run/joystickmanager/state.json
```

A client should re-read the file when it changes (for example with inotify on the directory, watching for the rename) rather than polling quickly.
