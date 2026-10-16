# UJM devlog

A running log of what we build, why, and what we measured on real hardware. The [README](README.md) is the user manual; this file is the story behind it.

- **Newest first.** Every release tag has an entry; work that is not released yet goes under *Unreleased*.
- **Honest by default.** Entries say what was verified on hardware, what was only reasoned about, and what is still open.
- **Dates** are the commit dates of 2026 (UTC-3). The first commit is `2026-10-15 20:59`.
- Release pages: <https://github.com/joaovitor-dv/universal-joystick-manager/releases>

## How to add an entry

Copy this block under *Unreleased* for every change worth remembering, and move it under its version when you tag a release:

```markdown
### Short title

- **What changed:** ...
- **Why:** ...
- **Evidence:** what you measured, on which hardware, how many runs (or "not verified").
- **Open questions:** ...
```

When you cut a release: add the tag, add its entry here, update the version in the README title and the patch-notes index at the end of the README, and create the GitHub release.

---

## Unreleased

### Credits, testers and the `joycond` note

- **What changed:** the README now says that `joycond` is not only for Joy-Cons: it also manages **Pro Controllers**, which then wait for a logical pairing (L + R) before their player LEDs settle. The first line of the README now says UJM numbers controllers *consistently every time*. New [`CREDITS.md`](CREDITS.md) lists maintainers, volunteer testers, the software UJM builds on and an artwork and trademarks notice; the volunteer guide, the test-report template (*Credit name* field) and the README explain that testers are built into the credits, only with their consent.
- **Why:** the `joycond` behavior surprised us on hardware, and volunteers deserve to be credited.
- **Evidence:** the `joycond` behavior comes from our own hardware runs (LEDs steady on the player number only after L + R); it was not measured systematically.
- **Open questions:** none.

### Interface prototype: File menu, service button and Bluetooth shortcuts

- **What changed:** the prototype's **File** menu exports and imports **controller profiles** (`ujm-controller-profiles`, version 1: id, name, alias, player, connection state) and **app settings** (`ujm-app-settings`, version 1: the theme) as JSON files, and has **Exit UJM**. A toolbar adds a **Start/Stop service** button with a state pill, and Bluetooth shortcuts: **Pair new controller…** (scan, pair, trust, connect, showing the `bluetoothctl` steps), **Connect** and **Disconnect** for the selected controller. The same actions are in the Controller menu.
- **Why:** the service must be controllable from the interface, and pairing is the first thing a new user needs.
- **Design decisions:** the interface is read-only while the service is stopped, as planned for the real application: a banner explains it and Pair/Connect/Disconnect are disabled (with a tooltip saying why). Stopping the service asks for confirmation. Exit only closes the interface; the service keeps running. Importing a profile applies only the *alias* (player slots follow connection order); import validates the format, caps the file at 256 KB and 100 entries, strips control characters and cuts aliases at 40 characters. Importing app settings goes through the same dark-only check as the theme dialog, so a JSON file carrying a light background is refused, with a joke.
- **Evidence:** a scripted headless-Chromium run of 52 checks passed with 0 JavaScript errors (menus, real exports captured from the download, imports with good and bad files, light-theme import refusal, service stop/start with the confirmation, disabled actions, connect/disconnect, the pairing dialog with masked addresses, exit and reopen), and the earlier 28 checks still pass. Testing found one real bug that is fixed: an imported alias with no spaces overflowed the controller card.
- **Open questions:** **nothing here talks to the system yet.** The service button, pairing and connect are simulated. In the real application the service cannot be controlled through the daemon's own API (it is the thing being stopped), so it has to use systemd's D-Bus interface with polkit authorization; the interface must never call `sudo`.

### Interface prototype: Credits & Info and a dark-only theme configurator

- **What changed:** the prototype got working **View** and **Help** menus, a **Help → Credits & Info** page that mirrors `CREDITS.md`, and **View → Theme…**: three color pickers (background, accent, text) plus six dark presets, saved in the browser. The two view tabs were removed earlier the same day: *Combined Joy-Cons* is just another entry in the controller list. The theme is **dark only**: a light background is refused, with jokes ("Do you hate your sight?", "What's wrong with you? Daywalker." and a few more; the fifth attempt tells you to touch grass).
- **Why:** credits and theming were requested for the app; refusing light mode is a design choice, not a limitation.
- **How it works:** the page's stylesheet is not edited. The configurator keeps a recolored copy of it in a later `<style>` and only remaps the green theme family (surfaces, highlights, text); semantic colors (A/B/X/Y, LEDs, warnings) are kept, and the default theme is the page's own palette.
- **Evidence:** a scripted headless-Chromium run of 28 checks passed with 0 JavaScript errors: menus, the credits page, the first two jokes verbatim, refusal of too-bright backgrounds, too-dark text and accents and of garbage input, presets, persistence after reload, reset, and that the controller cards still work. **The prototype is still not connected to the service**, and it lives outside this repository for now.
- **Open questions:** whether the theme should become a setting of the real application (it would be stored with the other settings); the screenshots still contain Steam-derived artwork and platform logos.

