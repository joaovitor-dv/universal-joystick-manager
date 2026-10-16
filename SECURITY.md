# Security policy

## Supported versions

UJM is pre-release (0.x). Only the latest release on `main` receives fixes.

## What to be aware of

UJM runs as a **root** systemd service. It writes LED brightness under `/sys/class/leds`, runs `bluetoothctl` and `btmgmt` (it keeps the Bluetooth adapter connectable, so the computer answers connection requests from bonded Bluetooth devices in range), and reads `/sys` and `/dev/input`. The installer needs root. The optional udev rule turns off USB data for one device (Pro Controller, `057e:2009`). UJM opens no network ports.

## Reporting a vulnerability

Please **do not open a public issue** for a security problem. Use GitHub's private reporting: on the repository page choose **Security → Report a vulnerability**. Include the version, how to reproduce it and the impact you expect.

You can expect an acknowledgement within a few days. This is a small, volunteer-run project, so there is no formal response-time guarantee.

When you report, remove personal data (MAC addresses, serial numbers, user names) from logs.
