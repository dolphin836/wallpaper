#!/usr/bin/env bash
# Package the SwiftPM executable into a redistributable .app (and optionally .dmg),
# and optionally copy the .dmg into the frontend's static public directory so
# the web /download/mac page can link to it.
#
# Usage:
#   ./build-app.sh                # builds Wallpaper Exchange.app, ad-hoc signed
#   ./build-app.sh --dmg          # additionally wraps the .app in a .dmg
#   ./build-app.sh --release      # implies --dmg, also copies to frontend/public
#   ./build-app.sh --sign "Developer ID Application: Your Name (TEAMID)"
#                                 # signs with a real Developer ID cert
#
# Output:
#   ./Wallpaper Exchange.app/      .app bundle, ready to run / drag to /Applications
#   ./Wallpaper Exchange.dmg       (if --dmg or --release)
#   ../frontend/public/downloads/mac/WallpaperExchange-<version>.dmg
#                                  (if --release)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/WallpaperExchange"

readonly APP_NAME="Wallpaper Exchange"
readonly EXECUTABLE="WallpaperExchange"
readonly APP_DIR="../${APP_NAME}.app"
readonly INFO_PLIST="Info.plist"

SIGN_IDENTITY="-"   # default: ad-hoc sign (any Mac can launch, but Gatekeeper warns)
MAKE_DMG=0
DO_UPLOAD=0

while [ $# -gt 0 ]; do
    case "$1" in
        --dmg)
            MAKE_DMG=1
            shift
            ;;
        --release)
            MAKE_DMG=1
            DO_UPLOAD=1
            shift
            ;;
        --sign)
            SIGN_IDENTITY="$2"
            shift 2
            ;;
        *)
            echo "unknown flag: $1" >&2
            exit 1
            ;;
    esac
done

echo "==> Building release binary (universal: arm64 + x86_64)..."
# Build each architecture separately and lipo them together. Intel Macs
# can't run a thin-arm64 binary — they will silently fail to launch
# (no Dock icon, no menu-bar icon) instead of showing an error, which
# is indistinguishable from "double-click does nothing".
swift build -c release --arch arm64
swift build -c release --arch x86_64

readonly ARM_BUILD_DIR=".build/arm64-apple-macosx/release"
readonly X86_BUILD_DIR=".build/x86_64-apple-macosx/release"

echo "==> Assembling ${APP_DIR}..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

lipo -create \
    "$ARM_BUILD_DIR/$EXECUTABLE" \
    "$X86_BUILD_DIR/$EXECUTABLE" \
    -output "$APP_DIR/Contents/MacOS/$EXECUTABLE"
cp "$INFO_PLIST" "$APP_DIR/Contents/Info.plist"

# Resources are loaded via Bundle.main from Contents/Resources/ rather than
# through SwiftPM's Bundle.module accessor — that accessor expects the
# resource bundle to live at the .app root, which violates the macOS
# bundle layout and trips `codesign --strict` ("unsealed contents present
# in the bundle root"). Package.swift no longer declares `resources:`;
# instead we copy Sources/Resources/ contents straight into the standard
# Contents/Resources/ location.
if [ -d "Sources/Resources" ]; then
    cp -R Sources/Resources/. "$APP_DIR/Contents/Resources/"
fi

if [ -f "../AppIcon.icns" ]; then
    cp ../AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" \
        "$APP_DIR/Contents/Info.plist" 2>/dev/null || true
fi

echo "==> Code-signing with: $SIGN_IDENTITY"
codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$APP_DIR"
codesign -dv --verbose=2 "$APP_DIR" 2>&1 | head -5

