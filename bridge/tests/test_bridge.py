#!/usr/bin/env python3
"""Bridge tests on a private session bus with a fake BlueZ.

Usage: dbus-run-session -- python3 bridge/tests/test_bridge.py
Exit status is non-zero if a test fails. Nothing here touches the real system bus or Bluetooth.
"""
import json
import os
import warnings
import subprocess
import sys
import tempfile
import time
import unittest

warnings.filterwarnings("ignore", category=DeprecationWarning)  # PyGObject on Python 3.14

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
BRIDGE = os.path.join(HERE, "..", "ujm-bridge")
FAKE = os.path.join(HERE, "fake_bluez.py")
FAKE_SERVICE = os.path.join(HERE, "fake_service.py")
NAME, PATH, IFACE = "org.ujm.Manager1", "/org/ujm/Manager1", "org.ujm.Manager1"

PRO = "20:1C:3A:00:00:01"
STATE = {
    "updated": 1, "format": "ujm-state", "version": 1,
    "service": {"led_refresh": "10", "idle_timeout": 1800, "experimental": False},
    "controllers": [
        {"id": PRO, "player": 1, "name": "Pro Controller", "family": "switch-pro", "transport": "bluetooth",
         "hid": "0005:057E:2009.0031", "event": "event30", "player_led_mask": 1, "player_led_manual": False,
         "home_led": "on", "player_leds": True, "battery": {"percent": 55, "status": "Charging", "level": "normal"}},
        {"id": "joycond:event5", "player": 2, "name": "Nintendo Switch Combined Joy-Cons", "family": "joycon-combined",
         "transport": "virtual", "hid": None, "event": "event5", "player_led_mask": 3, "battery": None},
        {"id": "30:2C:3A:00:00:02", "player": 3, "name": "Pro Controller", "family": "switch-pro", "transport": "usb",
         "hid": "0003:057E:2009.0040", "event": "event31", "player_led_mask": 4, "home_led": "unsupported",
         "player_leds": False, "battery": None},
    ],
}


def pump(cond, timeout=5.0):
    """Run the main loop until cond() is true; returns whether it became true."""
    ctx, end = GLib.MainContext.default(), time.monotonic() + timeout
    while time.monotonic() < end:
        if cond():
            return True
        ctx.iteration(False)
        time.sleep(0.01)
    return cond()


class Env:
    """Runtime dir, state dir, fake BlueZ and the bridge process for one group of tests."""

    def __init__(self, auth="allow", idle_exit="0", service=True, ack_timeout="5"):
        self.tmp = tempfile.TemporaryDirectory()
        t = self.tmp.name
        self.runtime, self.data, self.log = os.path.join(t, "run"), os.path.join(t, "data"), os.path.join(t, "bluez.log")
        os.makedirs(self.runtime)
        env = dict(os.environ, JOYMANAGER_RUNTIME_DIR=self.runtime, UJM_BRIDGE_STATE_DIR=self.data, UJM_BUS="session",
                   UJM_TEST_AUTH=auth, UJM_BRIDGE_IDLE_EXIT=idle_exit, UJM_ACK_TIMEOUT=ack_timeout, FAKE_BLUEZ_LOG=self.log)
        self.service = None
        if service:
            self.service = subprocess.Popen([sys.executable, FAKE_SERVICE], env=env, stdout=subprocess.PIPE, text=True)
            assert self.service.stdout.readline().strip() == "READY"
        self.bluez = subprocess.Popen([sys.executable, FAKE], env=env, stdout=subprocess.PIPE, text=True)
        assert self.bluez.stdout.readline().strip() == "READY"
        self.bridge = subprocess.Popen([sys.executable, BRIDGE], env=env, stdout=subprocess.PIPE, text=True)
        assert self.bridge.stdout.readline().strip() == "READY"
        self.conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)

    def write_state(self, data):
        tmp = os.path.join(self.runtime, "state.json.tmp")
        with open(tmp, "w", encoding="utf-8") as fh:
            fh.write(data if isinstance(data, str) else json.dumps(data))
        os.replace(tmp, os.path.join(self.runtime, "state.json"))

    def call(self, method, args=None, sig=None):
        params = GLib.Variant(sig, args) if sig else None
        res = self.conn.call_sync(NAME, PATH, IFACE, method, params, None, Gio.DBusCallFlags.NONE, 10000, None)
        return res.unpack()

    def prop(self, name):
        res = self.conn.call_sync(NAME, PATH, "org.freedesktop.DBus.Properties", "Get",
                                  GLib.Variant("(ss)", (IFACE, name)), None, Gio.DBusCallFlags.NONE, 5000, None)
        return res.unpack()[0]

    def service_log(self):
        try:
            with open(os.path.join(self.runtime, "service.log"), encoding="utf-8") as fh:
                return [line.split("\t") for line in fh.read().split("\n")[:-1]]
        except OSError:
            return []

    def set_service_mode(self, mode):
        path = os.path.join(self.runtime, "service.mode")
        if mode:
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(mode)
        elif os.path.exists(path):
            os.remove(path)

    def bluez_log(self):
        try:
            with open(self.log, encoding="utf-8") as fh:
                return fh.read().split("\n")[:-1]
        except OSError:
            return []

    def close(self):
        for p in (self.bridge, self.bluez, self.service):
            if p is None:
                continue
            if p.poll() is None:
                p.terminate()
            p.wait(5)
            p.stdout.close()
        self.tmp.cleanup()


class AllowedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.env = Env("allow")

    @classmethod
    def tearDownClass(cls):
        cls.env.close()

    def setUp(self):
        self.env.write_state(STATE)
        self.env.call("ListControllers")  # make sure the bridge has seen it

    def raises(self, name, fn, *a, **k):
        with self.assertRaises(GLib.Error) as cm:
            fn(*a, **k)
        self.assertIn(name, Gio.DBusError.get_remote_error(cm.exception) or "")

    def test_version_and_status(self):
        self.assertEqual(self.env.prop("Version"), "1")
        self.assertTrue(self.env.prop("StateAvailable"))
        status = self.env.call("GetServiceStatus")[0]
        self.assertEqual((status["state_available"], status["idle_timeout"], status["led_refresh"]), (True, 1800, "10"))

    def test_controllers_are_republished(self):
        pump(lambda: len(self.env.call("ListControllers")[0]) == 3)
        c = {x["id"]: x for x in self.env.call("ListControllers")[0]}
        pro = c[PRO]
        self.assertEqual((pro["name"], pro["player"], pro["transport"], pro["address"]), ("Pro Controller", 1, "bluetooth", PRO))
        self.assertEqual((pro["battery_percent"], pro["battery_status"], pro["battery_level"]), (55, "Charging", "normal"))
        self.assertEqual(pro["player_led_mask"], 1)
        self.assertNotIn("address", c["joycond:event5"])
        self.assertNotIn("battery_percent", c["joycond:event5"])
        self.assertEqual(self.env.call("GetController", (PRO,), "(s)")[0]["name"], "Pro Controller")
        self.raises("UnknownController", self.env.call, "GetController", ("nobody",), "(s)")

    def test_snapshot_json_matches_the_typed_methods(self):
        snap = json.loads(self.env.call("GetSnapshotJson")[0])
        typed = self.env.call("ListControllers")[0]
        self.assertEqual(snap["api_version"], "1")
        self.assertEqual(snap["service"]["idle_timeout"], 1800)
        self.assertEqual([c["id"] for c in snap["controllers"]], [c["id"] for c in typed])
        pro = next(c for c in snap["controllers"] if c["id"] == PRO)
        self.assertEqual((pro["name"], pro["battery_percent"], pro["address"]), ("Pro Controller", 55, PRO))

    def test_signal_when_the_service_replaces_state_json(self):
        got = []
        sub = self.env.conn.signal_subscribe(NAME, IFACE, "ControllersChanged", PATH, None, Gio.DBusSignalFlags.NONE,
                                             lambda *a: got.append(1))
        changed = json.loads(json.dumps(STATE))
        changed["controllers"].pop(1)
        self.env.write_state(changed)
        self.assertTrue(pump(lambda: got), "no ControllersChanged after state.json was replaced")
        self.assertEqual(len(self.env.call("ListControllers")[0]), 2)
        self.env.conn.signal_unsubscribe(sub)

    def test_unreadable_or_foreign_state_is_not_a_crash(self):
        for bad in ("{not json", json.dumps({"format": "other", "version": 1}), json.dumps({"format": "ujm-state", "version": 99})):
            self.env.write_state(bad)
            self.assertTrue(pump(lambda: not self.env.prop("StateAvailable")), bad)
            self.assertEqual(self.env.call("ListControllers")[0], [])
        os.remove(os.path.join(self.env.runtime, "state.json"))
        self.assertTrue(pump(lambda: not self.env.prop("StateAvailable")))

    def test_alias_is_stored_sanitized_and_cleared(self):
        self.env.call("SetControllerAlias", (PRO, "Sala \x07 do\nJoão"), "(ss)")
        pro = self.env.call("GetController", (PRO,), "(s)")[0]
        self.assertEqual(pro["alias"], "Sala  doJoão")
        saved = json.load(open(os.path.join(self.env.data, "aliases.json"), encoding="utf-8"))
        self.assertEqual(saved["aliases"][PRO], "Sala  doJoão")
        self.assertEqual(oct(os.stat(os.path.join(self.env.data, "aliases.json")).st_mode & 0o777), "0o644")
        self.env.call("SetControllerAlias", (PRO, "x" * 200), "(ss)")
        self.assertEqual(len(self.env.call("GetController", (PRO,), "(s)")[0]["alias"]), 40)
        self.env.call("SetControllerAlias", (PRO, ""), "(ss)")
        self.assertNotIn("alias", self.env.call("GetController", (PRO,), "(s)")[0])

    def test_alias_refused_without_a_stable_address_or_for_unknown_ids(self):
        self.raises("InvalidArgs", self.env.call, "SetControllerAlias", ("joycond:event5", "pair"), "(ss)")
        self.raises("UnknownController", self.env.call, "SetControllerAlias", ("AA:AA:AA:AA:AA:AA", "ghost"), "(ss)")

    def test_connect_and_disconnect_go_to_bluez(self):
        before = len(self.env.bluez_log())
        self.env.call("DisconnectBluetooth", (PRO,), "(s)")
        self.env.call("ConnectBluetooth", (PRO,), "(s)")
        calls = self.env.bluez_log()[before:]
        self.assertEqual([c for c in calls if c.startswith("Device.")], ["Device.Disconnect", "Device.Connect"])

    def test_only_bluetooth_controllers_can_be_connected(self):
        self.raises("InvalidArgs", self.env.call, "DisconnectBluetooth", ("joycond:event5",), "(s)")  # virtual pair
        self.raises("UnknownController", self.env.call, "ConnectBluetooth", ("nobody",), "(s)")      # neither an id nor an address

    def test_a_controller_that_dropped_can_be_reconnected_by_its_address(self):
        # it is not in the controller list any more, so its id no longer exists; the address still does
        self.env.write_state({**STATE, "controllers": []})
        self.assertTrue(pump(lambda: self.env.call("ListControllers")[0] == []))
        before = len(self.env.bluez_log())
        self.env.call("ConnectBluetooth", (PRO.lower(),), "(s)")
        self.assertIn("Device.Connect", self.env.bluez_log()[before:])
        self.raises("UnknownController", self.env.call, "ConnectBluetooth", ("AA:BB:CC:DD:EE",), "(s)")  # five bytes: not an address

    def test_bluez_errors_are_passed_on(self):
        open(self.env.log + ".fail-connect", "w").close()
        try:
            self.raises("Failed", self.env.call, "ConnectBluetooth", (PRO,), "(s)")
        finally:
            os.remove(self.env.log + ".fail-connect")

    def test_pair_pairs_trusts_then_connects(self):
        before = len(self.env.bluez_log())
        self.env.call("PairBluetooth", (PRO.lower(),), "(s)")
        calls = [c for c in self.env.bluez_log()[before:] if c.startswith("Device.")]
        self.assertEqual(calls, ["Device.Pair", "Device.Set Trusted=True", "Device.Connect"])
        self.raises("InvalidArgs", self.env.call, "PairBluetooth", ("not-an-address",), "(s)")
        with self.assertRaises(GLib.Error) as cm:  # BlueZ has no such device: say so, not "method doesn't exist"
            self.env.call("PairBluetooth", ("AA:BB:CC:DD:EE:FF",), "(s)")
        self.assertEqual(Gio.DBusError.get_remote_error(cm.exception), "org.ujm.Manager1.Error.UnknownDevice")
        self.assertIn("pair it first", cm.exception.message)

    def test_scan_starts_and_stops_by_itself(self):
        before = len(self.env.bluez_log())
        self.env.call("ScanBluetooth", (1,), "(u)")
        self.assertTrue(pump(lambda: "Adapter.StopDiscovery" in self.env.bluez_log()[before:], 4))
        calls = [c for c in self.env.bluez_log()[before:] if c.startswith("Adapter.")]
        self.assertEqual(calls, ["Adapter.StartDiscovery", "Adapter.StopDiscovery"])

    def test_bluetooth_devices_are_listed_with_a_gamepad_flag(self):
        devs = {d["address"]: d for d in self.env.call("ListBluetoothDevices")[0]}
        self.assertTrue(devs[PRO]["gamepad"])
        self.assertFalse(devs["11:22:33:44:55:66"]["gamepad"])

    def test_idle_timeout_goes_to_the_service(self):
        before = len(self.env.service_log())
        self.env.call("SetIdleTimeout", (120,), "(u)")
        self.env.call("SetIdleTimeout", (0,), "(u)")
        self.assertEqual(self.env.service_log()[before:], [["idle_timeout", "120"], ["idle_timeout", "0"]])
        for bad in (1, 59, 86401, 4000000000):
            self.raises("InvalidArgs", self.env.call, "SetIdleTimeout", (bad,), "(u)")
        self.assertEqual(len(self.env.service_log()), before + 2)

    def test_player_leds_go_to_the_service(self):
        before = len(self.env.service_log())
        self.env.call("SetPlayerLeds", (PRO, 12), "(su)")
        self.env.call("SetPlayerLeds", (PRO, 255), "(su)")
        self.assertEqual(self.env.service_log()[before:], [["player_leds", PRO, "12"], ["player_leds", PRO, "255"]])
        self.raises("InvalidArgs", self.env.call, "SetPlayerLeds", (PRO, 16), "(su)")
        self.raises("InvalidArgs", self.env.call, "SetPlayerLeds", (PRO, 254), "(su)")
        self.raises("InvalidArgs", self.env.call, "SetPlayerLeds", ("joycond:event5", 3), "(su)")  # the virtual pair
        self.raises("InvalidArgs", self.env.call, "SetPlayerLeds", ("30:2C:3A:00:00:02", 3), "(su)")  # reports no player LEDs
        self.raises("UnknownController", self.env.call, "SetPlayerLeds", ("AA:AA:AA:AA:AA:AA", 3), "(su)")
        self.assertEqual(len(self.env.service_log()), before + 2)

    def test_home_led_goes_to_the_service(self):
        before = len(self.env.service_log())
        self.env.call("SetHomeLed", (PRO, False), "(sb)")
        self.env.call("SetHomeLed", (PRO, True), "(sb)")
        self.assertEqual(self.env.service_log()[before:], [["home_led", PRO, "off"], ["home_led", PRO, "on"]])
        self.raises("InvalidArgs", self.env.call, "SetHomeLed", ("30:2C:3A:00:00:02", True), "(sb)")  # reported unsupported
        self.assertEqual(len(self.env.service_log()), before + 2)

    def test_a_lower_case_address_still_counts_as_an_address(self):
        # a DualShock 3 reports its HID uniq in lower case; BlueZ paths are upper case
        low = json.loads(json.dumps(STATE))
        low["controllers"][0]["id"] = PRO.lower()
        self.env.write_state(low)
        self.assertTrue(pump(lambda: self.env.call("ListControllers")[0][0]["id"] == PRO.lower()))
        self.assertEqual(self.env.call("GetController", (PRO.lower(),), "(s)")[0]["address"], PRO.lower())
        before = len(self.env.bluez_log())
        self.env.call("ConnectBluetooth", (PRO.lower(),), "(s)")
        self.assertIn("Device.Connect", self.env.bluez_log()[before:])
        self.env.call("SetControllerAlias", (PRO.lower(), "ds3"), "(ss)")
        self.assertEqual(self.env.call("GetController", (PRO.lower(),), "(s)")[0]["alias"], "ds3")

    def test_the_led_state_is_published(self):
        c = {x["id"]: x for x in self.env.call("ListControllers")[0]}
        self.assertEqual((c[PRO]["home_led"], c[PRO]["player_led_manual"]), ("on", False))
        self.assertEqual(c["30:2C:3A:00:00:02"]["home_led"], "unsupported")
        self.assertNotIn("home_led", c["joycond:event5"])

    def test_a_refusal_by_the_service_is_passed_on_with_its_reason(self):
        self.env.set_service_mode("reject")
        try:
            with self.assertRaises(GLib.Error) as cm:
                self.env.call("SetPlayerLeds", (PRO, 3), "(su)")
            self.assertEqual(Gio.DBusError.get_remote_error(cm.exception), "org.ujm.Manager1.Error.Rejected")
            self.assertIn("nope, said the service", cm.exception.message)
        finally:
            self.env.set_service_mode("")


class DeniedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.env = Env("deny")
        cls.env.write_state(STATE)

    @classmethod
    def tearDownClass(cls):
        cls.env.close()

    def test_nothing_changes_without_authorization(self):
        pump(lambda: len(self.env.call("ListControllers")[0]) == 3)
        for method, args, sig in (("SetControllerAlias", (PRO, "x"), "(ss)"), ("ConnectBluetooth", (PRO,), "(s)"),
                                  ("DisconnectBluetooth", (PRO,), "(s)"), ("PairBluetooth", (PRO,), "(s)"),
                                  ("ScanBluetooth", (5,), "(u)"), ("SetIdleTimeout", (120,), "(u)"),
                                  ("SetPlayerLeds", (PRO, 3), "(su)"), ("SetHomeLed", (PRO, False), "(sb)")):
            with self.assertRaises(GLib.Error) as cm:
                self.env.call(method, args, sig)
            self.assertIn("AccessDenied", Gio.DBusError.get_remote_error(cm.exception), method)
        self.assertFalse(os.path.exists(os.path.join(self.env.data, "aliases.json")))
        self.assertEqual(self.env.service_log(), [])
        self.assertEqual([c for c in self.env.bluez_log() if c.startswith(("Device.", "Adapter."))], [])
        self.assertEqual(len(self.env.call("ListControllers")[0]), 3)  # reads need no authorization


