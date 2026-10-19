#!/bin/bash
# Renders the app icon from the game's own 3D room (IconMaker.swift) in the booted simulator and copies it
# into the asset catalog (AppIcon and AppIcon-Dev with the DEV band) and brand/icon-1024.png.
# Needs a booted simulator and a Debug build installed (Xcode or tools/sim-run.sh).
set -euo pipefail
cd "$(dirname "$0")/.."
xcrun simctl terminate booted com.blubergames.perfectfit 2>/dev/null || true
xcrun simctl launch booted com.blubergames.perfectfit -pfHome -pfIcon >/dev/null
sleep 8
C=$(xcrun simctl get_app_container booted com.blubergames.perfectfit data)
cp "$C/Documents/icon-1024.png" PerfectFit/Assets.xcassets/AppIcon.appiconset/icon-1024.png
cp "$C/Documents/icon-dev-1024.png" PerfectFit/Assets.xcassets/AppIcon-Dev.appiconset/icon-1024.png
cp "$C/Documents/icon-1024.png" brand/icon-1024.png
echo "Íconos actualizados."
