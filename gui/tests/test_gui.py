#!/usr/bin/env python3
"""Headless tests of the QML interface (offscreen, software rendering).

Usage: dbus-run-session -- python3 gui/tests/test_gui.py            (the bridge tests need a session bus)
       python3 gui/tests/test_gui.py --screenshot OUT.png [PLAYER] [HEIGHT] [STATE_FILE]
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
import warnings

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
warnings.filterwarnings("ignore", category=DeprecationWarning)

HERE = os.path.dirname(os.path.abspath(__file__))
GUI = os.path.join(HERE, "..")
sys.path.insert(0, GUI)

from PySide6.QtCore import QCoreApplication, QObject  # noqa: E402

import ujm_gui  # noqa: E402

EXAMPLE = os.path.join(GUI, "examples", "state.example.json")
BRIDGE = os.path.join(GUI, "..", "bridge", "ujm-bridge")


def pump(cond, timeout=5.0):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        QCoreApplication.processEvents()
        if cond():
            return True
        time.sleep(0.01)
    QCoreApplication.processEvents()
    return cond()


def rewrite(path, fn):
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    fn(data)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh)
    os.replace(tmp, path)  # the service replaces the file by rename


class Base(unittest.TestCase):
    def start(self, expect_none=False, **kw):
        self.app, self.engine, self.backend, self.model = ujm_gui.build(["test"], **kw)
        self.assertTrue(self.engine.rootObjects(), "the QML did not load")
        self.win = self.engine.rootObjects()[0]
        self.assertTrue(pump(lambda: self.backend.sourceKind != "none" or expect_none))

    def tearDown(self):
        if getattr(self, "engine", None):
            self.engine.deleteLater()
            QCoreApplication.processEvents()

    def item(self, name):
        found = self.win.findChild(QObject, name)
        self.assertIsNotNone(found, name)
        return found

    def visual_items(self):
        """Every Qt Quick item on screen, delegates included (they are not QObject children of the window)."""
        stack, out = [self.win.contentItem()], []
        while stack:
            it = stack.pop()
            out.append(it)
            stack.extend(it.childItems())
        return out


class FileSourceTests(Base):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.file = os.path.join(self.tmp, "state.json")
        shutil.copy(EXAMPLE, self.file)
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def test_example_is_shown_in_player_order(self):
        self.start(state_file=self.file)
        self.assertEqual(self.model.count, 5)
        self.assertEqual(self.backend.sourceKind, "file")
        rows = [self.model.data(self.model.index(i), ujm_gui.Qt.UserRole + 1 + ujm_gui.ControllerModel.ROLES.index("player"))
                for i in range(5)]
        self.assertEqual(rows, [1, 2, 3, 4, 5])
        self.assertEqual(self.item("controllerList").property("count"), 5)
        self.assertEqual(self.item("countText").property("text"), "5 connected")

    def test_roles(self):
        self.start(state_file=self.file)
        role = lambda r: ujm_gui.Qt.UserRole + 1 + ujm_gui.ControllerModel.ROLES.index(r)
        get = lambda i, r: self.model.data(self.model.index(i), role(r))
        self.assertEqual((get(0, "displayName"), get(0, "vendor"), get(0, "transportText")), ("Pro Controller", "Nintendo", "Bluetooth"))
        self.assertEqual((get(0, "hasBattery"), get(0, "batteryPercent"), get(0, "batteryStatus")), (True, 55, "Charging"))
        self.assertEqual((get(1, "transportText"), get(1, "hasBattery"), get(1, "address")), ("Joy-Con pair", False, ""))
        self.assertEqual((get(2, "batteryLevel"), get(2, "vendor")), ("low", "Sony"))
        self.assertEqual((get(4, "transportText"), get(4, "vendor")), ("Wired", "Microsoft"))
        self.assertEqual(get(0, "address"), "20:1C:3A:AA:00:01")

    def test_player_leds_are_drawn_from_the_mask(self):
        self.start(state_file=self.file)
        leds = lambda: sorted(o.objectName() for o in self.visual_items() if o.objectName().startswith("led") and o.objectName().endswith("on"))
        # masks: Pro Controller 1 (LED 1), joy-con pair 3 (LEDs 1 and 2), DualShock 4 4 (LED 3), PS3 8 (LED 4), Xbox 360 0 (none)
        expected = ["led0on", "led0on", "led1on", "led2on", "led3on"]
        self.assertTrue(pump(lambda: leds() == expected), leds())

    def test_native_details_reuse_controller_diagrams_and_button_icons(self):
        self.start(state_file=self.file)
        self.assertTrue(pump(lambda: self.win.property("selectedId") == "20:1C:3A:AA:00:01"))
        visible = lambda name: next((o for o in self.visual_items() if o.objectName() == name and o.isVisible()), None)
        self.assertTrue(pump(lambda: visible("detailTitle") is not None))
        self.assertEqual(visible("detailTitle").property("text"), "Pro Controller")
        self.win.setProperty("selectedId", "phys:usb-0000:00:14.0-2/input0")
        self.assertTrue(pump(lambda: visible("detailTitle") is not None and visible("detailTitle").property("text") == "Microsoft X-Box 360 pad"))
        art = visible("controllerArtwork")
        self.assertIsNotNone(art)
        self.assertTrue(pump(lambda: art.property("paintedWidth") > 0), "Xbox 360 SVG did not load")
        self.assertIn("xbox-360-xcf-ui.svg", art.property("source").toString())
        sectors = [o for o in self.visual_items() if o.objectName() == "buttonSector"]
        self.assertEqual(len(sectors), 4)
        icons = [o for o in self.visual_items() if o.objectName() == "buttonIcon" and o.isVisible()]
        self.assertTrue(pump(lambda: all(o.property("paintedWidth") > 0 for o in icons)), "a controller button SVG did not load")
        self.assertGreaterEqual(len(icons), 14)

    def test_native_diagrams_load_for_supported_families(self):
        def add_families(state):
            for i, (family, name) in enumerate([
                ("dualsense", "DualSense"), ("xbox-one-series", "Xbox Series X/S Controller"),
                ("joycon", "Joy-Con (L)"), ("joycon", "Joy-Con (R)")
            ], start=6):
                state["controllers"].append({"id": f"test:{i}", "player": i, "name": name,
                    "family": family, "transport": "bluetooth", "player_led_mask": 0, "battery": None})
        rewrite(self.file, add_families)
        self.start(state_file=self.file)
        role = lambda r: ujm_gui.Qt.UserRole + 1 + ujm_gui.ControllerModel.ROLES.index(r)
        for i in range(self.model.count):
            controller_id = self.model.data(self.model.index(i), role("controllerId"))
            self.win.setProperty("selectedId", controller_id)
            def artwork():
                return next((o for o in self.visual_items() if o.objectName() == "controllerArtwork" and o.isVisible()), None)
            self.assertTrue(pump(lambda: artwork() is not None and artwork().property("paintedWidth") > 0),
                            f"diagram did not load for {controller_id}")

    def test_series_share_and_ds4_system_icons_are_model_specific(self):
        def add_series(state):
            state["controllers"].append({"id": "test:series", "player": 6,
                "name": "Xbox Series X/S Controller", "family": "xbox-one-series",
                "transport": "bluetooth", "player_led_mask": 0, "battery": None})
        rewrite(self.file, add_series)
        self.start(state_file=self.file)
        share = lambda: next((o for o in self.visual_items() if o.objectName() == "xboxSeriesShare"), None)
        self.win.setProperty("selectedId", "test:series")
        self.assertTrue(pump(lambda: share() is not None and share().isVisible()), "Series Share overlay is missing")
        self.win.setProperty("selectedId", "20:1C:3A:AA:00:01")
        self.assertTrue(pump(lambda: share() is not None and not share().isVisible()), "Series Share leaks to the Pro Controller")
        self.win.setProperty("selectedId", "30:2C:3A:AA:00:03")
        def ds4_icons():
            return [o for o in self.visual_items() if o.objectName() == "buttonIcon" and o.isVisible()
                    and any(name in o.property("source").toString() for name in ("ps4_button_share", "ps4_button_options"))]
        self.assertTrue(pump(lambda: len(ds4_icons()) == 2 and all(o.property("paintedWidth") > 0 for o in ds4_icons())),
                        "DualShock 4 Share/Options icons did not render")

    def test_led_state_badges_follow_service_data_without_guessing(self):
        self.start(state_file=self.file)
        pill = lambda name: next((o for o in self.visual_items() if o.objectName() == name), None)
        self.assertTrue(pump(lambda: pill("homeLedPill") is not None and pill("manualLedPill") is not None))
        self.assertFalse(pill("homeLedPill").isVisible(), "an old service must not be reported as HOME off")
        self.assertFalse(pill("manualLedPill").isVisible(), "automatic mode needs no badge")

        def set_leds(state):
            state["controllers"][0].update(home_led="on", player_led_manual=True)
        rewrite(self.file, set_leds)
        self.assertTrue(pump(lambda: pill("homeLedPill").isVisible()
                             and pill("homeLedPill").property("text") == "HOME LED on"
                             and pill("manualLedPill").isVisible()), "LED state did not reach QML")
        rewrite(self.file, lambda state: state["controllers"][0].update(home_led="off", player_led_manual=False))
        self.assertTrue(pump(lambda: pill("homeLedPill").property("text") == "HOME LED off"
                             and not pill("manualLedPill").isVisible()), "LED badge did not follow the update")
        rewrite(self.file, lambda state: state["controllers"][0].update(home_led="unsupported"))
        self.assertTrue(pump(lambda: not pill("homeLedPill").isVisible()),
                        "unsupported HOME LED should not add the old availability comment")

    def test_updates_live_when_the_file_is_replaced(self):
        self.start(state_file=self.file)
        rewrite(self.file, lambda d: d["controllers"].append(
            {"id": "50:AA:00:00:00:06", "player": 6, "name": "Pro Controller", "family": "switch-pro", "transport": "usb",
             "hid": None, "event": "event40", "player_led_mask": 8, "battery": None}))
        self.assertTrue(pump(lambda: self.model.count == 6), "a new controller did not appear")
        self.assertEqual(self.item("countText").property("text"), "6 connected")
        rewrite(self.file, lambda d: d["controllers"].__delitem__(slice(0, 5)))
        self.assertTrue(pump(lambda: self.model.count == 1))
        self.assertEqual(self.item("countText").property("text"), "1 connected")
        rewrite(self.file, lambda d: d["controllers"].clear())
        self.assertTrue(pump(lambda: self.model.count == 0))
        self.assertTrue(self.item("emptyText").property("visible"))

    def test_a_battery_change_updates_the_row_without_resetting_the_list(self):
        self.start(state_file=self.file)
        resets = []
        self.model.modelReset.connect(lambda: resets.append(1))
        role = ujm_gui.Qt.UserRole + 1 + ujm_gui.ControllerModel.ROLES.index("batteryPercent")
        rewrite(self.file, lambda d: d["controllers"][0]["battery"].update(percent=99))
        self.assertTrue(pump(lambda: self.model.data(self.model.index(0), role) == 99))
        self.assertEqual(resets, [])

    def test_unreadable_file_means_no_data_not_a_crash(self):
        self.start(state_file=self.file)
        with open(self.file, "w", encoding="utf-8") as fh:
            fh.write("{broken")
        self.assertTrue(pump(lambda: self.model.count == 0))
        self.assertIn("unavailable", self.backend.serviceText)


class NoServiceTests(Base):
    def test_without_any_source_it_says_so(self):
        os.environ["JOYMANAGER_RUNTIME_DIR"] = tempfile.mkdtemp()
        self.addCleanup(os.environ.pop, "JOYMANAGER_RUNTIME_DIR", None)
        self.start(mode="file", expect_none=True)
        self.assertEqual(self.backend.sourceKind, "none")
        self.assertEqual(self.model.count, 0)
        self.assertIn("not running", self.item("emptyText").property("text"))
        self.assertIn("systemctl", self.backend.serviceText)


@unittest.skipUnless(os.environ.get("DBUS_SESSION_BUS_ADDRESS"), "needs a session bus: run under dbus-run-session")
class BridgeSourceTests(Base):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.run_dir = os.path.join(self.tmp, "run")
        os.makedirs(self.run_dir)
        self.file = os.path.join(self.run_dir, "state.json")
        shutil.copy(EXAMPLE, self.file)
        env = dict(os.environ, UJM_BUS="session", JOYMANAGER_RUNTIME_DIR=self.run_dir,
                   UJM_BRIDGE_STATE_DIR=os.path.join(self.tmp, "data"), UJM_BRIDGE_IDLE_EXIT="0")
        self.bridge = subprocess.Popen([sys.executable, BRIDGE], env=env, stdout=subprocess.PIPE, text=True)
        self.assertEqual(self.bridge.stdout.readline().strip(), "READY")
        self.addCleanup(self._stop)

    def _stop(self):
        self.bridge.terminate()
        self.bridge.wait(5)
        self.bridge.stdout.close()

    def test_reads_the_bridge_and_follows_its_signal(self):
        self.start(mode="bridge", bus="session")
        self.assertEqual(self.backend.sourceKind, "bridge")
        self.assertEqual(self.backend.sourceText, "D-Bus bridge")
        self.assertEqual(self.model.count, 5)
        rewrite(self.file, lambda d: d["controllers"].pop())
        self.assertTrue(pump(lambda: self.model.count == 4), "no update after the bridge signalled a change")

    def test_falls_back_to_the_file_when_there_is_no_bridge(self):
        self._stop()
        self.addCleanup(lambda: None)
        os.environ["JOYMANAGER_RUNTIME_DIR"] = self.run_dir
        self.addCleanup(os.environ.pop, "JOYMANAGER_RUNTIME_DIR", None)
        # no bridge owns the name and nothing can start it on this private bus
        self.start(mode="auto", bus="session")
        self.assertEqual(self.backend.sourceKind, "file")
        self.assertEqual(self.model.count, 5)


def screenshot(out, player=1, height=740, state_file=EXAMPLE):
    app, engine, backend, model = ujm_gui.build(["shot"], state_file=state_file)
    win = engine.rootObjects()[0]
    win.setHeight(height)
    pump(lambda: model.count > 0, 3)
    role = ujm_gui.Qt.UserRole + 1 + ujm_gui.ControllerModel.ROLES.index("controllerId")
    if not 1 <= player <= model.count:
        raise ValueError("PLAYER must be within the screenshot state controller list")
    win.setProperty("selectedId", model.data(model.index(player - 1), role))
    for _ in range(30):
        QCoreApplication.processEvents()
        time.sleep(0.02)
    win.grabWindow().save(out)
    print("saved", out)


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "--screenshot":
        screenshot(sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 1,
                   int(sys.argv[4]) if len(sys.argv) > 4 else 740,
                   sys.argv[5] if len(sys.argv) > 5 else EXAMPLE)
    else:
        unittest.main(verbosity=2)
