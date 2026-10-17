# Native interface (QML), WebEngine shell and measurements

## Native interface

`ujm_gui.py` + `qml/` is the native interface. It shows the connected-controller overview and a read-only details panel with family-specific diagrams and button groups reused from the HTML prototype. The Xbox 360 panel uses the upper-layer SVG exported from the editable XCF. The details panel also shows HOME LED on/off and a manual player-LED badge when the service supplies those states; unknown and unsupported HOME states are not guessed or displayed. Diagram highlights, stick values and adaptive-trigger output are **not live**: the service does not yet expose input telemetry to this screen. It uses the D-Bus bridge ([../docs/bridge.md](../docs/bridge.md)) and falls back to `/run/joystickmanager/state.json`. Dark only, Qt Quick Controls `Basic` style.

```bash
python3 gui/ujm_gui.py                                              # bridge, else state.json
python3 gui/ujm_gui.py --state-file gui/examples/state.example.json  # no service, no hardware
dbus-run-session -- python3 -W ignore gui/tests/test_gui.py          # 13 headless tests
python3 gui/tests/test_gui.py --screenshot out.png [PLAYER] [HEIGHT] [STATE_FILE] # render a controller state
```

Needs `python-pyside6` (QtQuick, QtDBus, QtSvg). The tests use the offscreen platform with software rendering and, for the bridge cases, a private session bus; they are not in CI yet because PySide6 is not on the runner. Controller art is read from `ui/assets/` through local relative URLs; the HTML preview remains a separate prototype.

## WebEngine shell (stop-gap)

`ujm_gui_webengine.py` is a **stop-gap**: a PySide6 window with QtWebEngine around `ui/index.html`, plus a `QWebChannel` object named `ujm` that carries `/run/joystickmanager/state.json` to the page (the page cannot read the file itself). It exists to put real data in the current prototype and to measure what Chromium costs; the native interface above replaces it (see [../docs/gui-measurements.md](../docs/gui-measurements.md)).

```bash
python3 gui/ujm_gui_webengine.py          # needs python-pyside6 with QtWebEngine
```

`qml_baseline.py` and `measure/baseline.qml` are the smallest possible QML windows, used as the floor in the measurements. `measure/` holds the scripts to repeat them.