class PolkitTests(unittest.TestCase):
    """UJM_TEST_AUTH empty: the bridge asks (a fake) polkit about the caller's bus name, as in production."""

    @classmethod
    def setUpClass(cls):
        cls.env = Env("")
        cls.env.write_state(STATE)
        pump(lambda: len(cls.env.call("ListControllers")[0]) == 3)

    @classmethod
    def tearDownClass(cls):
        cls.env.close()

    def test_asks_polkit_about_the_caller_and_the_action(self):
        self.env.call("SetControllerAlias", (PRO, "Sala"), "(ss)")
        self.env.call("ConnectBluetooth", (PRO,), "(s)")
        asked = [c for c in self.env.bluez_log() if c.startswith("Polkit")]
        me = self.env.conn.get_unique_name()
        self.assertEqual(asked[-2:], [f"Polkit org.ujm.manager.set-alias system-bus-name={me} flags=1",
                                      f"Polkit org.ujm.manager.bluetooth system-bus-name={me} flags=1"])

    def test_service_actions_ask_for_their_own_polkit_actions(self):
        self.env.call("SetPlayerLeds", (PRO, 3), "(su)")
        self.env.call("SetHomeLed", (PRO, True), "(sb)")
        self.env.call("SetIdleTimeout", (300,), "(u)")
        asked = [c.split()[1] for c in self.env.bluez_log() if c.startswith("Polkit")]
        self.assertEqual(asked[-3:], ["org.ujm.manager.leds", "org.ujm.manager.leds", "org.ujm.manager.configure"])

    def test_reads_do_not_ask_polkit(self):
        before = len([c for c in self.env.bluez_log() if c.startswith("Polkit")])
        self.env.call("ListControllers")
        self.env.call("GetServiceStatus")
        self.assertEqual(len([c for c in self.env.bluez_log() if c.startswith("Polkit")]), before)

    def test_polkit_refusal_blocks_the_action(self):
        open(self.env.log + ".polkit-deny", "w").close()
        try:
            with self.assertRaises(GLib.Error) as cm:
                self.env.call("DisconnectBluetooth", (PRO,), "(s)")
            self.assertIn("AccessDenied", Gio.DBusError.get_remote_error(cm.exception))
            self.assertNotIn("Device.Disconnect", self.env.bluez_log()[-3:])
        finally:
            os.remove(self.env.log + ".polkit-deny")


