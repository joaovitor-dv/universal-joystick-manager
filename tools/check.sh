#!/usr/bin/env bash
# Runs locally what CI runs, so a push does not find the errors first.
#
#   tools/check.sh              the CI "Tests" and "ShellCheck" jobs (what blocks a merge)
#   tools/check.sh --ui         also the interface tests in headless Chromium (needs node and a Chrome/Chromium)
#   tools/check.sh --gui        also the QML interface tests (needs PySide6)
#   tools/check.sh --packages   also build the .deb, .rpm (Docker) and Arch package (makepkg) and inspect them
#   tools/check.sh --all        everything above
#   tools/check.sh --since REF  documentation check against REF (default: the latest tag)
#
# Exit status: the number of failed checks. A check that cannot run here is reported as "skip"
# with the reason, never silently passed. Documentation hints are "warn" and do not fail.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

do_ui=0 do_gui=0 do_pkg=0 since=""
while [ $# -gt 0 ]; do
    case "$1" in
        --ui) do_ui=1;;
        --gui) do_gui=1;;
        --packages) do_pkg=1;;
        --all) do_ui=1 do_gui=1 do_pkg=1;;
        --since) since=${2:-}; shift;;
        -h|--help) sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0;;
        *) printf 'unknown option: %s\n' "$1" >&2; exit 2;;
    esac
    shift
done

fails=0 warns=0 skips=0
log=$(mktemp); trap 'rm -f "$log"' EXIT

ok()   { printf 'ok    %s\n' "$1"; }
bad()  { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); [ -s "$log" ] && sed 's/^/        /' "$log" | tail -25; }
skip() { printf 'skip  %s (%s)\n' "$1" "$2"; skips=$((skips + 1)); }
warn() { printf 'warn  %s\n' "$1"; warns=$((warns + 1)); }
step() { # description command...
    local d=$1; shift
    : >"$log"
    if "$@" >"$log" 2>&1; then ok "$d"; else bad "$d"; fi
}

# ---- what the CI "Tests" job runs ---------------------------------------------------------
step "unit tests (fake sysfs)" bash tests/test_slots.sh
step "bash syntax" bash -c 'for f in joystickmanager.sh joystickmanager-doctor install.sh tests/test_slots.sh tools/*.sh; do [ -e "$f" ] || continue; bash -n "$f" || { echo "syntax error in $f"; exit 1; }; done'
step "python compiles" bash -c 'python3 -m py_compile switchpro-leds.py bridge/ujm-bridge bridge/tests/test_bridge.py bridge/tests/fake_bluez.py gui/ujm_gui.py gui/tests/test_gui.py; r=$?; find . -name __pycache__ -not -path "./ui/*" -prune -exec rm -rf {} + 2>/dev/null; exit $r'
step "report script masks Bluetooth addresses" tools/collect-report.sh --self-test
step "profile table has 7 fields per row" awk -F'\t' '!/^#/ && NF != 7 { printf "line %d has %d fields, expected 7\n", NR, NF; bad=1 } END { exit bad }' controllers.tsv
if command -v udevadm >/dev/null 2>&1 && udevadm verify --help >/dev/null 2>&1; then
    step "udev rule is valid" udevadm verify udev/99-joystickmanager-procontroller-charge-only.rules
else skip "udev rule is valid" "udevadm verify not available"; fi
if command -v xmllint >/dev/null 2>&1; then
    step "bridge XML files are well formed" xmllint --noout --nonet bridge/org.ujm.Manager1.conf bridge/org.ujm.manager.policy
else skip "bridge XML files are well formed" "xmllint not installed (libxml2)"; fi
if command -v dbus-run-session >/dev/null 2>&1 && python3 -c 'import gi; gi.require_version("Gio","2.0")' 2>/dev/null; then
    step "bridge tests (private D-Bus session)" dbus-run-session -- python3 -W ignore bridge/tests/test_bridge.py
else skip "bridge tests" "needs dbus-run-session and python3-gi"; fi

# ---- the CI "ShellCheck" job (blocking) ----------------------------------------------------
sc_files="joystickmanager.sh joystickmanager-doctor install.sh tests/test_slots.sh"
if command -v shellcheck >/dev/null 2>&1; then
    # shellcheck disable=SC2086
    step "ShellCheck" shellcheck -S warning $sc_files
elif docker image inspect koalaman/shellcheck:stable >/dev/null 2>&1; then
    # shellcheck disable=SC2086
    step "ShellCheck (Docker)" docker run --rm -v "$PWD:/mnt:ro" -w /mnt koalaman/shellcheck:stable -S warning $sc_files
else skip "ShellCheck" "not installed: CI blocks on it. Arch: sudo pacman -S shellcheck"; fi

# ---- optional: interface (Codex's prototype) ------------------------------------------------
if [ "$do_ui" = 1 ]; then
    if command -v node >/dev/null 2>&1; then step "HTML interface tests (headless Chromium)" ui/tests/run.sh
    else skip "HTML interface tests" "node not found"; fi
fi

# ---- optional: QML interface ------------------------------------------------------------------
if [ "$do_gui" = 1 ]; then
    if python3 -c 'import PySide6.QtQuick' 2>/dev/null && command -v dbus-run-session >/dev/null 2>&1; then
        step "QML interface tests (offscreen)" dbus-run-session -- python3 -W ignore gui/tests/test_gui.py
    else skip "QML interface tests" "needs PySide6 and dbus-run-session"; fi
fi

