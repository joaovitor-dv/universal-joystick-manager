# Dependencies by distribution

## First-version target

The first version supports Linux distributions with:

- a Linux kernel with `evdev`, `joydev` and the controller drivers;
- `udev` to detect connection and disconnection;
- `systemd` to run the service;
- `dbus` and BlueZ for Bluetooth;
- `uinput` when `joycond`'s virtual controller needs to be created.

Distributions without systemd can use the script directly, but they are not a target of the current `.service` unit.

## Dependencies

| Component | Required | Role |
|---|---:|---|
| Linux kernel | Yes | Input, USB, Bluetooth HID and controller drivers |
| `udev`/`systemd-udev` | Yes | Connection events and device identification |
| `systemd` | Yes in the first version | Start and restart `joystickmanager` |
| `dbus` | Yes for Bluetooth | BlueZ communication |
| `bluez`/`bluetoothd` | For Bluetooth | Pairing, connection and disconnection |
| `bluez-utils` or equivalent | For diagnostics | `bluetoothctl` and helper tools |
| `joycond` | Optional | Combine two Joy-Cons into one virtual controller |
| `uinput` | For `joycond` | Create the combined virtual controller |
| `evtest` | Testing only | Check buttons and axes before games |
| `jstest-gtk`/`joystick` | Testing only | Check the joystick API |
| `upower` | Optional | Show the battery on the desktop; not required by the manager |

## Kernel drivers

The single source of truth for which controllers the service recognizes, and which
driver is expected for each, is [`controllers.tsv`](../controllers.tsv). To check what
your system has, run:

```text
joystickmanager-doctor
```

It only reads the system: for each family it shows whether each kernel module is
loaded, available or absent, and which connected controllers matched a profile.

| Family | State | Expected module |
|---|---|---|
| DualShock 3 | validated | `hid_sony` |
| Switch Pro and Joy-Con | validated | `hid_nintendo` |
| Virtual controller (`joycond`) | validated | `uinput` |
| Xbox 360, One, Series (wired) | experimental | `xpad` |
| Xbox over Bluetooth | experimental | `hid_microsoft`; `xpadneo` (external, optional) |
| Xbox wireless receiver | experimental | `xone` (external, optional) |
| DualShock 4 and DualSense | experimental | `hid_playstation` |
| 8BitDo, GameSir, Logitech, Razer, Redragon, XInput clones | experimental | `xpad`, `hid_generic`, etc., depending on model and mode |
| Switch 2 | planned | no stable driver |

Only **validated** families are active by default. The others require
`JOYMANAGER_EXPERIMENTAL=1` in the service environment. The modules above are what
is expected from general Linux knowledge and have **not been validated on hardware**,
except for the validated ones.

External drivers (`xone`, `xpadneo`) are not installed by `install.sh` and are not
included in the packages: they are third-party code built through DKMS and should be
installed by you from your distribution's package or from the upstream project.

## Arch Linux/CachyOS

Base packages:

```text
bluez bluez-utils upower evtest joystick
```

`joycond` will normally be installed from the AUR or built from the upstream project. The following services must be active:

```text
bluetooth.service
joycond.service       (only if combined pairing is used)
joystickmanager.service
```

## Debian/Ubuntu

Usual names:

```text
bluez evtest joystick upower dbus udev
```

`joycond` may need to be built from source if the distribution does not maintain a package for it. The kernel development headers are also needed for any future DKMS driver.

## Fedora

Usual names:

```text
bluez evtest joystick upower dbus systemd-udev
```

`joycond` and additional DKMS drivers should be treated as optional components installed separately.

## Xbox in future versions

When Xbox support is implemented, the choice will depend on the connection:

- USB and Xbox 360 receiver: `xpad`/`xone`, depending on the model;
- Xbox One/Series over Bluetooth: `xpadneo` is the candidate for battery and mapping;
- `dkms` and kernel headers may be needed for external drivers.

These components must not be installed by the first version without Xbox hardware to validate them.

## Planned automatic verification

The future installer should check and report:

1. the distribution and package manager;
2. the presence of `systemd`, `udev`, `dbus` and `bluetoothctl`;
3. the state of `bluetooth.service`;
4. the presence of `/dev/uinput` when `joycond` is requested;
5. the `hid-sony` and `hid-nintendo` modules;
6. the availability of `joycond.service`;
7. optional diagnostic tools.

The installer must not install external drivers automatically without explicit confirmation.

## Installation artifacts

- `install.sh`: installs base dependencies and the systemd unit on Arch, Debian/Ubuntu or Fedora.
- `packaging/arch/PKGBUILD`: native package for Arch and derivatives.
- `packaging/debian/`: skeleton of a `.deb` package.
- `packaging/fedora/`: RPM spec.

These artifacts are the first portability layer and still need to be built on each distribution before a formal package release.
