#!/usr/bin/env bash
set -u

optional=0
charge_only=0
for arg in "$@"; do
    case "$arg" in
        --install-optional) optional=1;;
        --pro-charge-only) charge_only=1;;
        -h|--help) printf '%s\n' 'Uso: sudo ./install.sh [--install-optional] [--pro-charge-only]'; exit 0;;
        *) printf 'Unknown option: %s\n' "$arg" >&2; exit 2;;
    esac
done

[ "$(id -u)" -eq 0 ] || { printf '%s\n' 'Run with sudo.' >&2; exit 1; }

if command -v pacman >/dev/null 2>&1; then
    pacman -S --needed bluez bluez-utils upower evtest joystick
elif command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y bluez dbus udev upower evtest joystick
elif command -v dnf >/dev/null 2>&1; then
    dnf install -y bluez dbus systemd-udev upower evtest joystick
else
    printf '%s\n' 'Unrecognized distribution; see docs/dependencies.md.' >&2
    exit 1
fi

install -Dm755 joystickmanager.sh /usr/local/bin/joystickmanager.sh
install -Dm755 joystickmanager-doctor /usr/local/bin/joystickmanager-doctor
install -Dm644 controllers.tsv /usr/local/share/joystickmanager/controllers.tsv
install -Dm755 switchpro-leds.py /usr/local/libexec/joystickmanager-switchpro-leds
install -Dm644 joystickmanager.service /etc/systemd/system/joystickmanager.service
systemctl daemon-reload
if [ "$charge_only" -eq 1 ]; then
    # Optional: the Pro Controller only charges over USB (no data). See the rule header.
    install -Dm644 udev/99-joystickmanager-procontroller-charge-only.rules /etc/udev/rules.d/99-joystickmanager-procontroller-charge-only.rules
    udevadm control --reload
fi
systemctl enable bluetooth.service 2>/dev/null || true
systemctl enable joystickmanager.service

if [ "$optional" -eq 1 ]; then
    printf '%s\n' 'joycond is optional and should be installed from your distribution package manager or the AUR.'
fi
printf '%s\n' 'Dependencies and joystickmanager files installed.'
printf '%s\n' 'Run joystickmanager-doctor to check the kernel drivers. External drivers (xone, xpadneo) are not installed.'
