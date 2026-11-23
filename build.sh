#!/bin/bash
set -eu
cd "$(dirname "$0")"
app="build/Keyboard Mouse Switcher.app"
bin="$app/Contents/MacOS"
rm -rf "$app"
mkdir -p "$bin" "$app/Contents/Resources"
cp Info.plist "$app/Contents/"
cp LICENSE-mxswitch "$app/Contents/Resources/"
# App icon: the menu bar's "keyboard" SF Symbol on a rounded tile.
swift make-icon.swift "build/AppIcon.iconset"
iconutil -c icns "build/AppIcon.iconset" -o "$app/Contents/Resources/AppIcon.icns"
flags=(-arch arm64 -arch x86_64 -mmacosx-version-min=13.0 -O2 -Wall)
clang "${flags[@]}" mxswitch.c -framework IOKit -framework CoreFoundation -framework CoreGraphics -o "$bin/mxswitch"
clang "${flags[@]}" -fobjc-arc Follow.m -framework Cocoa -framework IOKit -framework ServiceManagement -o "$bin/KeyboardMouseSwitcher"
codesign --force -s - "$bin/mxswitch"
codesign --force -s - "$app"
codesign --verify --deep --strict "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "build/Keyboard Mouse Switcher.zip"
echo "Built: $app"
