#!/usr/bin/env python3
"""Set fixed player LEDs on Nintendo Switch Pro Controllers via HID."""

from __future__ import annotations

import argparse
import glob
import os
import re
import sys
import time

PREFIX_RE = re.compile(r"^0005:057E:2009\.[0-9A-Fa-f]+$")


def hidraw_for_prefix(prefix: str) -> str | None:
    fallback = None
    for hidraw in glob.glob("/sys/class/hidraw/hidraw*"):
        path = os.path.realpath(os.path.join(hidraw, "device"))
        while path != "/":
            if os.path.basename(path) == prefix:
                device = "/dev/" + os.path.basename(hidraw)
                name_path = os.path.join(hidraw, "device", "name")
                try:
                    name = open(name_path, encoding="utf-8").read().strip()
                except OSError:
                    name = ""
                if name == "Pro Controller":
                    return device
                fallback = fallback or device
            path = os.path.dirname(path)
    return fallback


def hidraw_for_id(controller_id: str) -> str | None:
    wanted = controller_id.strip().upper()
    for hidraw in glob.glob("/sys/class/hidraw/hidraw*"):
        for uniq_path in glob.glob(os.path.join(hidraw, "device", "input", "*", "uniq")):
            try:
                if open(uniq_path, encoding="utf-8").read().strip().upper() == wanted:
                    return "/dev/" + os.path.basename(hidraw)
            except OSError:
                continue
    return None


def send_player_lights(device: str, mask: int) -> None:
    # The controller uses the low nibble as an output-report sequence.
    sequence = (time.monotonic_ns() // 1_000_000) & 0x0F
    payload = bytes((0x01, sequence, 0x00, 0x01, 0x40, 0x40, 0x00, 0x01,
                     0x40, 0x40, 0x30, mask & 0x0F))
    fd = os.open(device, os.O_WRONLY | os.O_NONBLOCK)
    try:
        written = os.write(fd, payload)
        if written != len(payload):
            raise OSError(f"short HID write: {written}/{len(payload)}")
    finally:
        os.close(fd)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--prefix", required=True)
    parser.add_argument("--id")
    parser.add_argument("--mask", required=True, type=lambda value: int(value, 0))
    args = parser.parse_args()
    if not PREFIX_RE.fullmatch(args.prefix) or not 0 <= args.mask <= 0x0F:
        return 2
    device = hidraw_for_id(args.id) if args.id else None
    device = device or hidraw_for_prefix(args.prefix)
    if device is None:
        return 0
    try:
        send_player_lights(device, args.mask)
    except OSError as exc:
        print(f"switchpro-leds: {device}: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
