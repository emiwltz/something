#!/bin/sh
# Draws the app's icon again, packaging/something.icns: a white tile with the sign, on Apple's 1024 grid, at every size
# macOS asks for. The test drawsTheIcon draws the pictures with the app's own Sign.draw, and iconutil, which comes with
# macOS, packs them: neither needs Xcode. Needs a window server: run it on a Mac where someone is logged in. Commit the
# binary. How it looks in the Dock can only be seen by hand.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
folder=$(mktemp -d)
trap 'rm -rf "$folder"' EXIT
SOMETHING_ICON="$folder/something.iconset" swift test --filter drawsTheIcon
# A filter that matches no test passes too: the iconset must be there.
iconutil -c icns "$folder/something.iconset" -o packaging/something.icns
echo "packaging/something.icns is drawn again; commit it."
