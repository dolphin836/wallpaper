#!/usr/bin/env bash
# Package the SwiftPM executable into a redistributable .app (and optionally .dmg).
#
# Usage:
#   ./build-app.sh                # builds Wallpaper Exchange.app, ad-hoc signed
#   ./build-app.sh --dmg          # additionally wraps the .app in a .dmg
#   ./build-app.sh --sign "Developer ID Application: Your Name (TEAMID)"
#                                 # signs with a real Developer ID cert (required
#                                 # to skip the Gatekeeper warning on receiving Macs;
#                                 # see PACKAGING.md for the notarize step)
#
# Output:
#   ./Wallpaper Exchange.app/      .app bundle, ready to run / drag to /Applications
#   ./Wallpaper Exchange.dmg       (if --dmg)
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/WallpaperExchange"

readonly APP_NAME="Wallpaper Exchange"
readonly EXECUTABLE="WallpaperExchange"
readonly APP_DIR="../${APP_NAME}.app"
readonly BUILD_DIR=".build/release"

SIGN_IDENTITY="-"   # default: ad-hoc sign (any Mac can launch, but Gatekeeper warns)
MAKE_DMG=0

while [ $# -gt 0 ]; do
    case "$1" in
        --dmg)
            MAKE_DMG=1
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

echo "==> Building release binary..."
swift build -c release

echo "==> Assembling ${APP_DIR}..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Executable.
cp "$BUILD_DIR/$EXECUTABLE" "$APP_DIR/Contents/MacOS/$EXECUTABLE"

# On-disk Info.plist (macOS reads this for .app bundles; the linker-embedded copy
# in the binary is only used when running the executable directly).
cp Info.plist "$APP_DIR/Contents/Info.plist"

# SwiftPM resource bundle (contains StatusBarIcon.png and anything else declared
# under Sources/Resources/). Lives next to the executable in dev; for a .app
# bundle it must be inside Contents/Resources/ for Bundle.module to find it.
readonly RESOURCE_BUNDLE="${EXECUTABLE}_${EXECUTABLE}.bundle"
if [ -d "$BUILD_DIR/$RESOURCE_BUNDLE" ]; then
    cp -R "$BUILD_DIR/$RESOURCE_BUNDLE" "$APP_DIR/Contents/Resources/$RESOURCE_BUNDLE"
fi

# Optional AppIcon.icns at this directory's parent — drop a file there to set
# the Finder/dock icon. The menubar (status bar) icon is loaded separately
# from the SwiftPM resource bundle.
if [ -f "../AppIcon.icns" ]; then
    cp ../AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
    # Tell Info.plist which icon to use. Done via PlistBuddy so we don't ship a
    # different Info.plist depending on icon presence.
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" \
        "$APP_DIR/Contents/Info.plist" 2>/dev/null || true
fi

echo "==> Code-signing with: $SIGN_IDENTITY"
codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$APP_DIR"

echo "==> Done: $APP_DIR"
codesign -dv --verbose=2 "$APP_DIR" 2>&1 | head -5

if [ "$MAKE_DMG" -eq 1 ]; then
    readonly DMG="../${APP_NAME}.dmg"
    echo "==> Creating DMG: $DMG"
    rm -f "$DMG"
    hdiutil create -volname "$APP_NAME" \
        -srcfolder "$APP_DIR" \
        -ov -format UDZO \
        "$DMG" >/dev/null
    echo "==> DMG ready: $DMG"
fi

cat <<EOF

Next steps:
  - Drag to /Applications to install locally.
  - To share with others, see macos/PACKAGING.md for code signing,
    notarization, and Gatekeeper considerations.
EOF
