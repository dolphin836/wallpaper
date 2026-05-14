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
    : "${SSH_HOST:?SSH_HOST must be set — your deploy host. Example: SSH_HOST=root@your-server (or a host alias from ~/.ssh/config)}"
    : "${SITE_DOMAIN:?SITE_DOMAIN must be set (e.g. wallpaper.haibing.site)}"
    SSH_DEPLOY_PATH="${SSH_DEPLOY_PATH:-/opt/wallpaper}"
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

    echo "==> Uploading into MinIO via mc inside the minio container"
    # Wrap in single-quoted heredoc so $VAR references stay literal until the
    # remote shell expands them — but pre-substitute the values we already know
    # locally via SSH env vars before the bash call.
    ssh "$SSH_HOST" \
        "DEPLOY_PATH='$SSH_DEPLOY_PATH' REMOTE_TMP='$REMOTE_TMP' BUCKET='$BUCKET' OBJECT_KEY='$OBJECT_KEY' bash -s" <<'REMOTE_EOF'
set -e
cd "$DEPLOY_PATH"
# shellcheck disable=SC1091
set -a; source .env; set +a
docker compose cp "$REMOTE_TMP" minio:/tmp/wpe-release.dmg
docker compose exec -T \
    -e MC_USER="$MINIO_ROOT_USER" \
    -e MC_PASS="$MINIO_ROOT_PASSWORD" \
    -e BUCKET="$BUCKET" \
    -e OBJECT_KEY="$OBJECT_KEY" \
    minio sh -c '
        mc alias set local http://localhost:9000 "$MC_USER" "$MC_PASS" >/dev/null
        mc cp /tmp/wpe-release.dmg "local/$BUCKET/$OBJECT_KEY"
        rm -f /tmp/wpe-release.dmg
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