DMG_PATH=""
if [ "$MAKE_DMG" -eq 1 ]; then
    DMG_PATH="../${APP_NAME}.dmg"
    echo "==> Creating DMG: $DMG_PATH"
    rm -f "$DMG_PATH"

    # Build the standard Mac installer experience: a Finder window that
    # opens on mount, with the .app icon on the left and an Applications
    # shortcut on the right, so the user can drag-to-install instead of
    # having to know to drop the bundle into /Applications themselves.
    #
    # The mechanics: stage the .app + an Applications symlink in a temp
    # dir, build a writable HFS+ DMG from that staging dir, mount it,
    # drive Finder via AppleScript to set window bounds + icon positions,
    # detach, and convert to a compressed read-only UDZO image.
    STAGING_DIR=$(mktemp -d)
    cp -R "$APP_DIR" "$STAGING_DIR/"
    ln -s /Applications "$STAGING_DIR/Applications"

    TEMP_DMG=$(mktemp -u).dmg
    hdiutil create -volname "$APP_NAME" \
        -srcfolder "$STAGING_DIR" \
        -fs HFS+ -format UDRW -ov \
        "$TEMP_DMG" >/dev/null

    # Detach any stale mount with the same volume name before attaching
    # — otherwise the second mount lands on "/Volumes/<name> 1" and the
    # AppleScript can't find the disk by name.
    if [ -d "/Volumes/$APP_NAME" ]; then
        hdiutil detach "/Volumes/$APP_NAME" -force >/dev/null 2>&1 || true
    fi
    MOUNT_INFO=$(hdiutil attach "$TEMP_DMG" -readwrite -noverify -noautoopen)
    DEVICE=$(printf '%s\n' "$MOUNT_INFO" | head -1 | awk '{print $1}')
    sleep 2 # let Finder notice the new volume before we script it

    osascript <<APPLESCRIPT
with timeout of 300 seconds
    tell application "Finder"
        tell disk "$APP_NAME"
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set the bounds of container window to {320, 200, 920, 500}
            set theViewOptions to the icon view options of container window
            set arrangement of theViewOptions to not arranged
            set icon size of theViewOptions to 128
            set text size of theViewOptions to 13
            set position of item "${APP_NAME}.app" of container window to {160, 150}
            set position of item "Applications" of container window to {440, 150}
            close
            open
            update without registering applications
            delay 1
        end tell
    end tell
end timeout
APPLESCRIPT

    sync
    hdiutil detach "$DEVICE" -force >/dev/null
    rm -rf "$STAGING_DIR"

    hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -ov \
        -o "$DMG_PATH" >/dev/null
    rm -f "$TEMP_DMG"

    echo "==> DMG ready: $DMG_PATH"
fi

if [ "$DO_UPLOAD" -eq 1 ]; then
    # Pull version from Info.plist so the published filename always matches what
    # the running app reports. Single source of truth.
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")
    if [ -z "$VERSION" ]; then
        echo "==> ERROR: couldn't read CFBundleShortVersionString from Info.plist" >&2
        exit 1
    fi

    STATIC_DIR="$SCRIPT_DIR/../frontend/public/downloads/mac"
    STATIC_NAME="WallpaperExchange-${VERSION}.dmg"
    STATIC_PATH="$STATIC_DIR/$STATIC_NAME"
    RELATIVE_URL="/downloads/mac/$STATIC_NAME"

    mkdir -p "$STATIC_DIR"
    cp "$DMG_PATH" "$STATIC_PATH"
    echo "==> Release copied to frontend static asset: $STATIC_PATH"
    echo "    URL: $RELATIVE_URL"

    # Keep only the current release in the repo. Each DMG adds ~4MB to git
    # forever, and the update flow only ever downloads current_dmg_url, so
    # superseded DMGs are dead weight. git rm stages the deletion for the
    # release commit; rm -f catches untracked leftovers.
    REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
    for old in "$STATIC_DIR"/WallpaperExchange-*.dmg; do
        [ -e "$old" ] || continue
        [ "$(basename "$old")" = "$STATIC_NAME" ] && continue
        echo "==> Removing superseded DMG: $(basename "$old")"
        git -C "$REPO_ROOT" rm -q --ignore-unmatch \
            "frontend/public/downloads/mac/$(basename "$old")" || true
        rm -f "$old"
    done

    cat <<HINT

==> Release packaged. To make it visible on /download/mac:

  1. Edit backend/internal/handler/mac_release.json
     - bump current_version to: $VERSION
     - set current_dmg_url to: $RELATIVE_URL
     - prepend a new entry to "releases" with this version + notes
  2. Mirror the same notes into macos/CHANGELOG.md (Keep a Changelog format).
  3. Commit the version files, $STATIC_PATH, and the staged removal of
     superseded DMGs, then deploy frontend + backend.
HINT
fi

if [ "$DO_UPLOAD" -ne 1 ]; then
    cat <<EOF

Next steps:
  - Drag the .app to /Applications to install locally.
  - To share with others, see macos/PACKAGING.md for code signing,
    notarization, and Gatekeeper considerations.
  - To publish on the web /download/mac page, re-run with --release.
EOF
fi