class ServiceProblemTests(unittest.TestCase):
    """The command channel when the service is silent, absent, or not reading."""

    def call_error(self, env, method="SetIdleTimeout", args=(120,), sig="(u)"):
        with self.assertRaises(GLib.Error) as cm:
            env.call(method, args, sig)
        return Gio.DBusError.get_remote_error(cm.exception), cm.exception.message

    def test_a_silent_service_times_out(self):
        env = Env("allow", ack_timeout="1")
        self.addCleanup(env.close)
        env.write_state(STATE)
        env.set_service_mode("silent")
        started = time.monotonic()
        name, _ = self.call_error(env)
        self.assertEqual(name, "org.ujm.Manager1.Error.ServiceTimeout")
        self.assertTrue(1 <= time.monotonic() - started < 4)

    def test_no_command_channel_means_service_unavailable(self):
        env = Env("allow", service=False)
        self.addCleanup(env.close)
        env.write_state(STATE)
        name, message = self.call_error(env)
        self.assertEqual(name, "org.ujm.Manager1.Error.ServiceUnavailable")
        self.assertIn("older version", message)
        self.assertEqual(env.call("GetServiceStatus")[0]["idle_timeout"], 1800)  # reads keep working

    def test_a_fifo_nobody_reads_means_service_unavailable(self):
        env = Env("allow", service=False)
        self.addCleanup(env.close)
        env.write_state(STATE)
        os.mkfifo(os.path.join(env.runtime, "command.fifo"), 0o600)  # the service died and left it
        name, message = self.call_error(env)
        self.assertEqual(name, "org.ujm.Manager1.Error.ServiceUnavailable")
        self.assertIn("not reading", message)


