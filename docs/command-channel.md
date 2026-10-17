# Command channel: from the bridge into the service

The shell service (`joystickmanager.sh`) is the **only writer of player numbering and LEDs**. The bridge ([bridge.md](bridge.md)) never writes them itself: it asks the service, over a small channel that only root can use. Nothing here is for applications; they talk to the bridge.

```text
 bridge (root) ── one line ──▶ /run/joystickmanager/command.fifo ──▶ service
        ▲                                                              │
        └──────────── /run/joystickmanager/ack/<request-id> ◀──────────┘
```

## Request

One line per request, tab-separated, at most a few hundred bytes (a write below `PIPE_BUF` is atomic, so requests never interleave):

```text
REQ <TAB> request-id <TAB> command <TAB> arg1 <TAB> arg2
```

`request-id` is 8 to 64 letters or digits (anything else is ignored, which also keeps it from being a path). The FIFO is `0600`, owned by root, created when the service starts and removed when it stops. The bridge opens it without blocking: if the service is not running there is no reader and the open fails at once, which the bridge reports as `ServiceUnavailable`.

## Commands

| Command | Arguments | Effect |
|---|---|---|
| `idle_timeout` | `SECONDS` | `0` turns the idle power-off off; otherwise 60 to 86400. Applied at once (running idle workers are stopped and come back with the new value) and **kept across restarts** in `/var/lib/joystickmanager/settings`, where it wins over `Environment=JOYMANAGER_IDLE_TIMEOUT` in the unit. Delete that file to go back to the unit's value. |
| `player_leds` | `ID MASK` | `MASK` 0 to 15 (bit 0 = LED 1) is the physical pattern; it is applied at once and **wins over the slot pattern** until `255` is sent, or until the controller disconnects. While a manual pattern is set the service does not refresh that controller's LEDs and does not blink them for battery or charging. Refused for controllers without player LEDs the service can write and for the `joycond` virtual pair. |
| `home_led` | `ID on|off` | Turns the HOME LED (Joy-Con R, Pro Controller) off, or back to full brightness. `off` is kept against the periodic refresh until the controller disconnects. Refused where there is no HOME LED. |

`ID` is the controller `id` of [state.md](state.md) and must be a controller that is connected now. **`PairJoycond` does not exist**: `joycond` completes a Joy-Con pairing when the user presses L+R (or SL+SR) on the controllers, and nothing outside it can trigger that.

## Answer

The service writes `/run/joystickmanager/ack/<request-id>` (atomically, the directory is `0700`):

```text
ok
```
or
```text
error <TAB> reason
```

The bridge polls for it every 40 ms for 5 s (`UJM_ACK_TIMEOUT`), deletes it, and turns `error` into the D-Bus error `org.ujm.Manager1.Error.Rejected` carrying the reason; no answer is `ServiceTimeout`. The service also logs each command and its outcome to the journal.

## Rules the service keeps whatever the sender does

- It checks every argument again (numbers, ranges, the id against the current controllers); an argument with shell syntax is just a refused argument and is never evaluated.
- A request with a bad id, a bad tag or no tab structure is ignored without an answer.
- It does not trust the bridge to have checked anything, and the bridge does not trust the interface.

## Cost

The service's 2 s pause used to be `sleep 2`, a new process every cycle. It is now a `read -t 2` on the FIFO, a shell builtin: **fewer processes per cycle than before**, no extra work when nothing is sent, and a command is answered at once (tens of milliseconds) instead of at the next cycle.

## Tests

`tests/test_slots.sh` covers the commands on a fake sysfs (patterns survive refreshes and charging blinks, refusals, malformed requests, persistence, workers stopped with their evtest pipeline) and one test that starts the real service in a temporary directory and talks to it through the FIFO, checking the answer time, the FIFO permissions and that nothing is left running afterwards. `bridge/tests/test_bridge.py` covers the bridge side with a fake service (`bridge/tests/fake_service.py`): requests, refusals, rejection by the service, timeout, no channel, a FIFO nobody reads, and the polkit actions. **Not tested:** the bridge's sandbox rules on a real system unit (it needs `ReadWritePaths=-/run/joystickmanager` to remove the answer files), and any of it on a real controller.
