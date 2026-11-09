#!/bin/bash
# Builds a Release Herder.app and wraps it in a DMG. Run through `just package`,
# which generates the project and builds the frameworks first.
#
# VERSION            sets the marketing version and, with the commit count, the build number.
# CODESIGN_IDENTITY  signs with a Developer ID; unset, the app and DMG are ad-hoc signed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
DERIVED="$BUILD/DerivedData"
APP="$BUILD/Herder.app"
DMG="$BUILD/Herder.dmg"
STAGE="$BUILD/dmg"
ENTITLEMENTS="$ROOT/Herder/Herder.entitlements"
ARCH="$(uname -m)"

settings=("HERDER_GIT_COMMIT=$(git -C "$ROOT" rev-parse --short HEAD)")
if [[ -n "${VERSION:-}" ]]; then
    settings+=("MARKETING_VERSION=$VERSION" "CURRENT_PROJECT_VERSION=$(git -C "$ROOT" rev-list --count HEAD)")
fi

# Signing happens below, so the build itself is unsigned.
xcodebuild \
    -project "$ROOT/Herder.xcodeproj" \
    -scheme Herder \
    -configuration Release \
    -destination "platform=macOS,arch=$ARCH" \
    -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO \
    ONLY_ACTIVE_ARCH=YES \
    ${settings[@]+"${settings[@]}"} \
    -quiet \
    build

rm -rf "$APP"
# ditto rather than cp, to keep the bundle intact.
ditto "$DERIVED/Build/Products/Release/Herder.app" "$APP"

# A release must say the version its tag does. Checked here, before
# anything is signed or notarized, rather than found in Settings later.
built="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
if [[ -n "${VERSION:-}" && "$built" != "$VERSION" ]]; then
    printf 'Built version %s, expected %s\n' "$built" "$VERSION" >&2
    exit 1
fi
printf 'Version %s (%s), commit %s\n' "$built" \
    "$(plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist")" \
    "$(plutil -extract HerderGitCommit raw "$APP/Contents/Info.plist")"

sign() {  # usage: sign [codesign args...] <path>
    if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
        codesign --force --sign "$CODESIGN_IDENTITY" --timestamp --options runtime "$@"
    else
        codesign --force --sign - "$@"
    fi
}

# Inside out, and not with --deep, which would strip the entitlements
# Sparkle's downloader is signed with. The order is Sparkle's own:
# https://sparkle-project.org/documentation/sandboxing/#code-signing
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
sign "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
sign "$SPARKLE/Versions/B/Autoupdate"
sign "$SPARKLE/Versions/B/Updater.app"
sign "$SPARKLE"
sign --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

rm -rf "$STAGE"
rm -f "$DMG"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Herder.app"
ln -s /Applications "$STAGE/Applications"

hdiutil create \
    -volname Herder \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DMG"

rm -rf "$STAGE"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    codesign --force --sign "$CODESIGN_IDENTITY" --timestamp "$DMG"
    codesign --verify --strict --verbose=2 "$DMG"
fi

printf 'Packaged %s\n' "$DMG"
