# UJM — Universal Joystick Manager

UJM is a Linux service for unified game controller management on Arch Linux/CachyOS.

> **Naming:** UJM is the product name. The technical identifiers (`joystickmanager.sh`, `joystickmanager.service`, `joystickmanager-doctor`, `JOYMANAGER_*`, `/run/joystickmanager`) keep their current names for now.

## Approved scope

- Global numbering by connection order, up to eight players.
- Initial/testable implementation: original DS3, original Switch Pro and original/third-party Joy-Con.
- Planned support for Xbox 360, Xbox One, Xbox Series X/S, DualShock 4 and DualSense.
- Planned future support for the Nintendo Switch 2 Pro Controller and Joy-Con 2.
- Planned experimental support for 8BitDo and GameSir controllers.
- USB and Bluetooth controllers, with Joy-Con over Bluetooth only.
- `joycond` as an optional component to combine a pair of Joy-Cons into a single virtual device.
- Player LEDs, battery indication when the driver exposes it, and automatic power-off for Bluetooth only.
- Automatic power-off is initially set to 30 minutes (`JOYMANAGER_IDLE_TIMEOUT=1800`) during the testing phase.
- LEDs are re-applied every 10 s (`JOYMANAGER_LED_REFRESH=10`; `0` re-applies on every 2 s cycle). Each LED write is an HID subcommand, and rewriting everything every 2 s overloaded the Pro Controller (`exceeded max attempts` errors and drops caused by `timeout waiting for input report`). Real changes, such as starting to charge, are written immediately.
- Bluetooth is kept when the same controller is also connected over USB for charging, when the firmware allows it.
- Integration with Steam Input without duplicate devices.
- Planned cross-distribution compatibility through an explicit dependency matrix.

### Pro Controller: USB and Bluetooth

The Switch Pro Controller may switch from Bluetooth to USB when a data cable is
connected to the computer. In that case the firmware may drop the Bluetooth
connection, and `joystickmanager` on its own cannot prevent that switch (see the
next section for a workaround). To charge without replacing the Bluetooth
transport, use a charge-only cable, an adapter without data lines, or a
charger/hub that does not expose USB to the computer.

When `joycond` is active, the player LEDs may blink while the controller waits
for logical pairing. Press **L + R** simultaneously on each Pro Controller to
complete that pairing; for a virtual device made of combined Joy-Cons, use
**+ and -**.

## Charging the Pro Controller without losing Bluetooth

Plugging the Pro Controller in with a **data** cable makes the firmware abandon Bluetooth. The service alone does not prevent this. What worked by hand on hardware was deauthorizing the USB device (`echo 0 | sudo tee /sys/bus/usb/devices/<port>/authorized`): the controller returned to Bluetooth and kept charging. The optional rule [`udev/99-joystickmanager-procontroller-charge-only.rules`](udev/99-joystickmanager-procontroller-charge-only.rules) does this automatically, with `sudo ./install.sh --pro-charge-only`.

Limitations: with the rule the controller **does not work wired**; the kernel has already enumerated the device by the time udev runs, so the controller may leave Bluetooth for a moment when the cable is plugged in; the rule itself has not been tested on hardware yet. A charge-only cable remains the solution without caveats.

## Current state

The initial unified service is in `joystickmanager.sh` and `joystickmanager.service`. The other scripts are the historical per-model implementation and remain until the unified version is validated on real hardware.

## Available test matrix

| Hardware | Quantity | Available connections |
|---|---:|---|
| Original DualShock 3 | 1 | Bluetooth and USB |
| Original Switch Pro | 2 | Bluetooth and USB |
| Original Joy-Con | 1 pair | Bluetooth |
| Third-party Joy-Con | 1 pair | Bluetooth |

Xbox, DualShock 4, DualSense and Switch 2 controllers are documented as future changes and will not be declared compatible without hardware to validate them.

8BitDo, GameSir, Logitech, Razer, Redragon and XInput clones enter this experimental branch as unvalidated support families, described in [`controllers.tsv`](controllers.tsv). They are only active with `JOYMANAGER_EXPERIMENTAL=1`; `joystickmanager-doctor` shows the kernel drivers and which profile each connected controller matched. Compatibility will depend on the model, connection mode and the driver Linux presents; it will not be assumed from the brand alone.

## Planned installation

Installation will be documented after support for each family is validated. Do not install the individual services and the unified service at the same time.

Per-distribution dependencies are in [`docs/dependencies.md`](docs/dependencies.md). The first version of the service targets distributions with systemd, udev, D-Bus and BlueZ; `joycond`, `upower` and test tools are optional depending on use.

There is also a common installer in `install.sh` and initial metadata in `packaging/arch`, `packaging/debian` and `packaging/fedora`. The installer does not install external drivers or `joycond` automatically.

To take part in testing controllers that are not yet available, see [`docs/volunteer-testing.md`](docs/volunteer-testing.md).

## License

MIT. See `LICENSE`.
