# Native interface (QML), WebEngine shell and measurements

## Native interface

`ujm_gui.py` + `qml/` is the real interface (first slice: the Overview screen, read-only). It uses the D-Bus bridge ([../docs/bridge.md](../docs/bridge.md)) and falls back to `/run/joystickmanager/state.json`. Dark only, Qt Quick Controls `Basic` style.

```bash
python3 gui/ujm_gui.py                                              # bridge, else state.json
python3 gui/ujm_gui.py --state-file gui/examples/state.example.json  # no service, no hardware
dbus-run-session -- python3 -W ignore gui/tests/test_gui.py          # 9 headless tests
python3 gui/tests/test_gui.py --screenshot out.png                   # render the example data
```

Needs `python-pyside6` (QtQuick, QtDBus). The tests use the offscreen platform with software rendering and, for the bridge cases, a private session bus; they are not in CI yet because PySide6 is not on the runner.

## WebEngine shell (stop-gap)

`ujm_gui_webengine.py` is a **stop-gap**: a PySide6 window with QtWebEngine around `ui/index.html`, plus a `QWebChannel` object named `ujm` that carries `/run/joystickmanager/state.json` to the page (the page cannot read the file itself). It exists to put real data in the current prototype and to measure what Chromium costs; the native interface above replaces it (see [../docs/gui-measurements.md](../docs/gui-measurements.md)).

```bash
python3 gui/ujm_gui_webengine.py          # needs python-pyside6 with QtWebEngine
```

`qml_baseline.py` and `measure/baseline.qml` are the smallest possible QML windows, used as the floor in the measurements. `measure/` holds the scripts to repeat them.
