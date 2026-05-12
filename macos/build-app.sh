#!/usr/bin/env bash
# Package the SwiftPM executable into a redistributable .app (and optionally .dmg),
# and optionally upload the .dmg to MinIO so the web /download/mac page can link to it.
#
# Usage:
#   ./build-app.sh                # builds Wallpaper Exchange.app, ad-hoc signed
#   ./build-app.sh --dmg          # additionally wraps the .app in a .dmg
#   ./build-app.sh --release      # implies --dmg, also uploads to MinIO
#   ./build-app.sh --sign "Developer ID Application: Your Name (TEAMID)"
#                                 # signs with a real Developer ID cert
#
# `--release` requires `mc` (MinIO Client; `brew install minio/stable/mc`) and
# these env vars (sourced from ../.env if present):
#   MINIO_ROOT_USER       MinIO access key
#   MINIO_ROOT_PASSWORD   MinIO secret key
#   SITE_DOMAIN           e.g. wallpaper.haibing.site (endpoint = https://${SITE_DOMAIN}/storage)
#   MINIO_BUCKET          optional, defaults to "wallpapers"
#
# Output:
#   ./Wallpaper Exchange.app/      .app bundle, ready to run / drag to /Applications
#   ./Wallpaper Exchange.dmg       (if --dmg or --release)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/WallpaperExchange"

readonly APP_NAME="Wallpaper Exchange"
readonly EXECUTABLE="WallpaperExchange"
readonly APP_DIR="../${APP_NAME}.app"
readonly BUILD_DIR=".build/release"
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

echo "==> Building release binary..."
swift build -c release

echo "==> Assembling ${APP_DIR}..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BUILD_DIR/$EXECUTABLE" "$APP_DIR/Contents/MacOS/$EXECUTABLE"
cp "$INFO_PLIST" "$APP_DIR/Contents/Info.plist"

readonly RESOURCE_BUNDLE="${EXECUTABLE}_${EXECUTABLE}.bundle"
if [ -d "$BUILD_DIR/$RESOURCE_BUNDLE" ]; then
    cp -R "$BUILD_DIR/$RESOURCE_BUNDLE" "$APP_DIR/Contents/Resources/$RESOURCE_BUNDLE"
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
    hdiutil create -volname "$APP_NAME" \
        -srcfolder "$APP_DIR" \
        -ov -format UDZO \
        "$DMG_PATH" >/dev/null
    echo "==> DMG ready: $DMG_PATH"
fi

if [ "$DO_UPLOAD" -eq 1 ]; then
    # Pull credentials from ../.env if it exists (same file docker-compose uses).
    # Allow already-set env vars to win.
    if [ -f "$SCRIPT_DIR/../.env" ]; then
        # shellcheck disable=SC1091
        set -a; source "$SCRIPT_DIR/../.env"; set +a
    fi

    : "${MINIO_ROOT_USER:?MINIO_ROOT_USER must be set (in ../.env or shell env)}"
    : "${MINIO_ROOT_PASSWORD:?MINIO_ROOT_PASSWORD must be set (in ../.env or shell env)}"
    : "${SITE_DOMAIN:?SITE_DOMAIN must be set (e.g. wallpaper.haibing.site)}"
    BUCKET="${MINIO_BUCKET:-wallpapers}"
    ENDPOINT="https://${SITE_DOMAIN}/storage"

    if ! command -v mc >/dev/null 2>&1; then
        echo "==> ERROR: mc (MinIO Client) not installed." >&2
        echo "           Install: brew install minio/stable/mc" >&2
        exit 1
    fi

    # Pull version from Info.plist so the uploaded filename always matches what
    # the running app reports. Single source of truth.
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")
    if [ -z "$VERSION" ]; then
        echo "==> ERROR: couldn't read CFBundleShortVersionString from Info.plist" >&2
        exit 1
    fi

    ALIAS="wallpaper-release"
    OBJECT_KEY="releases/mac/WallpaperExchange-${VERSION}.dmg"
    REMOTE_URL="${ENDPOINT}/${BUCKET}/${OBJECT_KEY}"

    echo "==> Configuring mc alias $ALIAS -> $ENDPOINT"
    mc alias set "$ALIAS" "$ENDPOINT" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" --api S3v4 >/dev/null

    echo "==> Uploading $DMG_PATH to ${ALIAS}/${BUCKET}/${OBJECT_KEY}"
    mc cp "$DMG_PATH" "${ALIAS}/${BUCKET}/${OBJECT_KEY}"

    echo "==> Verifying public URL..."
    if curl -fsSI -o /dev/null "$REMOTE_URL"; then
        echo "    OK: $REMOTE_URL"
    else
        echo "    WARNING: HEAD request to $REMOTE_URL failed."
        echo "    File was uploaded but may not be publicly reachable yet — check Caddy / bucket policy."
    fi

    cat <<HINT

==> Release uploaded. To make it visible on /download/mac:

  1. Edit backend/internal/handler/mac_release.json
     - bump current_version to: $VERSION
     - set current_dmg_url to: $REMOTE_URL
     - prepend a new entry to "releases" with this version + notes
  2. Mirror the same notes into macos/CHANGELOG.md (Keep a Changelog format).
  3. git commit -am "release(mac): v$VERSION" && git push
     The deploy.yml workflow rebuilds the api container with the new manifest.
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
