#!/usr/bin/env bash
# Runs the interface browser tests against a local HTTP server.
# Usage: ui/tests/run.sh   (CHROME=/path/to/browser if it is not called chromium)
# Exit status = number of test files that failed.
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ui=$(dirname "$here")
port=${UJM_UI_PORT:-8765}

python3 -m http.server "$port" --bind 127.0.0.1 --directory "$ui" >/dev/null 2>&1 &
server=$!
trap 'kill "$server" 2>/dev/null' EXIT
for _ in $(seq 1 40); do
    python3 -c "import urllib.request,sys; urllib.request.urlopen('http://127.0.0.1:$port/index.html')" 2>/dev/null && break
    sleep 0.25
done

fails=0
for t in "$here"/*.test.mjs; do
    printf '# %s\n' "$(basename "$t")"
    node "$t" "http://127.0.0.1:$port/index.html" || fails=$((fails + 1))
done
printf '\n%s test file(s) failed\n' "$fails"
exit "$fails"