### The technical rename is off the table

- **What changed:** nothing in the code. The README roadmap no longer plans renaming `joystickmanager.service`, `JOYMANAGER_*` and `/run/joystickmanager`.
- **Why:** renaming them on their own would break existing installs for no gain. It would only make sense together with a **console-only edition** installed as plain `ujm` (command and service id). That edition is an idea, not a commitment.

### The GitHub page becomes a manual

- **What changed:** the README is now a user manual (install, use, configuration, troubleshooting, roadmap, patch notes). This devlog, `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, a bug-report form, a PR template and a CI workflow were added. Screenshots of the interface prototype live in `docs/images/`.
- **Why:** the old README mixed scope, rationale and instructions in one long list. New visitors could not tell what works today.
- **Evidence:** screenshots are of the **static UI prototype with simulated data**; the interface is not connected to the daemon yet. The first CI run on GitHub passed all steps of the `Tests` job (unit tests, syntax checks, udev rule validation, profile table check) on the Ubuntu runner, which uses `mawk`. The informational ShellCheck job reports warnings, mostly false positives (variables defined in a sourced file, and an intentional glob in a `case`); cleaning them up is a follow-up. All 22 tags were published as GitHub pre-releases, the repository description and topics were set, and private vulnerability reporting was enabled.
- **Open questions:** the social preview image must be uploaded by hand (`docs/images/social-preview.png`); the screenshots contain controller artwork derived from Steam client assets and platform logos, whose publication rights are the maintainer's call.

---

## v0.7.1 - English docs and the UJM name

*2026-10-16 · docs only · `fa691a5`*

- **What changed:** code comments, messages, tests, README and docs were translated to en-US. The product name is now **UJM - Universal Joystick Manager** in the README and package descriptions. Technical identifiers are unchanged on purpose.
- **Why:** make the project accessible to more people, and give it a short name.
- **Evidence:** the test suite has the same 38 passing checks before and after the translation.
- **Open questions:** none for the brand. Decision, 2026-10-16: the technical identifiers (`joystickmanager.service`, `JOYMANAGER_*`, `/run/joystickmanager`) are **not** going to be renamed on their own; it would only make sense with a console-only edition installed as plain `ujm`.

## v0.7.0 - Charge the Pro Controller without losing Bluetooth (opt-in)

*2026-10-16 · minor · `da867c4`*

- **What changed:** an optional udev rule, `udev/99-joystickmanager-procontroller-charge-only.rules`, deauthorizes the Pro Controller's USB device when it is plugged in. `install.sh --pro-charge-only` installs it.
- **Why:** plugging a Pro Controller in with a *data* cable makes its firmware leave Bluetooth, so you could not charge while playing.
- **Evidence:** by hand, `echo 0 | sudo tee /sys/bus/usb/devices/<port>/authorized` kept the controller on Bluetooth with the battery reporting `Charging` (several minutes, in separate runs). **The udev rule itself has not been tested on hardware.**
- **Open questions:** the kernel enumerates the device before udev runs, so the controller may drop Bluetooth for a moment on plug-in; it is not known whether it returns without pressing HOME. With the rule installed the controller does not work wired. A charge-only cable remains the solution without caveats.

## v0.6.1 - Gentler LED updates: no more Pro Controller drops

*2026-10-16 · patch · `f7a58de`*

- **What changed:** LEDs are re-applied every 10 s (`JOYMANAGER_LED_REFRESH`, `0` keeps the old behavior) instead of every 2 s. Real changes, such as starting to charge, are still written immediately. The periodic device scan no longer re-applies LEDs for a controller it already knows.
- **Why:** with a Pro Controller connected, the kernel logged hundreds of `joycon_enforce_subcmd_rate: exceeded max attempts` per hour, followed by `timeout waiting for input report` and a Bluetooth drop. Every LED write is an HID subcommand, and the loop was sending many of them every cycle.
- **Evidence:** on one Pro Controller, one run per setting: old script with the service on dropped after 31 s and after 2.5 min (49-64 errors in a 3-4 minute window); with the service stopped it stayed up for 4 minutes with 0 errors; the new script with the service on stayed up for 5+ minutes, charging, with 0 errors, and the LEDs looked correct. **A short sample; the Joy-Con R was not connected.**
- **Open questions:** a longer soak test with a Pro Controller and a Joy-Con R together; whether the idle-disconnect worker, which now also starts for USB controllers, behaves.

## v0.6.0 - `joystickmanager-doctor` and wider packaging

*2026-10-16 · minor · `5eb449e`*

- **What changed:** `joystickmanager-doctor` is a read-only command that shows, per controller family, whether each kernel module is loaded, available or absent, and which connected controllers matched a profile. `install.sh` and the Arch, Debian and Fedora packaging install it with `controllers.tsv`.
- **Why:** "my controller is not detected" needs a one-command answer.
- **Evidence:** run against the real system: the Pro Controller was listed with its driver and marked active. Covered by a test using a fake sysfs.
- **Open questions:** the packages have not been built on each distribution.

## v0.5.0 - Controller profiles

*2026-10-16 · minor · `8f54858`*

- **What changed:** `controllers.tsv` describes each controller family (match rule, state, expected kernel module, notes). Only `validated` profiles are active by default; `experimental` and `planned` need `JOYMANAGER_EXPERIMENTAL=1`. Controllers without HID identity (for example `xpad` devices) get a slot but no LEDs. Without the table the service falls back to the old fixed list.
- **Why:** the supported list was a hard-coded `case`; adding Xbox, DualShock 4, DualSense, 8BitDo, GameSir, Logitech, Razer or Redragon would have meant editing code and silently claiming support.
- **Evidence:** unit tests (profile matching, state gating, IMU/touchpad nodes ignored, fallback). **The experimental entries are expected values from general Linux knowledge, not validated on hardware.**
- **Open questions:** volunteers with those controllers (see `docs/volunteer-testing.md`).

## v0.4.2 - The Bluetooth adapter stays connectable

*2026-10-16 · patch · `e0a4a55`*

- **What changed:** the service re-asserts `btmgmt connectable on` every ~20 s and restarts with `bluetooth.service`.
- **Why:** pressing HOME on a Pro Controller did not reconnect it. A packet capture (`btmon`) showed the adapter received nothing from the Pro, while a Joy-Con R reconnected fine; `btmgmt info` showed the adapter without the `connectable` setting. With `connectable on`, the Pro Controller reconnected with a single HOME press.
- **Evidence:** reproduced and fixed on hardware. A first version that set the mode only once at service start was **not enough**: after `systemctl restart bluetooth` the mode was gone a minute later, which is why it is now re-asserted periodically. After the change, `connectable` was back within 25 s of a Bluetooth restart (checked with `btmgmt info`).
- **Open questions:** why `bluetoothd` clears the mode is not confirmed.

## v0.4.1 - Pro Controller recognized over USB

*2026-10-16 · patch · `faa8fb1`*

- **What changed:** the Pro Controller is recognized when it appears over USB.
- **Why:** over USB the kernel names the input "Nintendo Co., Ltd. Pro Controller" instead of "Pro Controller", so the service ignored it: no slot, no LEDs, missing from `slots.tsv`.
- **Evidence:** three user scenarios on hardware (Bluetooth first then cable; two on Bluetooth with one plugged in; USB first then a second on Bluetooth) behave correctly after the fix.
- **Open questions:** none for this change.

## v0.4.0 - Players numbered by connection order, and the first tests

*2026-10-16 · minor by judgment (a `fix`) · `b29738d`*

- **What changed:** a controller that reconnects before the periodic cleanup no longer inherits its old slot because it has the same MAC; a controller that is still present (for example Bluetooth to USB) keeps its slot. The script can now be sourced, and `tests/test_slots.sh` runs against a fake sysfs.
- **Why:** numbering by connection order was always the design, but the code could hand an old slot back to a reconnecting controller.
- **Evidence:** four test functions at this point (now 17); the suite has 38 checks.
- **Open questions:** none.

## v0.3.5 - Right Joy-Con LED order fixed

*2026-10-15 · patch · `9548d6f`*

- **What changed:** the player LED pattern for the right Joy-Con is reversed, so the pattern reads in the same direction as on the left one.
- **Evidence:** not recorded in the commit.

## v0.3.4 - Idle power-off raised to 30 minutes

*2026-10-15 · patch (a default change, committed as `test:`) · `38e7ccc`*

- **What changed:** the idle power-off, a fixed 300 s, became configurable through `JOYMANAGER_IDLE_TIMEOUT` with a default of 1800 s (30 minutes), set in the service, the script and the README.
- **Why:** a longer window makes long hardware tests practical. It is temporary.
- **Open questions:** restore 300 s once the planned hardware tests are done.

## v0.3.3 - Pro Controller LEDs addressed by Bluetooth address

*2026-10-15 · patch · `0ec25a5`*

- **What changed:** the service passes the controller's Bluetooth address (`--id`) to the helper, which finds the matching hidraw device, so the LED command reaches the right controller when several are connected.

## v0.3.2 - Pro Controller LEDs use the right HID interface

*2026-10-15 · patch · `238113e`*

- **What changed:** `switchpro-leds.py` prefers the hidraw interface whose device name is "Pro Controller" and only falls back to the first one found.

## v0.3.1 - Pro Controller LEDs: output report sequence

*2026-10-15 · patch · `a4c9423`*

- **What changed:** the helper now fills the output-report sequence number (the low nibble of the report counter) instead of always sending a fixed value.
- **Why:** the helper's own comment says the controller uses that nibble as an output-report sequence.

## v0.3.0 - Pro Controller player LEDs via HID

*2026-10-15 · minor · `c4b6681`*

- **What changed:** a small helper, `switchpro-leds.py`, sets the Pro Controller's player LEDs by writing HID output reports.
- **Why:** not recorded in the commit message; the service already wrote the LEDs through the kernel interface and this adds a direct HID path for the Pro Controller.
- **Evidence:** three follow-up fixes (v0.3.1-v0.3.3) were needed before it behaved on hardware.
- **Also in this range:** `dd6704a` documented that a data cable can move a Pro Controller from Bluetooth to USB.

## v0.2.1 - Faster LED re-apply

*2026-10-15 · patch · `a6202cd`*

- **What changed:** player LEDs are re-applied more often.
- **Why:** the controller firmware could put its own pairing pattern back after an input report. (v0.6.1 later reversed the trade-off: too frequent writes overload the controller.)

## v0.2.0 - HOME LED as a connection indicator

*2026-10-15 · minor · `99518d6`*

- **What changed:** the service keeps the HOME LED on while a controller is connected.
- **Open questions:** the current `hid-nintendo` exposes the blue HOME LED as `player-5`, and its brightness can change without any physical change, so it is not a trustworthy indicator on every controller.

## v0.1.3 - Battery status on the player LED

*2026-10-15 · patch · `d559302`*

- **What changed:** battery state moved from the blue HOME LED to the player LED: steady when normal, blinking when charging or low.
- **Why:** the commit calls the player LEDs the reliable ones; the HOME LED could not be trusted (see v0.2.0).

## v0.1.2 - Player and blue battery LEDs restored

*2026-10-15 · patch · `c3f81a6`*

- **What changed:** the player LEDs are re-applied before the battery state on every cycle, and a controller is also looked up by its hardware prefix. This restores the LEDs after the controller firmware refreshes them.

## v0.1.1 - Connection LED stays on outside battery alerts

*2026-10-15 · patch · `e46bd0a`*

- **What changed:** when the battery is normal, the blue LED stays on as a connection confirmation; only charging and low-battery alerts change it.
- **Also in this range:** `66131c6` added the experimental 8BitDo and GameSir scope, the volunteer testing program and an issue template.

## v0.1.0 - `joycond` integration, installers and packages

*2026-10-15 · minor · `a1997a9`*

- **What changed:** two physical Joy-Cons combined by `joycond` into one virtual device take a single player slot, and their LEDs stay in sync. `install.sh` and the Arch, Debian and Fedora packaging skeletons were added. The packages declare version `0.1.0`.
- **Evidence:** the first version that can be installed. Packages have not been built on every distribution.
- **Also in this range:** `6e2516d` documented the cross-distribution dependencies.

## v0.0.2 - Eight players

*2026-10-15 · pre-0.1.0 · `93967b2`*

- **What changed:** the player limit went from four to eight. The four player LEDs encode players 5-8 with binary masks (for example player 5 lights LEDs 1 and 4).
- **Why:** a four-LED row can still tell eight players apart.

## v0.0.1 - Bootstrap

*2026-10-15 · pre-0.1.0 · `2db2fc5`*

- **What changed:** the first unified service: `joystickmanager.sh` and its systemd unit, with global player numbering by connection order and a first README and architecture note, under the MIT license.
- **Why:** several per-model scripts existed; the goal is one service that numbers every controller the same way.
