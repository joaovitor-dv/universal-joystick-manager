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

### Third-party Joy-Cons are recorded as not supported

- **What changed:** the README no longer lists third-party Joy-Cons as validated; a Troubleshooting entry explains the symptoms and what to do.
- **Why:** a gray third-party pair was tried on real hardware in four situations (with Steam running, with it closed, with the radio full and with only the white pair connected). It failed in each: the driver could not initialise it (`failed reading SPI flash`, `Failed to enable the IMU`, `probe with driver nintendo failed`), it dropped gyroscope reports continuously (about 200 in 14 minutes against 33 for a Pro Controller), and twice it left `bluetoothd` and the kernel's LED queue in uninterruptible sleep until it was switched off, which stops every Bluetooth controller. It shows only LED 1 and never lights its HOME LED.
- **What we found out about it:** everything it reports is an original's (name, class, `057E:2006`, a Nintendo-style serial `XBW…`, the gray colour values `#828282`/`#0F0F0F` read from its memory); its Bluetooth LE advertisement (`BLE_Joy_L`) carries the manufacturer id `0x6C42`, which the Bluetooth SIG has not assigned, at -80 dBm. Nothing names the maker, so there is no update tool to look for, and Nintendo's firmware is not what it runs. The same SPI reads worked in 5 s when only a user-space script talked to it, so the failures come from the driver's short timeouts, not from an unreadable controller.
- **Evidence:** logs and counts from the hardware session of 2026-10-17; no code changed. UJM cannot tell a clone from an original (identical ids), so there is no detection.
- **Open questions:** whether another clone brand behaves the same; whether a closer adapter placement would make this pair usable.

### Only the Joy-Cons that `joycond` merged lose their slot

- **What changed:** when a "Nintendo Switch Combined Joy-Cons" device appears, only the physical Joy-Cons that `joycond` merged into it are dropped from the slot table; a Joy-Con that is free keeps its own slot. The service tells them apart by the permission of the input node (mode 0600, root only, while `joycond` holds it). Before, **every** physical Joy-Con was dropped when a combined device registered and came back at the next scan, so a merged pair was counted twice (the combined device plus its two Joy-Cons) and, with a second pair, the free Joy-Cons were wrongly folded in.
- **Why:** with a white pair merged next to a gray pair left free, the table had seven entries (two Pro Controllers, the combined device and four Joy-Cons) instead of five. A probe that counted button events per joystick node showed the gray Joy-Cons answering on their own nodes (74 and 32 events) and the white ones only on the combined device (44 and 26); the nodes of the white pair were `crw-------`, the gray ones `crw-rw-rw-`.
- **Evidence:** 3 new unit tests (a merged pair collapses and stays collapsed across scans while a free pair keeps its slots; a dissolved pair gets its slots back; a locked Joy-Con with no combined device is a normal controller); the first two fail on the old behavior. **Not yet run on the real service.**
- **Open questions:** the permission is a side effect of `joycond`'s udev rules, not a documented interface; a different `joycond` version may not do it. When a pair dissolves, the Joy-Cons come back at the next scan (up to two seconds).
- **Also found:** a button press on a controller moved the mouse and opened the start menu: Steam Input, which was running, applies its Desktop layout to every controller it sees (README, Troubleshooting). UJM does not write input events.

### The right Joy-Con's battery LED follows its mirrored pattern

- **What changed:** the battery indication (steady, blinking while charging or when low) now uses the LED that is on for the slot, which for the right Joy-Con is the mirrored one (slot 4 lights LED 1), instead of the LED with the slot's number.
- **Why:** on a right Joy-Con in slot 4 the service lit LED 1 as the pattern and then lit LED 4 as the battery LED, so the maintainer saw LED 4 flash on and off at every refresh. Found on hardware with a third-party right Joy-Con.
- **Evidence:** a unit test with the right Joy-Con in slot 4 (the old code leaves LED 4 lit); removing the change makes it fail. Not yet re-checked on the controller.
- **Also recorded:** third-party Joy-Cons keep an LED pattern for only a few seconds and their right Joy-Con never lights its HOME LED ([docs/state.md](docs/state.md)); the left one drops many IMU reports (about 1.5 a second) without failing.

### Nintendo LEDs wait for the controller; the HOME LED is lit once and not kept alive

