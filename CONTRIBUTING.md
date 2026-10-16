# Contributing to UJM

Thanks for helping. The most valuable contribution is often **not code**: a test report from a controller the maintainers do not own. See the [volunteer testing guide](docs/volunteer-testing.md).

## Ways to help

- **Test a controller** and report what you saw (button, LEDs, battery, numbering). Use the [volunteer test template](https://github.com/joaovitor-dv/universal-joystick-manager/issues/new?template=controller-testing.md).
- **Report a bug** with the bug-report form. Include the UJM version and the output of `joystickmanager-doctor`.
- **Improve the docs** if something in the [README](README.md) confused you.
- **Send code** for a fix or a new controller profile.

Before sharing logs, remove full MAC addresses, serial numbers, user names and personal paths (replace them with `XX`).

## Ground rules

- **Be honest about evidence.** Say whether a change was verified on real hardware, with which controller, how many runs, or that it was only reasoned about. The [devlog](DEVLOG.md) shows the style.
- **No hardware, no `validated`.** A controller family is only promoted from `experimental` to `validated` in [`controllers.tsv`](controllers.tsv) after at least one reproducible, documented test.
- **Keep changes small and auditable.** One topic per commit.
- Be kind: see the [Code of Conduct](CODE_OF_CONDUCT.md).

## Development setup

You only need `bash` and standard tools. The tests use a fake sysfs and never touch real LEDs or Bluetooth:

```bash
bash tests/test_slots.sh      # exit status = number of failures
```

Useful while developing:

- `udevadm verify udev/99-joystickmanager-procontroller-charge-only.rules` checks the udev rule.
- `shellcheck joystickmanager.sh joystickmanager-doctor install.sh` is run (informationally) by CI.
- `ui/tests/run.sh` runs the interface tests in headless Chromium (Node.js 22+; set `CHROME` if the browser is not called `chromium`).
- The service reads `/sys` through variables (`JOYMANAGER_SYS_INPUT`, `JOYMANAGER_SYS_LEDS`, `JOYMANAGER_SYS_POWER`), which is how the tests fake hardware.

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org/), in English: `feat:`, `fix:`, `docs:`, `test:`, `chore:`, `i18n:`. Explain the *why* in the body when it is not obvious, and mention how you verified the change.

## Adding a controller profile

1. Add a row to [`controllers.tsv`](controllers.tsv) (columns are documented at the top of the file). New families start as `experimental`.
2. Add a test in `tests/test_slots.sh` with a fake input node (see `fake_input`).
3. Add a devlog entry and, if you tested it, say how.

## Versioning

SemVer 0.x while the validated hardware matrix is incomplete:

| Change | Bump |
|---|---|
| `feat:` new capability, family or component | minor (`0.x.0`) |
| `fix:` without an interface change | patch (`0.x.y`) |
| A default-behavior change | patch or minor, by judgment (say which in the tag message) |
| `docs:`, `test:`, `i18n:`, `chore:` | none |

`1.0.0` is reserved for when the validated matrix in the README is complete.

## Cutting a release (maintainers)

1. Tag the commit with an **annotated** tag: `git tag -a vX.Y.Z -m "vX.Y.Z - <title>"`, with the classification in the message.
2. Add its entry to the [devlog](DEVLOG.md).
3. Update the version in the **README title** and the **Patch notes** table at the end of the README.
4. Update the package versions (`PKGBUILD`, `.spec`, `debian/changelog`).
5. Push the branch and the tag, then create the GitHub release (mark it as a pre-release while the version is 0.x).
