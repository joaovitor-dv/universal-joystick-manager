#!/usr/bin/env python3
"""UJM native interface (Qt Quick / QML), first slice: the Overview screen.

Data comes from the D-Bus bridge (org.ujm.Manager1, see docs/bridge.md). If the bridge is not
there, it falls back to reading /run/joystickmanager/state.json directly, read-only. A state
file can also be forced for development (--state-file) with no service and no hardware.

Nothing polls: updates arrive from the bus signal or from inotify.
"""
import argparse
import json
import os
import re
import sys
from pathlib import Path

from PySide6.QtCore import (Property, QAbstractListModel, QFileSystemWatcher, QModelIndex, QObject, Qt, QTimer,
                            QUrl, Signal, Slot, SLOT)
from PySide6.QtDBus import QDBusConnection, QDBusInterface, QDBusServiceWatcher
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuickControls2 import QQuickStyle

HERE = Path(__file__).resolve().parent
BUS_NAME, OBJ_PATH, IFACE = "org.ujm.Manager1", "/org/ujm/Manager1", "org.ujm.Manager1"
MAC_RE = re.compile(r"^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$")  # HID "uniq" may be lower case (DualShock 3)

VENDORS = {"switch-pro": "Nintendo", "joycon": "Nintendo", "joycon-combined": "Nintendo", "switch2": "Nintendo",
           "ps3": "Sony", "dualshock4": "Sony", "dualsense": "Sony",
           "xbox360": "Microsoft", "xbox-bluetooth": "Microsoft", "xbox-one-series": "Microsoft"}
TRANSPORTS = {"bluetooth": "Bluetooth", "usb": "USB", "virtual": "Joy-Con pair", "other": "Wired"}


def runtime_state_path():
    return Path(os.environ.get("JOYMANAGER_RUNTIME_DIR", "/run/joystickmanager")) / "state.json"


def controllers_from_state(state):
    """state.json (docs/state.md) -> the flat dicts the bridge publishes (docs/bridge.md)."""
    out = []
    for c in (state or {}).get("controllers", []):
        d = {"id": c.get("id", ""), "name": c.get("name") or "", "transport": c.get("transport") or "other",
             "player": c.get("player") if isinstance(c.get("player"), int) else 0,
             "player_led_mask": c.get("player_led_mask") if isinstance(c.get("player_led_mask"), int) else 0}
        for key in ("family", "hid", "event", "home_led"):
            if c.get(key):
                d[key] = c[key]
        for key in ("player_led_manual", "player_leds"):
            if isinstance(c.get(key), bool):
                d[key] = c[key]
        if MAC_RE.match(d["id"]):
            d["address"] = d["id"]
        b = c.get("battery")
        if isinstance(b, dict):
            if isinstance(b.get("percent"), int):
                d["battery_percent"] = b["percent"]
            if b.get("status"):
                d["battery_status"] = b["status"]
            if b.get("level"):
                d["battery_level"] = b["level"]
        out.append(d)
    return out


def read_state_file(path):
    try:
        state = json.loads(Path(path).read_text(encoding="utf-8"))
        if state.get("format") != "ujm-state" or state.get("version") != 1:
            return None
        return state
    except (OSError, ValueError, AttributeError):
        return None


class ControllerModel(QAbstractListModel):
    ROLES = ["controllerId", "name", "alias", "displayName", "vendor", "transportText", "transport", "player",
             "address", "hasBattery", "batteryPercent", "batteryStatus", "batteryLevel", "ledMask", "family",
             "homeLed", "ledManual", "playerLeds"]
    countChanged = Signal()

    def __init__(self):
        super().__init__()
        self._rows = []
        self._roles = {Qt.UserRole + 1 + i: r.encode() for i, r in enumerate(self.ROLES)}

    def roleNames(self):
        return self._roles

    def rowCount(self, parent=QModelIndex()):
        return 0 if parent.isValid() else len(self._rows)

    def data(self, index, role):
        if not index.isValid() or not 0 <= index.row() < len(self._rows):
            return None
        c = self._rows[index.row()]
        key = self._roles.get(role, b"").decode()
        if key == "controllerId":
            return c["id"]
        if key == "name":
            return c["name"]
        if key == "alias":
            return c.get("alias", "")
        if key == "displayName":
            return c.get("alias") or c["name"] or c["id"]
        if key == "vendor":
            return VENDORS.get(c.get("family", ""), "")
        if key == "transport":
            return c["transport"]
        if key == "transportText":
            return TRANSPORTS.get(c["transport"], c["transport"])
        if key == "player":
            return c["player"]
        if key == "address":
            return c.get("address", "")
        if key == "hasBattery":
            return "battery_percent" in c
        if key == "batteryPercent":
            return c.get("battery_percent", -1)
        if key == "batteryStatus":
            return c.get("battery_status", "")
        if key == "batteryLevel":
            return c.get("battery_level", "")
        if key == "ledMask":
            return c["player_led_mask"]
        if key == "family":
            return c.get("family", "")
        if key == "homeLed":  # "on", "off" or "unsupported" ("" when the service is older and does not say)
            return c.get("home_led", "")
        if key == "playerLeds":  # the controller has player-number LEDs (True when an older service does not say)
            return c.get("player_leds", True)
        if key == "ledManual":  # the player LEDs were set by hand (SetPlayerLeds), not by the slot
            return c.get("player_led_manual", False)
        return None

    @Property(int, notify=countChanged)
    def count(self):
        return len(self._rows)

    def set_controllers(self, rows):
        rows = sorted(rows, key=lambda c: (c["player"] or 99, c["id"]))
        if [c["id"] for c in rows] == [c["id"] for c in self._rows]:
            old, self._rows = self._rows, rows
            for i, (a, b) in enumerate(zip(old, rows)):
                if a != b:
                    ix = self.index(i)
                    self.dataChanged.emit(ix, ix)
            return
        self.beginResetModel()
        self._rows = rows
        self.endResetModel()
        self.countChanged.emit()


