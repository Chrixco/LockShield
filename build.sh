#!/bin/bash
# Builds build/LockShield.app from Sources/main.swift.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/LockShield.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp Icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"  # regenerate with: swift Icon/make_icon.swift
swiftc -O -swift-version 5 -o "$APP/Contents/MacOS/LockShield" Sources/*.swift

# Sign with the Apple Development certificate when there is one, so macOS keeps the
# Accessibility permission across rebuilds. An ad-hoc signature ("-") changes with
# every build and macOS then asks for the permission again.
IDENTITY="$(security find-identity -v -p codesigning | awk '/Apple Development/ { print $2; exit }')"
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "Built $APP"
