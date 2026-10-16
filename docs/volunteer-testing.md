# Volunteer testing program

The project needs people who own controllers that are not available for local validation. The goal is to test detection, input, numbering, battery, LEDs, Bluetooth, USB and wireless receivers without requiring remote access to the volunteer's computer.

## Families we are looking for

- 8BitDo: Ultimate, Pro 2, SN30, SN30 Pro, M30, Zero, Lite and other models.
- GameSir: T4, T4 Pro, T4 Kaleid, Nova, G7, Cyclone and other models.
- Xbox 360, Xbox One and Xbox Series X/S.
- DualShock 4 and DualSense.
- Nintendo Switch 2 Pro Controller and Joy-Con 2.

## What the volunteer needs to report

- distribution and kernel version;
- exact model and revision, if available;
- connection used: USB, Bluetooth or receiver;
- whether the controller appears as XInput, DInput, Switch or another mode;
- whether it has player LEDs, RGB, a battery indicator or none of them;
- whether the controller uses batteries, an internal battery or a removable battery.

Do not publish a full MAC address, serial number, user name, personal path or logs that contain them. Replace identifiers with `XX` before sending.

## Safe collection

Run the commands below with the controller connected:

```text
uname -a
cat /proc/bus/input/devices
lsusb
bluetoothctl devices Connected
```

To test input, use `evtest` only on the `/dev/input/eventN` that corresponds to the controller. Do not send the contents of other devices.

## Expected result

The volunteer should report:

1. whether the controller was detected;
2. which name and mode appeared;
3. which buttons and axes worked;
4. whether the controller received a player number from 1 to 8;
5. whether the battery appeared;
6. whether LEDs or RGB responded;
7. whether there was duplication between USB/Bluetooth, Steam Input or the receiver.

A model is only promoted from experimental to validated after at least one reproducible, documented test.
