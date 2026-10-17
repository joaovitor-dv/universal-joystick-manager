# Interface shell and measurements

`ujm_gui_webengine.py` is a **stop-gap**: a PySide6 window with QtWebEngine around `ui/index.html`, plus a `QWebChannel` object named `ujm` that carries `/run/joystickmanager/state.json` to the page (the page cannot read the file itself). It exists to put real data in the current prototype and to measure what Chromium costs; the native interface will be QML (see [../docs/gui-measurements.md](../docs/gui-measurements.md)).

```bash
python3 gui/ujm_gui_webengine.py          # needs python-pyside6 with QtWebEngine
```

`qml_baseline.py` and `measure/baseline.qml` are the smallest possible QML windows, used as the floor in the measurements. `measure/` holds the scripts to repeat them.