class LifetimeTests(unittest.TestCase):
    def test_exits_by_itself_when_nobody_uses_it(self):
        env = Env("allow", idle_exit="2")
        try:
            env.bridge.wait(8)
        except subprocess.TimeoutExpired:
            self.fail("the bridge did not exit when nobody called it")
        finally:
            env.close()

    def test_stays_while_a_caller_is_connected_then_exits(self):
        env = Env("allow", idle_exit="2")
        try:
            holder = subprocess.Popen([sys.executable, "-c", (
                "import gi,time;gi.require_version('Gio','2.0');from gi.repository import Gio;"
                "c=Gio.bus_get_sync(Gio.BusType.SESSION,None);"
                "c.call_sync('org.ujm.Manager1','/org/ujm/Manager1','org.ujm.Manager1','GetServiceStatus',None,None,0,5000,None);"
                "print('called',flush=True);time.sleep(30)")], stdout=subprocess.PIPE, text=True)
            self.assertEqual(holder.stdout.readline().strip(), "called")
            time.sleep(4)
            self.assertIsNone(env.bridge.poll(), "exited while a caller was still connected")
            holder.kill()
            holder.wait()
            try:
                env.bridge.wait(8)
            except subprocess.TimeoutExpired:
                self.fail("did not exit after the last caller left")
        finally:
            env.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