class Backend(QObject):
    """Chooses the data source and keeps the model current."""

    sourceChanged = Signal()

    def __init__(self, model, mode="auto", bus="system", state_file=None):
        super().__init__()
        self.model, self.mode, self.bus_kind = model, mode, bus
        self.forced_file = state_file
        self._kind, self._text, self._service = "none", "Looking for the service", ""
        self._bus = QDBusConnection.sessionBus() if bus == "session" else QDBusConnection.systemBus()
        self._iface = None
        self._watcher = QFileSystemWatcher(self)
        self._watcher.directoryChanged.connect(self._file_changed)
        self._watcher.fileChanged.connect(self._file_changed)
        self._svc_watcher = QDBusServiceWatcher(BUS_NAME, self._bus, QDBusServiceWatcher.WatchModeFlag.WatchForUnregistration, self)
        self._svc_watcher.serviceUnregistered.connect(lambda *_: QTimer.singleShot(1000, self.connect_source))

    # ---- properties for QML
    def _set(self, kind, text, service=""):
        if (kind, text, service) != (self._kind, self._text, self._service):
            self._kind, self._text, self._service = kind, text, service
            self.sourceChanged.emit()

    @Property(str, notify=sourceChanged)
    def sourceKind(self):
        return self._kind

    @Property(str, notify=sourceChanged)
    def sourceText(self):
        return self._text

    @Property(str, notify=sourceChanged)
    def serviceText(self):
        return self._service

    # ---- choosing a source
    @Slot()
    def connect_source(self):
        self._unwatch_file()
        if self.forced_file:
            return self._use_file(Path(self.forced_file), "example data" if "example" in self.forced_file else "state file")
        if self.mode in ("auto", "bridge") and self._use_bridge():
            return None
        if self.mode in ("auto", "file") and self._use_file(runtime_state_path(), "state.json, read-only"):
            return None
        self.model.set_controllers([])
        return self._set("none", "No service found", "Start it with: sudo systemctl enable --now joystickmanager")

    def _use_bridge(self):
        if not self._bus.isConnected():
            return False
        iface = QDBusInterface(BUS_NAME, OBJ_PATH, IFACE, self._bus)
        if not iface.isValid():
            return False
        self._iface = iface
        ok = self._bus.connect(BUS_NAME, OBJ_PATH, IFACE, "ControllersChanged", self, SLOT("on_bridge_changed()"))
        if not ok or not self._read_bridge():
            return False
        return True

    @Slot()
    def on_bridge_changed(self):
        self._read_bridge()

    def _read_bridge(self):
        reply = self._iface.call("GetSnapshotJson")
        args = reply.arguments()
        if not args or not isinstance(args[0], str):
            return False
        snap = json.loads(args[0])
        self.model.set_controllers(snap.get("controllers", []))
        st = snap.get("service", {})
        self._set("bridge", "D-Bus bridge", self._service_text(st.get("state_available", False), st.get("idle_timeout")))
        return True

    def _use_file(self, path, label):
        state = read_state_file(path)
        if state is None and not path.exists():
            return False
        self._file = path
        for p in (str(path.parent), str(path)):
            if os.path.exists(p):
                self._watcher.addPath(p)
        self._apply_state(state, label)
        return True

    def _apply_state(self, state, label):
        self.model.set_controllers(controllers_from_state(state))
        self._set("file", label, self._service_text(state is not None, (state or {}).get("service", {}).get("idle_timeout")))

    def _file_changed(self, *_):
        label = "example data" if self.forced_file and "example" in self.forced_file else (
            "state file" if self.forced_file else "state.json, read-only")
        for p in (str(self._file.parent), str(self._file)):  # the file is replaced by rename: watch it again
            if os.path.exists(p) and p not in self._watcher.files() + self._watcher.directories():
                self._watcher.addPath(p)
        self._apply_state(read_state_file(self._file), label)

    def _unwatch_file(self):
        paths = self._watcher.files() + self._watcher.directories()
        if paths:
            self._watcher.removePaths(paths)

    @staticmethod
    def _service_text(available, idle_timeout):
        if not available:
            return "Service data unavailable"
        return f"Idle power-off after {int(idle_timeout) // 60} min" if idle_timeout else "Service running"


def build(argv, mode="auto", bus="system", state_file=None):
    """Create the app objects; returns (app, engine, backend, model)."""
    app = QGuiApplication.instance() or QGuiApplication(argv)
    QQuickStyle.setStyle("Basic")  # the lightest style; the platform one stalled in the test environment
    model = ControllerModel()
    backend = Backend(model, mode, bus, state_file)
    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("backend", backend)
    engine.rootContext().setContextProperty("controllerModel", model)
    engine.load(QUrl.fromLocalFile(str(HERE / "qml" / "Main.qml")))
    backend.connect_source()
    return app, engine, backend, model


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--source", choices=["auto", "bridge", "file"], default="auto")
    ap.add_argument("--bus", choices=["system", "session"], default="system", help="bus of the bridge (session is for tests)")
    ap.add_argument("--state-file", help="read this state.json instead (development: gui/examples/state.example.json)")
    ap.add_argument("--print-ready", action="store_true", help="print a READY line when the window is up (measurements)")
    args, rest = ap.parse_known_args()
    app, engine, backend, model = build([sys.argv[0]] + rest, args.source, args.bus, args.state_file)
    if not engine.rootObjects():
        return 1
    if args.print_ready:
        print(f"READY ok=True source={backend.sourceKind} controllers={model.count}", flush=True)
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
