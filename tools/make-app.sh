#!/bin/bash
# Assembles something.app in <prefix>: Contents/Info.plist with <version>, Contents/MacOS/something (stripped),
# Contents/Resources/share and the icon, then an ad-hoc signature (no Apple account) that seals the bundle. A something.app
# already in <prefix> is replaced. The program is stamped with the SDK that compiled it: swift build's default build
# system records an older one, and macOS gives its current look only to a program stamped with a recent SDK.
#
#   tools/make-app.sh <prefix> <version> [<executable>]
#
# <executable> is the something program already built; Homebrew's formula passes .build/release/something after its
# own `swift build`, which runs inside Homebrew's sandbox where a second swift build could not. Without it, this
# script builds it with `swift build -c release`, which builds again only what changed.
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: tools/make-app.sh <prefix> <version> [<executable>], for example: tools/make-app.sh /tmp/example 1.0.0" >&2
  exit 2
fi
prefix=$1
version=$2
if [[ -z $prefix || -z $version ]]; then
  echo "The prefix and the version must not be empty, for example: tools/make-app.sh /tmp/example 1.0.0" >&2
  exit 2
fi
repository=$(cd "$(dirname "$0")/.." && pwd)
if [[ $# -eq 3 ]]; then
  executable=$3
else
  (cd "$repository" && swift build -c release --product something)
  executable="$(cd "$repository" && swift build -c release --show-bin-path)/something"
fi
if [[ ! -x $executable ]]; then
  echo "There is no something program at $executable: build it with swift build -c release, or leave the third argument out." >&2
  exit 1
fi

app="$prefix/something.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$repository/packaging/Info.plist" "$app/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$version" "$app/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$version" "$app/Contents/Info.plist"
minimum=$(plutil -extract LSMinimumSystemVersion raw "$app/Contents/Info.plist")
xcrun vtool -set-build-version macos "$minimum" "$(xcrun --show-sdk-version)" -replace -output "$app/Contents/MacOS/something" "$executable"
# The local symbols only serve a debugger: without them the program is half its size. The signature comes after.
strip -x "$app/Contents/MacOS/something"
cp -R "$repository/share" "$app/Contents/Resources/share"
cp "$repository/packaging/something.icns" "$app/Contents/Resources/something.icns"
codesign --force --sign - "$app"
