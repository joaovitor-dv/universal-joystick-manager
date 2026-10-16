#!/usr/bin/env bash
set -u

optional=0
for arg in "$@"; do
    case "$arg" in
        --install-optional) optional=1;;
        -h|--help) printf '%s\n' 'Uso: sudo ./install.sh [--install-optional]'; exit 0;;
        *) printf 'Opção desconhecida: %s\n' "$arg" >&2; exit 2;;
    esac
done

[ "$(id -u)" -eq 0 ] || { printf '%s\n' 'Execute com sudo.' >&2; exit 1; }

if command -v pacman >/dev/null 2>&1; then
    pacman -S --needed bluez bluez-utils upower evtest joystick
elif command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y bluez dbus udev upower evtest joystick
elif command -v dnf >/dev/null 2>&1; then
    dnf install -y bluez dbus systemd-udev upower evtest joystick
else
    printf '%s\n' 'Distribuição não reconhecida; consulte docs/dependencies.md.' >&2
    exit 1
fi

install -Dm755 joystickmanager.sh /usr/local/bin/joystickmanager.sh
install -Dm755 switchpro-leds.py /usr/local/libexec/joystickmanager-switchpro-leds
install -Dm644 joystickmanager.service /etc/systemd/system/joystickmanager.service
systemctl daemon-reload
systemctl enable bluetooth.service 2>/dev/null || true
systemctl enable joystickmanager.service

if [ "$optional" -eq 1 ]; then
    printf '%s\n' 'joycond é opcional e deve ser instalado pelo gerenciador nativo/AUR conforme a distribuição.'
fi
printf '%s\n' 'Dependências e arquivos do joystickmanager instalados.'
