# D-Bus bridge (`org.ujm.Manager1`)

The graphical interface does not read `/dev/input`, run `bluetoothctl` or touch the service. It talks to a small **bridge** on the system bus. The shell service (`joystickmanager.sh`) stays the only authority over player numbering and LEDs; the bridge republishes what it knows and drives BlueZ on the interface's behalf.

```text
 interface (user) ──D-Bus──▶ ujm-bridge (root) ──▶ BlueZ (org.bluez, D-Bus)
                                  │  ▲
                                  │  └── polkit: asks before every action
                                  ▼
                    /run/joystickmanager/state.json  ◀── joystickmanager.sh
                    /var/lib/ujm/aliases.json (aliases, written by the bridge)
```

## Install

It is optional and only useful with an interface that uses it.

| How | Command |
|---|---|
| `install.sh` | `sudo ./install.sh --with-bridge` (also installs `python3-gi`/`python-gobject` and polkit) |
| Arch / Debian / Fedora packages | the files are in the package; install `python-gobject` / `python3-gi` / `python3-gobject-base` and polkit (optional dependencies) |

Nothing has to be enabled: `org.ujm.Manager1.service` lets the bus start `ujm-bridge.service` on the first call. The bridge exits by itself 30 s after the last client that called it has left the bus, so **it costs nothing while the interface is closed**. A client that only listens to signals must make one call first (for example `GetServiceStatus`), otherwise the bridge may exit.

| File | Where it goes |
|---|---|
| `bridge/ujm-bridge` | `/usr/local/libexec/ujm-bridge` (`install.sh`), `/usr/lib/joystickmanager/ujm-bridge` (Arch, Debian), `/usr/libexec/ujm-bridge` (Fedora) |
| `bridge/ujm-bridge.service` | systemd unit, hardened (read-only filesystem, no new privileges, Unix sockets only), no `[Install]` section |
| `bridge/org.ujm.Manager1.conf` | `system.d` bus policy: only root owns the name, anyone may call it |
| `bridge/org.ujm.Manager1.service` | bus activation |
| `bridge/org.ujm.manager.policy` | polkit actions |

## Reading it

```bash
busctl call org.ujm.Manager1 /org/ujm/Manager1 org.ujm.Manager1 GetServiceStatus
busctl get-property org.ujm.Manager1 /org/ujm/Manager1 org.ujm.Manager1 Controllers
busctl monitor org.ujm.Manager1
```

## Interface `org.ujm.Manager1` (version 1)

Properties: `Version` (`s`, the API version), `StateAvailable` (`b`, whether a valid `state.json` exists), `Controllers` (`aa{sv}`).
Signals: `ControllersChanged`, `BluetoothDevicesChanged` (both without payload: read again), plus the standard `PropertiesChanged`.

| Method | Authorization | Notes |
|---|---|---|
| `ListControllers() → aa{sv}` | none | Same list as the `Controllers` property. |
| `GetController(s id) → a{sv}` | none | `UnknownController` if `id` is not connected. |
| `GetSnapshotJson() → s` | none | The service status and the controllers as one JSON text (`api_version`, `service`, `controllers`), for clients that cannot unpack `a{sv}` easily: QtDBus from Python cannot. |
| `GetServiceStatus() → a{sv}` | none | `api_version`, `state_available`, `updated`, `idle_timeout`, `led_refresh`, `experimental`. |
| `SetControllerAlias(s id, s alias)` | `org.ujm.manager.set-alias` | Only for controllers with a stable address (Bluetooth MAC). Up to 40 printable characters; empty clears it. Stored in `/var/lib/ujm/aliases.json`. |
| `ConnectBluetooth(s id)`, `DisconnectBluetooth(s id)` | `org.ujm.manager.bluetooth` | Only controllers connected over Bluetooth. Calls BlueZ `Device1.Connect`/`Disconnect`. |
| `ScanBluetooth(u seconds)` | `org.ujm.manager.bluetooth` | Starts discovery and stops it by itself (1 to 60 s, 15 if 0). |
| `ListBluetoothDevices() → aa{sv}` | none | `address`, `name`, `paired`, `connected`, `gamepad` (BlueZ icon `input-gaming`). |
| `PairBluetooth(s address)` | `org.ujm.manager.bluetooth` | Pair, trust, then connect. |
| `SetIdleTimeout(u)`, `SetPlayerLeds(s,u)`, `SetHomeLed(s,b)` | `org.ujm.manager.configure` | **Not available yet**: they return `org.freedesktop.DBus.Error.NotSupported` (see below). |

A controller (`a{sv}`) has: `id`, `name`, `transport` (`bluetooth`, `usb`, `virtual`, `other`), `player`, `player_led_mask`, `connected`, and when known `family`, `hid`, `event`, `address`, `alias`, `battery_percent`, `battery_status`, `battery_level`. The field meanings are the ones in [state.md](state.md).

Errors are standard D-Bus errors: `InvalidArgs` (for example an alias for an id without an address, connecting a USB controller), `AccessDenied` (polkit said no), `org.ujm.Manager1.Error.UnknownController`, `NoAdapter`/`NoBluetooth`, and BlueZ's own errors passed through (`org.bluez.Error.Failed`...).

## Authorization

Reads need none (the snapshot is world readable anyway). Actions ask polkit about the **caller's bus name**, with interaction allowed. Defaults: `set-alias` and `bluetooth` are allowed for the active local session and need an administrator otherwise; `configure` always needs an administrator (kept for the actions that are not available yet).

## What is not done: a command channel to the service

`SetIdleTimeout`, `SetPlayerLeds` and `SetHomeLed` need the shell service to accept commands, and it does not yet. The service is the only writer of the LEDs, so the bridge must not write them behind its back. The plan is a small file the service reads each cycle (for the idle timeout) and a request file for one-shot LED tests; both need design and tests on the service side first.

## Resources

Measured on the maintainer's machine (see [gui-measurements.md](gui-measurements.md)): 0.00% of a CPU core while idle, about 20 MiB of memory (PSS) while running, nothing when stopped.

## Tests

```bash
dbus-run-session -- python3 bridge/tests/test_bridge.py
```

20 tests on a private session bus with a **fake BlueZ and a fake polkit** (`bridge/tests/fake_bluez.py`): nothing touches the real system bus or Bluetooth. They cover the snapshot and its change signal, bad or foreign `state.json`, aliases (sanitising, persistence, refusal), Bluetooth routing and error passthrough, polkit being asked with the right action and caller (and a refusal blocking the action), the actions that are not available, and the bridge exiting when unused. The test authorizers (`UJM_TEST_AUTH`) are only honoured on a session bus (`UJM_BUS=session`), never on the system bus.
Not tested: a real BlueZ, a real polkit and the system bus policy files, which need an installed system.
