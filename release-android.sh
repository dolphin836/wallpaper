#!/usr/bin/env bash
# One-click Android release: build an installable APK and copy it into the
# frontend static directory, ready for the website download page.
#
# Usage:
#   ./release-android.sh
#
# The script reads versionName/versionCode from android/app/build.gradle.kts,
# builds the app, publishes:
#   frontend/public/downloads/android/WallpaperExchange-<version>.apk
# and updates:
#   backend/internal/handler/android_release.json
#
# Until Play signing or a dedicated release keystore is added, this uses the
# debug-signed APK so it can be installed directly from the website.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
ANDROID_DIR="$REPO_ROOT/android"
BUILD_FILE="$ANDROID_DIR/app/build.gradle.kts"
MANIFEST_FILE="$REPO_ROOT/backend/internal/handler/android_release.json"
STATIC_DIR="$REPO_ROOT/frontend/public/downloads/android"

if [ ! -f "$BUILD_FILE" ]; then
    echo "==> ERROR: Android build file not found: $BUILD_FILE" >&2
    exit 1
fi

if [ ! -f "$MANIFEST_FILE" ]; then
    echo "==> ERROR: Android release manifest not found: $MANIFEST_FILE" >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "==> ERROR: jq is required to update $MANIFEST_FILE" >&2
    exit 1
fi

VERSION="$(awk -F'"' '/versionName[[:space:]]*=/ { print $2; exit }' "$BUILD_FILE")"
VERSION_CODE="$(awk -F'=' '/versionCode[[:space:]]*=/ { gsub(/[^0-9]/, "", $2); print $2; exit }' "$BUILD_FILE")"

if [ -z "$VERSION" ] || [ -z "$VERSION_CODE" ]; then
    echo "==> ERROR: couldn't read versionName/versionCode from $BUILD_FILE" >&2
    exit 1
fi

cd "$ANDROID_DIR"
if [ -x "./gradlew" ]; then
    GRADLE="./gradlew"
elif command -v gradle >/dev/null 2>&1; then
    GRADLE="gradle"
else
    echo "==> ERROR: Gradle not found. Install Gradle or restore android/gradlew." >&2
    exit 1
fi

echo "==> Building Android APK v$VERSION ($VERSION_CODE)..."
"$GRADLE" :app:assembleDebug

APK_SOURCE="$ANDROID_DIR/app/build/outputs/apk/debug/app-debug.apk"
if [ ! -f "$APK_SOURCE" ]; then
    echo "==> ERROR: APK not found after build: $APK_SOURCE" >&2
    exit 1
fi

STATIC_NAME="WallpaperExchange-${VERSION}.apk"
STATIC_PATH="$STATIC_DIR/$STATIC_NAME"
RELATIVE_URL="/downloads/android/$STATIC_NAME"

mkdir -p "$STATIC_DIR"
cp "$APK_SOURCE" "$STATIC_PATH"

SHA256="$(shasum -a 256 "$STATIC_PATH" | awk '{ print $1 }')"
RELEASED_AT="${RELEASED_AT:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}"

TMP_MANIFEST="$(mktemp)"
jq \
    --arg version "$VERSION" \
    --argjson versionCode "$VERSION_CODE" \
    --arg url "$RELATIVE_URL" \
    --arg sha "$SHA256" \
    --arg releasedAt "$RELEASED_AT" \
    '.current_version = $version
     | .current_version_code = $versionCode
     | .current_apk_url = $url
     | .apk_sha256 = $sha
     | .released_at = $releasedAt' \
    "$MANIFEST_FILE" > "$TMP_MANIFEST"
mv "$TMP_MANIFEST" "$MANIFEST_FILE"

echo "==> Release copied to frontend static asset: $STATIC_PATH"
echo "    URL: $RELATIVE_URL"
echo "    SHA-256: $SHA256"

# Keep only the current APK in the repo, matching the macOS release asset flow.
for old in "$STATIC_DIR"/WallpaperExchange-*.apk; do
    [ -e "$old" ] || continue
    [ "$(basename "$old")" = "$STATIC_NAME" ] && continue
    echo "==> Removing superseded APK: $(basename "$old")"
    git -C "$REPO_ROOT" rm -q --ignore-unmatch \
        "frontend/public/downloads/android/$(basename "$old")" || true
    rm -f "$old"
done

cat <<HINT

==> Android release packaged.

Next steps:
  1. Review backend/internal/handler/android_release.json notes for this release.
  2. Commit the manifest and $STATIC_PATH.
  3. Deploy frontend + backend so the APK and /api/v1/android/release are live.
HINT
