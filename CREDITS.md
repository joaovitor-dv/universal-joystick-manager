# Credits

UJM exists because people built it, tested it and shared their hardware. This file is the source of truth for the credits; the app's **Credits & Info** page (Help menu) shows the same list.

## Maintainers and collaborators

- **João** ([@joaovitor-dv](https://github.com/joaovitor-dv)): project owner, direction, and hardware testing.
- **Claude** (Anthropic): service, tests, documentation and release work.
- **Codex** (OpenAI): interface prototype.

## Volunteer testers

Testers who send a reproducible report for a controller model, connection or mode are **built into the credits**, here and in the app. You are listed under the name or handle you choose, and only if you say so: add it to the *Credit name* field of the [test report](https://github.com/joaovitor-dv/universal-joystick-manager/issues/new?template=controller-testing.md). How to test: [volunteer testing guide](docs/volunteer-testing.md).

Format of an entry: `name or handle - controller model, connection (UJM version)`.

- *No volunteer reports yet. Be the first.*

## Software UJM builds on

- The Linux kernel input and HID drivers (`hid_nintendo`, `hid_sony`, `hid_playstation`, `xpad`, ...) and the people who maintain them.
- [`joycond`](https://github.com/DanielOgorchock/joycond) by Daniel Ogorchock, which combines Joy-Cons and also manages Pro Controllers.
- [BlueZ](https://www.bluez.org/), systemd and udev.

## Artwork and trademarks

- The controller diagrams in the **interface prototype** are derived from assets found in the Steam client (© Valve) and use platform logos. They are shown for layout purposes only.
- Nintendo Switch, Joy-Con, PlayStation, DualShock, DualSense, Xbox, Steam and the other product names are trademarks of their owners. UJM is an independent project and is not affiliated with or endorsed by them.
