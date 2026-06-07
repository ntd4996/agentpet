#!/usr/bin/env bash
# Assembles AgentPet.app from a release build so it runs as a proper menu bar
# app (bundle id, LSUIElement, working notifications). Ad-hoc signed for local
# testing. Notarization + DMG + Homebrew are issue #13.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/build/AgentPet.app"
CONFIG="${1:-release}"

# Build native host architecture.
ARCHS=()

echo "Building ($CONFIG)..."
swift build -c "$CONFIG"
BINDIR="$(swift build -c "$CONFIG" --show-bin-path)"

echo "Assembling $APP ..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BINDIR/agentpet" "$APP/Contents/MacOS/agentpet"
cp "$ROOT/scripts/AppInfo.plist" "$APP/Contents/Info.plist"
# Sparkle compares the appcast's sparkle:version against the installed
# CFBundleVersion, and the appcast publishes the marketing version. Force
# CFBundleVersion == CFBundleShortVersionString so they can never drift (which
# would make Sparkle offer the same update forever).
SHORT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $SHORT_VERSION" "$APP/Contents/Info.plist"
[ -f "$ROOT/scripts/AppIcon.icns" ] && cp "$ROOT/scripts/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Note: SwiftPM emits an empty AgentPet_AgentPetCore.bundle, but nothing uses
# Bundle.module, so we deliberately do not copy it (it has no Info.plist and
# would break code signing). The app needs no runtime resource bundle.

# Bundle Sparkle.framework (auto-update). SwiftPM links it via @rpath but does
# not place it inside a hand-assembled .app, so we copy it into Frameworks and
# point the binary's rpath there. ditto preserves the framework symlinks.
mkdir -p "$APP/Contents/Frameworks"
ditto "$BINDIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/agentpet" 2>/dev/null || true

# Ad-hoc sign for local testing (release.sh re-signs with a Developer ID).
# Sign the framework first (inside-out) so the outer app signature is valid.
codesign --force --sign - "$APP/Contents/Frameworks/Sparkle.framework" || true
codesign --force --sign - "$APP" || echo "warning: codesign failed (continuing unsigned)"

echo "Done: $APP"
echo "Run with: open \"$APP\"   (or: \"$APP/Contents/MacOS/agentpet\")"
