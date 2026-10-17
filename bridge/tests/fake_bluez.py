#!/usr/bin/env python3
"""A stand-in for BlueZ on the test session bus. Logs every call to $FAKE_BLUEZ_LOG."""
import os
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

LOG = os.environ["FAKE_BLUEZ_LOG"]
ADAPTER = "/org/bluez/hci0"
DEVICE = ADAPTER + "/dev_20_1C_3A_00_00_01"


def log(line):
    with open(LOG, "a", encoding="utf-8") as fh:
        fh.write(line + "\n")


def V(sig, val):
    return GLib.Variant(sig, val)


def managed():
    objs = {
        ADAPTER: {"org.bluez.Adapter1": {"Address": V("s", "00:11:22:33:44:55"), "Powered": V("b", True)}},
        DEVICE: {"org.bluez.Device1": {"Address": V("s", "20:1C:3A:00:00:01"), "Alias": V("s", "Pro Controller"),
                                       "Paired": V("b", False), "Connected": V("b", False),
                                       "Icon": V("s", "input-gaming")}},
        ADAPTER + "/dev_11_22_33_44_55_66": {"org.bluez.Device1": {"Address": V("s", "11:22:33:44:55:66"),
                                                                    "Alias": V("s", "Headphones"), "Paired": V("b", True),
                                                                    "Connected": V("b", False), "Icon": V("s", "audio-headset")}},
    }
    return GLib.Variant("(a{oa{sa{sv}}})", (objs,))


def make(iface_xml, name, handler):
    return Gio.DBusNodeInfo.new_for_xml(iface_xml).lookup_interface(name), handler


def main():
    conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)

    def om(c, sender, path, iface, method, params, inv):
        log(f"{method}")
        inv.return_value(managed())

    def adapter(c, sender, path, iface, method, params, inv):
        log(f"Adapter.{method}")
        inv.return_value(None)

    def device(c, sender, path, iface, method, params, inv):
        if method == "Set":
            args = params.unpack()
            log(f"Device.Set {args[1]}={args[2]}")
        else:
            log(f"Device.{method}")
            if method == "Connect" and os.path.exists(LOG + ".fail-connect"):
                return inv.return_dbus_error("org.bluez.Error.Failed", "page timeout")
        inv.return_value(None)

    xml_om = '<node><interface name="org.freedesktop.DBus.ObjectManager"><method name="GetManagedObjects"><arg direction="out" type="a{oa{sa{sv}}}"/></method></interface></node>'
    xml_ad = '<node><interface name="org.bluez.Adapter1"><method name="StartDiscovery"/><method name="StopDiscovery"/></interface></node>'
    xml_dev = ('<node><interface name="org.bluez.Device1"><method name="Pair"/><method name="Connect"/><method name="Disconnect"/></interface>'
               '<interface name="org.freedesktop.DBus.Properties"><method name="Set"><arg direction="in" type="s"/><arg direction="in" type="s"/><arg direction="in" type="v"/></method></interface></node>')
    conn.register_object("/", Gio.DBusNodeInfo.new_for_xml(xml_om).interfaces[0], om, None, None)
    conn.register_object(ADAPTER, Gio.DBusNodeInfo.new_for_xml(xml_ad).interfaces[0], adapter, None, None)
    for iface in Gio.DBusNodeInfo.new_for_xml(xml_dev).interfaces:
        conn.register_object(DEVICE, iface, device, None, None)
    def polkit(c, sender, path, iface, method, params, inv):
        (kind, details), action, _d, flags, _cancel = params.unpack()
        log(f"Polkit {action} {kind}={details['name']} flags={flags}")
        allowed = not os.path.exists(LOG + ".polkit-deny")
        inv.return_value(GLib.Variant("((bba{ss}))", ((allowed, False, {}),)))

    xml_pk = ('<node><interface name="org.freedesktop.PolicyKit1.Authority"><method name="CheckAuthorization">'
              '<arg direction="in" type="(sa{sv})"/><arg direction="in" type="s"/><arg direction="in" type="a{ss}"/>'
              '<arg direction="in" type="u"/><arg direction="in" type="s"/><arg direction="out" type="(bba{ss})"/>'
              '</method></interface></node>')
    conn.register_object("/org/freedesktop/PolicyKit1/Authority", Gio.DBusNodeInfo.new_for_xml(xml_pk).interfaces[0], polkit, None, None)
    Gio.bus_own_name_on_connection(conn, "org.freedesktop.PolicyKit1", Gio.BusNameOwnerFlags.NONE, None, None)
    loop = GLib.MainLoop()
    Gio.bus_own_name_on_connection(conn, "org.bluez", Gio.BusNameOwnerFlags.NONE, lambda c, n: print("READY", flush=True), None)
    loop.run()


if __name__ == "__main__":
    sys.exit(main())
