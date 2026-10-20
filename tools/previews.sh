#!/bin/sh
# Draws the previews of share/templates again: each template is checked as `something check` checks a space (in this
# program's tests, against the invented state of share/contract), in its own appearance, and the check's snapshot is
# kept as <name>.png; previews.json gets the SHA-256 of each HTML its picture was made from, which TemplatesTests
# compares. The pictures themselves are never compared: the hash says which HTML a picture was made from, not that it
# looks right, which is for whoever runs this to look at. Run it from anywhere in the clone after changing a template. Needs a window server: run it on a Mac where someone is logged in. Nothing is shown
# on the screen.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
mark=$(mktemp)
trap 'rm -f "$mark"' EXIT
SOMETHING_PREVIEWS="$root/share/templates" swift test --filter 'TemplatesTests/makesThePreviews'
# A filter that matches no test passes too: each picture must be newer than this run's start.
for page in share/templates/*.html; do
    picture="${page%.html}.png"
    if [ ! "$picture" -nt "$mark" ] || [ ! share/templates/previews.json -nt "$mark" ]; then
        echo "$picture was not drawn again: the test makesThePreviews did not run. Look at the output above." >&2
        exit 1
    fi
done
echo "The previews of share/templates are drawn again; commit them with previews.json."