# ---- optional: packages -----------------------------------------------------------------------
check_deb_rpm() {
    docker run --rm -v "$PWD":/src:ro node:22-bookworm bash -c '
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null && apt-get install -y -qq --no-install-recommends build-essential debhelper dpkg-dev rpm cpio >/dev/null 2>&1
cp -r /src /b && cd /b && rm -rf debian && cp -r packaging/debian debian
dpkg-buildpackage -us -uc -b >/dev/null 2>&1
deb=$(ls ../universal-joystick-manager_*_all.deb)
list=$(dpkg-deb -c "$deb")
for f in usr/bin/joystickmanager.sh usr/lib/joystickmanager/switchpro-leds usr/lib/joystickmanager/ujm-bridge usr/share/polkit-1/actions/org.ujm.manager.policy usr/share/dbus-1/system.d/org.ujm.Manager1.conf lib/systemd/system/ujm-bridge.service; do
    echo "$list" | grep -q "$f" || { echo "deb is missing $f"; exit 1; }
done
dpkg-deb --fsys-tarfile "$deb" | tar -xO ./lib/systemd/system/joystickmanager.service | grep -q "^ExecStart=/usr/bin/joystickmanager.sh$" || { echo "deb unit ExecStart"; exit 1; }
dpkg-deb -e "$deb" /tmp/ctl
if cat /tmp/ctl/postinst 2>/dev/null | grep -q "deb-systemd-invoke"; then echo "deb postinst starts a service"; exit 1; fi
rpmbuild -bb --define "_sourcedir $PWD" --define "_topdir /tmp/rpm" --define "_unitdir /usr/lib/systemd/system" packaging/fedora/universal-joystick-manager.spec >/dev/null 2>&1
rpm=$(ls /tmp/rpm/RPMS/noarch/*.rpm)
for f in joystickmanager-switchpro-leds libexec/ujm-bridge polkit-1/actions/org.ujm.manager.policy dbus-1/system.d/org.ujm.Manager1.conf; do
    rpm -qlp "$rpm" | grep -q "$f" || { echo "rpm is missing $f"; exit 1; }
done
rpm2cpio "$rpm" | cpio -i --to-stdout ./usr/lib/systemd/system/joystickmanager.service 2>/dev/null | grep -q "^ExecStart=/usr/bin/joystickmanager.sh$" || { echo "rpm unit ExecStart"; exit 1; }
echo "deb and rpm built and inspected"'
}
check_arch() {
    local t; t=$(mktemp -d)
    ( cd packaging/arch && PKGDEST=$t BUILDDIR=$t/build SRCDEST=$t makepkg -f --nodeps ) || return 1
    local pkg; pkg=$(ls "$t"/*.pkg.tar.zst) || return 1
    bsdtar -tf "$pkg" | grep -q 'usr/lib/joystickmanager/ujm-bridge' || { echo "arch package has no bridge"; return 1; }
    bsdtar -xOf "$pkg" usr/lib/systemd/system/joystickmanager.service | grep -q '^ExecStart=/usr/bin/joystickmanager.sh$' || { echo "arch unit ExecStart"; return 1; }
    if command -v namcap >/dev/null 2>&1; then namcap "$pkg" | grep -E ' E: ' && return 1; fi
    rm -rf "$t"
}
if [ "$do_pkg" = 1 ]; then
    if docker image inspect node:22-bookworm >/dev/null 2>&1; then step ".deb and .rpm build and inspection (Docker)" check_deb_rpm
    else skip ".deb and .rpm" "needs Docker and the node:22-bookworm image (docker pull node:22-bookworm)"; fi
    if command -v makepkg >/dev/null 2>&1 && command -v bsdtar >/dev/null 2>&1; then step "Arch package builds (makepkg)" check_arch
    else skip "Arch package" "makepkg not found (not an Arch system)"; fi
fi

# ---- documentation hints (do not fail) -----------------------------------------------------------
# A commit that changes behavior updates its documentation in the same commit; these hints look
# at everything since the last tag (or --since).
[ -n "$since" ] || since=$(git describe --tags --abbrev=0 2>/dev/null || true)
if [ -n "$since" ] && git rev-parse --verify -q "$since^{commit}" >/dev/null; then
    changed=$(git diff --name-only "$since"...HEAD 2>/dev/null)
    has() { printf '%s\n' "$changed" | grep -Eq "$1"; }
    if has '^(joystickmanager\.sh|joystickmanager-doctor|install\.sh|bridge/ujm-bridge|gui/(ujm_gui\.py|qml/)|packaging/)' && ! has '^DEVLOG\.md$'; then
        warn "code changed since $since but DEVLOG.md did not"
    fi
    if has '^bridge/ujm-bridge$' && ! has '^docs/bridge\.md$'; then warn "bridge/ujm-bridge changed since $since but docs/bridge.md did not"; fi
    if has '^joystickmanager\.sh$' && git diff "$since"...HEAD -- joystickmanager.sh | grep -q '^+.*"format":"ujm-state"' && ! has '^docs/state\.md$'; then
        warn "the state.json format changed since $since but docs/state.md did not"
    fi
    if has '^(packaging/|install\.sh)' && ! has '^docs/packaging\.md$'; then warn "packaging changed since $since but docs/packaging.md did not"; fi
else skip "documentation hints" "no tag or --since REF to compare with"; fi

printf '\n%d failed, %d warning(s), %d skipped\n' "$fails" "$warns" "$skips"
exit "$fails"
