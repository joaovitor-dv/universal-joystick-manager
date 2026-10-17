# Interface and service resource measurements

Goal: UJM must cost as little as possible, both the service and the interface. This records what was measured on 2026-10-16 and how to repeat it.

Machine: CachyOS (Arch), kernel 7.2.9, Qt 6.12, PySide6 6.12, Wayland session. One run per case, 15 s of idle sampling after 3 s of settling. **These are single samples on one machine.** PSS (proportional set size) divides shared pages between the processes that map them, so it is the fairest memory figure; RSS counts them in full.

## Interface: Chromium (QtWebEngine) against plain QML

| Case | Processes | Memory PSS | Memory RSS | Idle CPU | Start until ready |
|---|---|---|---|---|---|
| QML, `qml6` runtime, no Python | 1 | **93 MiB** | 150 MiB | 0.0% | not measured |
| QML in a PySide6 script | 1 | **108 MiB** | 171 MiB | 0.0% | 269 ms |
| PySide6 + QtWebEngine around `ui/index.html` | 5 | **332 MiB** | 570 MiB | 0.1% | 613 ms |
| same, with trimmed Chromium flags | 5 | 310 MiB | 548 MiB | 0.1% | 554 ms |

Disk (installed size on this system): `qt6-webengine` 283 MiB, `pyside6` 54 MiB, `qt6-declarative` 136 MiB (QML runtime, shared with other Qt software).

What it says:

- CPU is not the problem: all cases are idle at about 0%. **Memory and installed size are.** Chromium adds about **225 MiB (3x)** and four extra processes over plain QML, starts about 340 ms later, and brings a 283 MiB dependency.
- PySide6 itself costs about 15 MiB over the bare QML runtime, so Python is not what to remove first.
- Trimming Chromium flags (`--disable-gpu`, one renderer, fewer features) saved only about 22 MiB. It does not change the picture.
- Most of the 93 MiB floor is Qt Quick, OpenGL drivers and shared libraries that any Qt desktop application already maps.

Limits: the page measured is the current static prototype with simulated data, not the final interface with eight controllers and the monitoring views. The QML case is a four-rectangle window, so it is a floor, not a forecast. Everything ran on the GPU path of this machine; software rendering would differ. On this machine the **default** Qt Quick Controls style stalled at start-up inside the test environment, so the QML cases use the `Basic` style (also the lightest).

**Conclusion:** start the native QML interface and keep the WebEngine shell (`gui/ujm_gui_webengine.py`) only as a stop-gap that shows the prototype with real data until the QML one replaces it.

## Bridge

Python with GLib/GIO (`bridge/ujm-bridge`) on a private session bus with one controller published: **0.00% CPU over 20 s, 19.6 MiB PSS (32.7 MiB RSS), 4 threads.** When no client is left it exits after 30 s, so with the interface closed it costs nothing.

## Service (`joystickmanager.sh`): a fixed problem

While preparing the measurements, the idle service itself turned out to cost **about 11% of one CPU core with no controllers connected** (the installed copy and the repository version, 29 input nodes on this desktop): every 2 s cycle matched every keyboard, mouse and switch against the profile table, around 1000 short-lived processes. After skipping nodes already known not to be controllers (`perf:` commit, see the devlog) the same measurement gives **0.4%**. With controllers connected the cost is not measured yet.

## Repeating it

```bash
gui/measure/run_all.sh [seconds]        # needs a graphical session; QT_QPA_PLATFORM=offscreen also works
python3 gui/measure/measure_gui.py --idle 15 -- COMMAND...   # one command; the command may print "READY"
```

For the service, run it in a transient scope and read the cgroup counter (`systemd-run --user --scope -p CPUAccounting=yes ...`, then `cpu.stat` `usage_usec` twice). Reading `times` or `ps` is not enough: most of the work is in short-lived children.
