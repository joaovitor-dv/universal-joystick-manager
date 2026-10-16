# Architecture

## Flow

```text
Linux drivers / Bluetooth / USB
          |
          v
  joystickmanager.service ---- joycond (optional)
          |
          +--> global numbering
          +--> LEDs and battery
          +--> Bluetooth idle timeout
          +--> USB/Bluetooth duplicate filter
          v
      games / Steam
```

## Decisions

1. Player identity is assigned by connection order, not by MAC address.
2. The initial logical limit is eight players; the four-position LEDs use masks for players 5-8.
3. Player state is ephemeral and must be cleared when the device disappears.
4. `joycond` creates the virtual pair; the manager coordinates numbering and synchronizes the presentation of the two Joy-Cons.
5. Battery is only shown when the kernel or the driver provides a reliable source.
6. The Xbox 360 takes part in numbering but will not have battery measurement.
7. USB interfaces that belong to the same Bluetooth controller will be treated as charging when the identity can be confirmed.
8. On the Switch Pro Controller, a USB data cable makes the firmware switch from Bluetooth to USB. To keep Bluetooth while charging, use a charge-only cable, or deauthorize the USB device (`echo 0 > /sys/bus/usb/devices/<port>/authorized`): validated by hand on hardware, the controller stayed on Bluetooth and `Charging`. The opt-in udev rule in `udev/` automates this, but it has **not been tested** and it disables wired use.
9. Steam Input must not create a second device for the combined Joy-Cons.
10. Recognized controllers come from `controllers.tsv` (input name, vendor, expected driver, state). Only the `validated` state is active by default; without the table, the service uses a fixed list of validated controllers.
11. The Bluetooth adapter must be `connectable` for controllers such as the Pro Controller to reconnect with HOME; the service re-asserts the mode periodically because `bluetoothd` may clear it on restart.
12. LEDs are re-applied every `JOYMANAGER_LED_REFRESH` s (default 10), not on every 2 s cycle: each write is an HID subcommand, and rewriting everything on every cycle made the Pro Controller drop by timeout. Real changes (charging, battery) are written immediately.

## Limits

The service alone cannot prevent the firmware from switching to USB when a data cable is plugged in; that is only avoided by deauthorizing the USB device or by using a charge-only cable. It also cannot guarantee that a Joy-Con clone implements the protocol `joycond` expects. With `joycond`, blinking LEDs may indicate pending logical pairing; Pro Controllers must receive **L + R**, and a combined virtual pair of Joy-Cons must receive **+ and -**.

## Untested future extensions

- Xbox 360, Xbox One and Xbox Series X/S.
- DualShock 4 and DualSense.
- Nintendo Switch 2 Pro Controller.
- Nintendo Switch 2 Joy-Con.
- 8BitDo controllers.
- GameSir controllers.

These models will only be marked as supported after tests with real hardware and confirmation of the battery, LED, input and connection paths.

The same criterion applies to each specific model within the 8BitDo and GameSir brands. XInput, DInput, Switch, Bluetooth, USB and proprietary receiver modes must be validated separately.
