# Packaging and distribution formats

UJM has two very different parts, and they need different formats:

- **The service** (`joystickmanager.sh` and its systemd unit) runs as root, writes under `/sys`, uses udev and `bluetoothctl`. It must be installed **into the system**, so it ships as native packages.
- **The interface** (`ui/`) is a user application. Today it is a static prototype; once it becomes a real app talking to the service, it is the part that fits sandboxed formats such as Flatpak and AppImage.

## Formats

| Format | Part | How it is built | Status |
|---|---|---|---|
| Source tarball + `install.sh` | service | `git archive`, attached to each release | works on any systemd distribution |
| Arch Linux `.pkg.tar.zst` | service | `packaging/arch/PKGBUILD` (builds from the checkout: run `makepkg` in that folder) | builds; checked with `namcap` |
| **AUR** | service | `packaging/aur/PKGBUILD` + `.SRCINFO`, from the release tarball; `packaging/aur/update.sh <version>` points it at a new release | recipe builds from the v0.8.0 tarball; **not published** (needs the maintainer's AUR account). Publish from the first release after v0.8.0, which carries the LED-helper path fix |
| Debian/Ubuntu `.deb` | service | `packaging/debian/` (copied to `debian/` for `dpkg-buildpackage`) | built and checked in CI on every push (files in place, `ExecStart` in `/usr/bin`); not yet installed on a real Debian/Ubuntu system |
| Fedora `.rpm` | service | `packaging/fedora/universal-joystick-manager.spec` | built and checked in CI on every push; not yet installed on a real Fedora system |
| Flatpak | interface | not yet | planned for the GUI app; a Flatpak cannot install a system service or udev rules, so it will talk to the service over D-Bus |
| AppImage | interface | not yet | same as Flatpak: GUI only |

Every published release gets its `.deb`, `.rpm`, Arch package, source tarball and `SHA256SUMS` attached automatically by `.github/workflows/release.yml`. It can also be run by hand for an existing tag (**Actions → Release packages → Run workflow**).

## Where things are installed

| File | `install.sh` | Packages |
|---|---|---|
| Service script | `/usr/local/bin/joystickmanager.sh` | `/usr/bin/joystickmanager.sh` |
| Doctor | `/usr/local/bin/joystickmanager-doctor` | `/usr/bin/joystickmanager-doctor` |
| Pro Controller LED helper | `/usr/local/libexec/joystickmanager-switchpro-leds` | Arch/Debian `/usr/lib/joystickmanager/switchpro-leds`, Fedora `/usr/libexec/joystickmanager-switchpro-leds` |
| Profile table | `/usr/local/share/joystickmanager/controllers.tsv` | `/usr/share/joystickmanager/controllers.tsv` |
| systemd unit | `/etc/systemd/system/joystickmanager.service` | `/usr/lib/systemd/system/joystickmanager.service` (`ExecStart` rewritten to `/usr/bin`) |
| Optional udev rule | installed only with `--pro-charge-only` | shipped in `/usr/share/joystickmanager/udev/`, **not active**; copy it to `/etc/udev/rules.d/` to enable |

The service finds the LED helper next to wherever it is installed (`JOYMANAGER_SWITCHPRO_HELPER` overrides it), so both layouts work. Packages do not enable or start the service by themselves: run `sudo systemctl enable --now joystickmanager` after installing.

## Later

- Repositories so updates arrive with the system: Fedora Copr, openSUSE Build Service (covers several distributions), an Ubuntu PPA.
- Flathub and an AppImage for the interface, once it is a real application.
- Signing the release files.
