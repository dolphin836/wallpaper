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
# `--release` uploads via SSH to the deploy host (the public MinIO endpoint
# is path-prefixed behind Caddy, so direct mc/AWS-CLI uploads from your Mac
# don't work). Required env vars:
#   SSH_HOST              deploy host, e.g. root@1.2.3.4 (or ~/.ssh/config alias)
#   SITE_DOMAIN           public domain for HEAD check, e.g. wallpaper.haibing.site
# Optional (with defaults):
#   SSH_DEPLOY_PATH       compose project dir on server (default /opt/app/wallpaper)
#   DOCKER_NETWORK        wallpaper docker network (default wallpaper_default)
#   MINIO_BUCKET          bucket name (default "wallpapers")
# MINIO_ROOT_USER/PASSWORD are read from the deploy host's .env, not yours.
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
    if [ -f "$SCRIPT_DIR/../.env" ]; then
        # shellcheck disable=SC1091
        set -a; source "$SCRIPT_DIR/../.env"; set +a
    fi

    # Need SSH access to the deploy host because the public MinIO endpoint is
    # served behind a path-prefix Caddy proxy (`/storage`). mc rejects path
    # components in its alias URL, and AWS CLI's SigV4 signature breaks when
    # Caddy strips the prefix before forwarding. The reliable path is to
    # ssh in and run mc inside the minio container where the API is plain
    # http://localhost:9000.
    : "${SSH_HOST:=root@139.224.49.94}"
    : "${SITE_DOMAIN:=wallpaper.haibing.site}"
    SSH_DEPLOY_PATH="${SSH_DEPLOY_PATH:-/opt/app/wallpaper}"
    DOCKER_NETWORK="${DOCKER_NETWORK:-wallpaper_default}"
    BUCKET="${MINIO_BUCKET:-wallpapers}"

    # Pull version from Info.plist so the uploaded filename always matches what
    # the running app reports. Single source of truth.
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")
    if [ -z "$VERSION" ]; then
        echo "==> ERROR: couldn't read CFBundleShortVersionString from Info.plist" >&2
        exit 1
    fi

    OBJECT_KEY="releases/mac/WallpaperExchange-${VERSION}.dmg"
    REMOTE_TMP="/tmp/wpe-release-${VERSION}.dmg"
    REMOTE_URL="https://${SITE_DOMAIN}/storage/${BUCKET}/${OBJECT_KEY}"

    echo "==> SCP $DMG_PATH → ${SSH_HOST}:${REMOTE_TMP}"
    scp "$DMG_PATH" "${SSH_HOST}:${REMOTE_TMP}"

    echo "==> Uploading into MinIO via minio/mc sidecar on $DOCKER_NETWORK"
    # We don't `docker compose exec` the minio container because newer
    # minio/minio images no longer ship the mc binary. Instead spin up a
    # one-shot minio/mc on the same docker network, mounting the DMG so
    # we don't need a second host→container copy.
    ssh "$SSH_HOST" \
        "DEPLOY_PATH='$SSH_DEPLOY_PATH' REMOTE_TMP='$REMOTE_TMP' BUCKET='$BUCKET' OBJECT_KEY='$OBJECT_KEY' NETWORK='$DOCKER_NETWORK' bash -s" <<'REMOTE_EOF'
set -e
cd "$DEPLOY_PATH"
# shellcheck disable=SC1091
set -a; source .env; set +a
docker run --rm \
    --network "$NETWORK" \
    -v "$REMOTE_TMP:/upload.dmg:ro" \
    -e MC_USER="$MINIO_ROOT_USER" \
    -e MC_PASS="$MINIO_ROOT_PASSWORD" \
    -e BUCKET="$BUCKET" \
    -e OBJECT_KEY="$OBJECT_KEY" \
    --entrypoint sh \
    minio/mc -c '
        mc alias set local http://minio:9000 "$MC_USER" "$MC_PASS" >/dev/null
        mc cp /upload.dmg "local/$BUCKET/$OBJECT_KEY"
    '
rm -f "$REMOTE_TMP"
REMOTE_EOF

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
