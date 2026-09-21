#!/bin/bash
# Installs the latest SideEye release into /Applications and opens it.
#   curl -fsSL https://raw.githubusercontent.com/ishmael07/SideEye/main/install.sh | bash
# SideEye is free and open source but not notarized by Apple yet. Files fetched with curl aren't
# quarantined, so installing this way skips the "cannot be opened" dialog a browser download gets.
set -euo pipefail

[[ "$(uname)" == "Darwin" ]] || { echo "SideEye is a Mac app."; exit 1; }
major=$(sw_vers -productVersion | cut -d. -f1)
[[ "$major" =~ ^[0-9]+$ ]] && (( major >= 14 )) || { echo "SideEye needs macOS 14 or later (this Mac has $(sw_vers -productVersion))."; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
echo "Downloading SideEye…"
curl -fsSL "https://github.com/ishmael07/SideEye/releases/latest/download/SideEye.zip" -o "$work/SideEye.zip"
ditto -x -k "$work/SideEye.zip" "$work"

apps="/Applications"; [[ -w "$apps" ]] || { apps="$HOME/Applications"; mkdir -p "$apps"; }   # standard accounts can't write to /Applications
pkill -x SideEye 2>/dev/null || true                 # a running copy can't be replaced
rm -rf "$apps/SideEye.app"
mv "$work/SideEye.app" "$apps/"
xattr -dr com.apple.quarantine "$apps/SideEye.app" 2>/dev/null || true
open "$apps/SideEye.app"
echo "SideEye is in your menu bar (the eye icon). macOS will ask for camera access: that's the face tracking, and it never leaves your Mac."
