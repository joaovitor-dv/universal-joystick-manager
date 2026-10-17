#!/usr/bin/env bash
# Measures the QML baseline and the WebEngine shell (default and lean Chromium flags), same method for all.
# usage: gui/measure/run_all.sh [idle-seconds]   (needs a graphical session; QT_QPA_PLATFORM=offscreen also works)
cd "$(dirname "$0")/../.." || exit 1
idle=${1:-15}; M=gui/measure/measure_gui.py
run() { printf '\n=== %s\n' "$1"; shift; "$@" 2>&1 | grep -vE 'ERROR|^qt\.|^\[[0-9]+:[0-9]+:'; }
run "QML baseline (Basic style)" python3 $M --idle "$idle" -- python3 gui/qml_baseline.py
run "WebEngine, default flags" python3 $M --idle "$idle" -- python3 gui/ujm_gui_webengine.py
run "WebEngine, lean flags" env QTWEBENGINE_CHROMIUM_FLAGS="--disable-gpu --renderer-process-limit=1 --disable-background-networking --disable-features=Translate,MediaRouter,OptimizationHints,AutofillServerCommunication --js-flags=--max-lazy" python3 $M --idle "$idle" -- python3 gui/ujm_gui_webengine.py
