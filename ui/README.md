# UJM interface (prototype)

A static HTML prototype of the UJM graphical interface. **It uses simulated data and is not connected to the service yet**: the controller list, the service button, pairing and connection are all simulated. It exists to settle the layout and behavior before the service exposes a local API (see `docs/` in the coordination notes and the roadmap in the [main README](../README.md#roadmap)).

## Open it

Open `ui/index.html` in a browser:

```bash
xdg-open ui/index.html
```

If your browser restricts local files, serve the folder instead and open <http://127.0.0.1:8000/>:

```bash
python3 -m http.server --directory ui 8000
```

## What it shows

- A connected-only controller roster with ten simulated slots and a separate Combined Joy-Cons diagram preview. Numbered LEDs, DUALSHOCK 4 light-bar colors, DualSense white player indicators and the Xbox 360 ring are shown as **slot references**, never as live hardware readings. RGB color for DualSense and undefined patterns above the manufacturer's four-player convention are reported as unknown.
- A per-controller diagram with the real button names of each family, stick values and extra readings.
- **File**: export and import controller profiles and app settings as JSON, **Update UJM…** (opens the official release downloads after confirmation; no automatic installation), and Exit.
- A toolbar with a **Start/Stop service** button (the interface is read-only while the service is stopped) and Bluetooth shortcuts: **Pair new controller…**, **Connect**, **Disconnect**.
- **View → Theme…**: your own background, accent and text colors, or a preset. Dark themes only, on purpose.
- **Help → Credits & Info**, mirroring [`CREDITS.md`](../CREDITS.md).

## Files

| Path | What it is |
|---|---|
| `index.html` | The whole interface: markup, styles and scripts. |
| `assets/` | Controller artwork and button icons. **Not MIT**: see [`assets/ASSETS-NOTICE.md`](assets/ASSETS-NOTICE.md). |
| `tests/` | Browser tests run with headless Chromium (see below). |

## Tests

The tests drive the page in a headless Chromium through the DevTools protocol. They need Node.js 22 or newer and Chromium or Google Chrome:

```bash
ui/tests/run.sh
```

They check that every asset exists and loads, that each of the 11 controller panels renders without errors or overflow, the Joy-Con button alignment, the menus, import/export, the simulated service and Bluetooth flows, the theme limits and the Credits page. Set `CHROME=/path/to/browser` if the browser is not called `chromium`.