- **What changed:** (1) for Nintendo controllers (HID vendor 057E) the first LED write happens `JOYMANAGER_LED_SETTLE` seconds after connecting (6; `0` for the old behavior) instead of at once. (2) The HOME LED is no longer re-sent with every refresh: it is lit once per connection (once per pair for a `joycond` pair) and left; `SetHomeLed` still lights it on request.
- **Why:** on a Pro Controller the HOME LED lights on command and **goes dark by itself after about 15 s** (watched by the maintainer, twice) while sysfs keeps saying 15: that is the old "brightness changes without physical effect" note, and the reason the 10 s refresh used to keep it alive. Keeping it lit means one more command per controller every 10 s, and too many commands are what drop the link (two Pro Controllers dropped with `exceeded max attempts` bursts; with the refresh off both stayed connected for 6.5 minutes), so the feature is abandoned. Separately, the second Pro Controller showed the kernel's own pattern (LEDs 1 and 2) instead of ours (LED 2): the driver applies its pattern some time after the connection, later than a write made at once, and later than the 6 s guess too (the pattern was still the kernel's 23 s after connecting).
- **Evidence:** 3 new unit tests for the settle time and 1 for the HOME LED (lit once, not re-sent by the refresh, still available on request); removing any part makes them fail. On hardware: the 15 s observation, the 6.5 minute run without the refresh, and that an explicit write to Pro 2 works (`0100`, also after going back to automatic). **The settle time does not fix Pro 2's numbering**: the open question is whether the periodic player-LED refresh (10 s) does.
- **Then:** the 10 s refresh itself dropped the second Pro Controller (it caught the driver's pattern, but rewrote all four LEDs plus the helper every time: about six commands per controller every 10 s, with `dropped IMU reports` and `exceeded max attempts` growing minute by minute until it fell, at about 3 minutes, twice; the first Pro Controller never failed). `set_player_leds` now reads the LEDs from sysfs, which shows the pattern the driver last applied, and sends nothing when they already match; the forced battery-LED write does the same; an explicit `SetPlayerLeds` still always writes. In steady state a refresh costs no command. Tests: 3 new (no command in four refreshes with the LEDs right; a pattern the driver changed is corrected, with a command; an explicit request always writes), the first two fail on the old behavior. **Not yet run on a controller.**
- **Open questions:** whether reading before writing keeps two or more Pro Controllers connected with the refresh on; the right time to wait, if any.

### Development tools: one check script, a hardware checklist

- **What changed:** `tools/check.sh` runs what CI runs (unit tests, syntax, the udev rule, the profile table, the bridge XML and tests, ShellCheck) and, on request, the interface tests, the QML tests and the package builds (`.deb` and `.rpm` in Docker, Arch with `makepkg`). CI's Tests job now calls the same script. `tools/collect-report.sh` writes one diagnostic file with Bluetooth addresses masked; `tools/measure-service.sh` measures the running service's CPU from its cgroup. [docs/hardware-checklist.md](docs/hardware-checklist.md) turns every check that needs a real controller into one ordered session with expected results.
- **Why:** two CI failures in one day (a missing build dependency and a tool used before it was installed) were both cheap to catch locally, and the hardware checks were scattered across notes, one of them ("original tests 3, 4 and 6") never written down.
- **Evidence:** `tools/check.sh` passes here and fails (exit status 1, with the parser error) when a bridge XML file is broken; `--gui` and `--packages` pass; the address masking has a self-test that `check.sh` runs. On this machine ShellCheck is not installed, and the script says so instead of passing.
- **Open questions:** nothing here has been used on a second machine; the checklist itself has not been run.

### Native QML interface: the Overview screen

- **What changed:** `gui/ujm_gui.py` and `gui/qml/` are the first screen of the native interface: one card per connected controller (player, name or alias, vendor, transport, battery and charging state, player LEDs), in the dark palette of the HTML prototype. It reads the D-Bus bridge and follows its `ControllersChanged` signal; without the bridge it reads `/run/joystickmanager/state.json` directly, read-only, and says which source it is using. `--state-file gui/examples/state.example.json` runs it with no service and no hardware. Read-only: no buttons yet.
- **Why:** the measurement decided it: about 88 MiB and one process, against 332 MiB and five for the WebEngine shell ([docs/gui-measurements.md](docs/gui-measurements.md)). Nothing polls: updates come from the bus signal or inotify, so it idles at about 0% CPU.
- **Evidence:** 9 headless tests (offscreen, software rendering) on the example data, live replacement of the file by rename, a battery change updating one row without resetting the list, a broken file, no service at all, the bridge on a private session bus following its signal, and the fallback to the file; the LED test fails when the LED lookup is broken. A rendered screenshot was checked by eye. Measured on the real Wayland session (4 samples).
- **Also:** the bridge got `GetSnapshotJson`, because QtDBus from Python cannot unpack `a{sv}` replies.
- **Open questions:** the Basic Qt Quick Controls style is used because the default one stalled at start-up here; no controller photos or icons yet; it was not run against a bridge on the system bus (the bridge is not installed on this machine); PySide6 is not installed in CI, so these tests do not run there yet.

### D-Bus bridge for the interface (`org.ujm.Manager1`)

- **What changed:** new `bridge/ujm-bridge`, a small Python program (PyGObject/GIO) that republishes `state.json` on the system bus, stores controller aliases, and drives BlueZ for scan, pair, connect and disconnect, asking polkit before every action. Bus-activated, and it exits 30 s after its last client leaves. Details in [docs/bridge.md](docs/bridge.md). `install.sh --with-bridge` and the three packages ship it (its dependencies are optional).
- **Why:** the interface must not run `bluetoothctl`, `sudo` or read `/dev/input`, and the shell service cannot speak D-Bus. GIO was chosen over `dbus-fast`/`jeepney`: one dependency that every Linux desktop already has, an idle main loop that costs nothing, and inotify built in.
- **Evidence:** 19 tests on a private session bus with a fake BlueZ and a fake polkit (the real `CheckAuthorization` call is exercised); measured 0.00% CPU and 19.6 MiB while running, nothing when stopped. The `.deb`, `.rpm` and Arch packages were built with the bridge and inspected.
- **Open questions:** `SetIdleTimeout`, `SetPlayerLeds` and `SetHomeLed` return `NotSupported` until the shell service has a command channel. Not tested: a real BlueZ, a real polkit, the system bus policy on an installed system.

### Interface measurements: Chromium against QML

- **What changed:** `gui/` has a PySide6 + QtWebEngine shell around `ui/index.html` (stop-gap), a QML baseline and the measuring scripts. Report: [docs/gui-measurements.md](docs/gui-measurements.md).
- **Why:** to decide whether the interface may depend on Chromium. Measured on one machine: plain QML 108 MiB (PSS) and one process; the WebEngine shell 332 MiB and five processes, 340 ms slower to start, plus a 283 MiB dependency. CPU is about 0% in both. The decision is to build the native QML interface.
- **Open questions:** single samples; the final interface with eight controllers and the monitoring views will use more than the baseline.

### Debian package no longer enables or starts the service

- **What changed:** `debian/rules` runs `dh_installsystemd --no-enable --no-start`.
- **Why:** reading the maintainer scripts of the built package showed that `dh_installsystemd` enabled and started `joystickmanager.service` on install, against what the docs and the Arch and Fedora packages do.
- **Evidence:** the `postinst` of the rebuilt package has the "dont-enable" snippet and no start/restart. Not tested by installing it on Debian.

### The service no longer burns ~10% of a core while idle

- **What changed:** the periodic scan (every 2 s) skips input nodes it has already found not to be supported controllers. A node is looked at again when it is re-created (newer than the previous scan) and every 30 scans, so a controller is never missed. `read_file` also uses the shell's `read` instead of starting `cat`.
- **Why:** measured with a transient systemd scope, an idle service with **no controllers connected** used about **11% of one CPU core**, both the installed copy and this repository. Every cycle it re-read all 29 input nodes of the desktop (keyboards, mice, touchpad, lid switch...) and matched each one against the profile table, around 1000 short-lived processes per cycle. On this machine the installed service had used 1 h 47 min of CPU in 18 h.
- **Evidence:** after the change the same measurement gives **0.4%** (68 ms of CPU in 17 s). Five new unit checks cover it: nodes are not matched again, a controller plugged after other nodes is still found, a node re-created as a controller is found, a node whose name changes in place is found by the periodic rescan, and a cycle over 30 ordinary nodes never reads the profile table. Two of them fail on the old scan.
- **Open questions:** the cost with controllers connected has not been measured on hardware; `write_state` and the battery loop still start a few processes per connected controller each cycle.

### The right Joy-Con HOME LED in a combined pair

- **What changed:** when two Joy-Cons are combined by `joycond`, the service now also turns on the HOME LED of the right Joy-Con, as it already did for a Joy-Con R on its own and for the Pro Controller.
- **Why:** reading the kernel driver (`drivers/hid/hid-nintendo.c`, current mainline): the HOME LED is exposed as `<hid>:blue:player-5` only for the right Joy-Con and the Pro Controller, with brightness 0-15, and it is set to **0 (off) when the controller connects**; every write is HID subcommand `0x38`. In a combined pair the physical Joy-Cons leave the slot table and the pair sync only wrote the player LEDs, so the right Joy-Con HOME LED stayed off.
- **Evidence:** a unit check with a fake LED tree (fails on the old code, passes now). **Not seen on hardware yet.** One more hypothesis to check on hardware: an old comment says the HOME LED brightness "can change without any physical change"; since every write sends a subcommand, that was probably subcommands failing under the LED write storm fixed in v0.6.1.

### The service publishes its state (`state.json`)

- **What changed:** the service writes `/run/joystickmanager/state.json` (format `ujm-state`, version 1): each connected controller with player, name, profile family, transport, HID device, player LED mask and battery, plus the service settings. It is rewritten atomically and only when something changed. Documented in [docs/state.md](docs/state.md).
- **Why:** it is the first, read-only step of the local API the interface needs to stop showing simulated data, and it does not depend on choosing D-Bus or another transport yet.
- **Evidence:** 13 unit checks (Bluetooth, USB and the joycond pair, battery, LED masks, escaping of quotes and backslashes, no rewrite when nothing changed, rewrite on disconnection), the JSON parsed by Python. Run against this machine's real devices in read-only mode it produced a valid file; no controller was connected at the time, so it has **not been seen with real controllers yet**.
- **Also:** the tests now always use the repository's `controllers.tsv`; before, they silently read a table installed on the machine (here an older one), which CI could not notice.

### The idle power-off could disconnect every Bluetooth controller

- **What changed:** the idle worker now disconnects only after a **full** idle timeout without input, and only Bluetooth devices get one. `evtest`, which it relies on, is a required dependency of every package.
- **Why:** it treated any end of `evtest` without input as idleness. With `evtest` missing (it was only optional in the packages) or failing, it ended at once, so the service disconnected each Bluetooth controller right after it connected, every 0.25 s. Workers also started for USB controllers and the joycond virtual pair, where there is nothing to disconnect.
- **Evidence:** unit tests with stub `evtest` and `bluetoothctl`; on the old code the failing-evtest case produced 6 disconnects in 1.5 s, now none. It did not happen on the maintainer's machine because `install.sh` installs `evtest`.

### Packages that actually work, and more formats

- **What changed:** the Arch `PKGBUILD` did not build (it used `../../` sources) and all three packages installed the script to `/usr/bin` while the unit pointed at `/usr/local/bin`, so the service would not have started; the Pro Controller LED helper was not packaged at all; the Debian files were invalid. All fixed (see [docs/packaging.md](docs/packaging.md)). New: an AUR recipe built from the release tarball with an update script, and a **Release packages** workflow that attaches `.deb`, `.rpm`, the Arch package, the source tarball and `SHA256SUMS` to each published release.
- **Why:** to offer as many Linux install formats as make sense. Flatpak and AppImage are kept for the graphical interface: they cannot install a root service, udev rules or a systemd unit.
- **Evidence:** the Arch package builds locally, `namcap` reports no errors in the AUR recipe, the package holds the 8 expected files, the unit points at `/usr/bin` and the installed script finds the LED helper. The AUR recipe builds from the real v0.8.0 tarball (checksum verified). The `.deb` and `.rpm` cannot be built on the maintainers' machine; a new CI job builds and checks them on every push. Its first run failed only because the runner lacked `build-essential`, and it passes since that was added (the same steps were also checked in a Debian container). Neither package has been installed on a real Debian/Ubuntu or Fedora system yet, and the release workflow has not run yet.
- **Open questions:** publish to the AUR (needs the maintainer's account), starting with the release after v0.8.0, which has the LED-helper path fix; Copr, OBS or a PPA later.

### Can the LEDs be written only once? (`JOYMANAGER_LED_REFRESH=off`)

- **What changed:** a new value, `off`, applies the player LEDs once per connected controller (each connection gets a new HID device, so a reconnection is applied again) and then writes only real changes: battery state and the charging blink. An invalid value now falls back to `10` instead of failing every comparison silently; in fact the old code already behaved like `off` for any non-number, by accident.
- **Why:** the periodic re-apply exists because, according to comments from the first days, the firmware or `hid-nintendo` may restore its own LED pattern after an input report. That was never measured. The more likely writer is `joycond`, which drives the LEDs while it waits for L + R and when it combines Joy-Cons. Fewer writes also mean fewer HID subcommands, the cause of the drops fixed in v0.6.1.
- **Evidence:** 7 new unit checks (applied once, 10 simulated minutes without writes, charging still written, a reconnection applied again, invalid values fall back). **Not tested on hardware yet**: the plan is 15-30 minutes with `off`, first without `joycond` and then with it, watching whether any LED changes by itself.
- **Open questions:** if `off` holds without `joycond` but not with it, re-apply only when `joycond` acts instead of on a timer.

### ShellCheck becomes a required check

- **What changed:** the ShellCheck job no longer runs as informational: a new warning in the service scripts now fails CI, like the tests and the interface job.
- **Why:** v0.8.0 brought it to zero warnings (confirmed on the release commit), so keeping it informational would only hide regressions.

---

## v0.8.0 - The interface joins the repository

*2026-10-16 · minor (`feat(ui)`) · 21 commits since v0.7.1*

The graphical interface prototype now lives in the repository with its own browser tests, and the GitHub page became a user manual with this devlog, CI, community files and credits. The service itself did not change in this release; the interface still uses simulated data.

### Release housekeeping

- **What changed:** package versions synchronized with the tag for the first time (`PKGBUILD`, `.spec` and `debian/changelog` said `0.1.0` since v0.1.0); README title, patch notes and the version shown in the interface's Credits & Info updated; the nine README screenshots refreshed from the current interface; the ShellCheck warnings that were not bugs silenced with explained directives; the interface CI job made blocking after its first two green runs.
- **Evidence:** slot tests 38/38 and interface tests 111/111 pass locally. ShellCheck is not installed locally, so its result is confirmed by CI only.

### Clearer controller outlines and separate shoulder buttons

- **What changed:** on the Pro Controller, DualSense, DualShock 4, Xbox One and Xbox Series diagrams the detail lines are now a light cool white instead of being drawn with the dark shell color, and each diagram shows four separate L/R shoulder and trigger buttons. Ten interface checks were added for it. Work by Codex (`d90adaf`).
- **Evidence:** Codex could not start Chromium in his environment; the checks were run by Claude in headless Chromium (47/47 for the panels) and the result was reviewed in screenshots.
- **Open questions:** the *Share* overlay on the Xbox Series diagram still looks lower than on the real controller.

### The interface moves into the repository

- **What changed:** the interface prototype now lives in [`ui/`](ui/README.md), versioned like the rest of the code, so two people (or agents) can no longer silently overwrite each other's edits. Only the 77 assets it actually uses came along (4.2 MB instead of 14 MB); experiments and backups stayed out. Its browser tests moved too (`ui/tests/`, 101 checks over 3 files, runnable with `ui/tests/run.sh`), and CI got an informational interface job.
- **Third-party artwork:** the controller pictures and icons are derived from Steam client assets (© Valve), and two reference images have no recorded origin. They are included with [`ui/assets/ASSETS-NOTICE.md`](ui/assets/ASSETS-NOTICE.md), which states that they are **not covered by the MIT license** and how rights holders can ask for removal. The long-term goal is artwork made for the project.
- **Evidence:** the list of assets was taken from what the browser actually requests across all 11 panels, after a first list built from the code missed 12 D-pad icons whose names are put together at run time; the panel test caught it. A negative check confirmed the panel test fails (exit 1) on the copy from before the Joy-Con fix.
- **Open questions:** whether to make the interface CI job blocking once it has proven stable on the runners.

### Interface prototype: a full-page audit

- **What changed:** with the interface folder idle, every one of the 11 controller panels was opened in a scripted headless Chromium and checked for missing assets, broken images, layout overflow and JavaScript errors. Two real bugs were fixed: on the three Joy-Con diagrams the colored A/B/X/Y buttons sat 9-36 px above the drawn circles (the diagram had gained a band on top for the L/ZL and R/ZR miniatures, but the button positions were still computed for the old box), and the green status dot of the new service pill was being pulled into the middle of the controller diagram by an unrelated generic `.dot` style.
- **Evidence:** all 12 literal assets and 53 icon files exist; 11/11 panels render with no broken image, no overflow and 0 JavaScript errors; the Joy-Con button deviation went from 9-36 px to 0 px; the 52 + 28 interface checks still pass.
- **Open questions:** on the DualShock 4 and Xbox Series diagrams the body lines are still very dim on the dark background, and the Series *Share* overlay looks lower than on the real controller. Both are visual-design calls, reported rather than changed.

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
