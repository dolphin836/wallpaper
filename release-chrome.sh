#!/usr/bin/env bash
# One-click Chrome extension release: package the installable extension zip and
# copy the same artifact into the frontend static directory for website
# download / Chrome Web Store upload.
#
# Usage:
#   ./release-chrome.sh
#
# The script reads the extension version from chrome-extension/manifest.json,
# creates:
#   chrome-extension/WallpaperExchangeChrome-<version>.zip
#   frontend/public/downloads/chrome/WallpaperExchangeChrome-<version>.zip
# and updates:
#   frontend/public/downloads/chrome/chrome_release.json
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
EXTENSION_DIR="$REPO_ROOT/chrome-extension"
STATIC_DIR="$REPO_ROOT/frontend/public/downloads/chrome"
MANIFEST_FILE="$EXTENSION_DIR/manifest.json"

if ! command -v node >/dev/null 2>&1; then
    echo "==> ERROR: node is required to read/write release metadata." >&2
    exit 1
fi

if ! command -v zip >/dev/null 2>&1; then
    echo "==> ERROR: zip is required to package the Chrome extension." >&2
    exit 1
fi

if [ ! -f "$MANIFEST_FILE" ]; then
    echo "==> ERROR: Chrome extension manifest not found: $MANIFEST_FILE" >&2
    exit 1
fi

VERSION="$(node -e "const fs=require('fs'); const m=JSON.parse(fs.readFileSync(process.argv[1], 'utf8')); process.stdout.write(m.version || '');" "$MANIFEST_FILE")"
if [ -z "$VERSION" ]; then
    echo "==> ERROR: couldn't read version from $MANIFEST_FILE" >&2
    exit 1
fi

for required in \
    "$EXTENSION_DIR/manifest.json" \
    "$EXTENSION_DIR/newtab.html" \
    "$EXTENSION_DIR/newtab.css" \
    "$EXTENSION_DIR/newtab.js" \
    "$EXTENSION_DIR/README.md" \
    "$EXTENSION_DIR/icons/icon-16.png" \
    "$EXTENSION_DIR/icons/icon-32.png" \
    "$EXTENSION_DIR/icons/icon-48.png" \
    "$EXTENSION_DIR/icons/icon-128.png"; do
    if [ ! -f "$required" ]; then
        echo "==> ERROR: required extension file missing: $required" >&2
        exit 1
    fi
done

PACKAGE_NAME="WallpaperExchangeChrome-${VERSION}.zip"
LOCAL_PACKAGE="$EXTENSION_DIR/$PACKAGE_NAME"
STATIC_PACKAGE="$STATIC_DIR/$PACKAGE_NAME"
RELATIVE_URL="/downloads/chrome/$PACKAGE_NAME"
RELEASED_AT="${RELEASED_AT:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}"

rm -f "$LOCAL_PACKAGE"
mkdir -p "$STATIC_DIR"

echo "==> Packaging Chrome extension v$VERSION..."
(
    cd "$EXTENSION_DIR"
    zip -qr "$LOCAL_PACKAGE" \
        manifest.json \
        newtab.html \
        newtab.css \
        newtab.js \
        README.md \
        icons \
        -x "*.DS_Store" "__MACOSX/*" "*.zip"
)

cp "$LOCAL_PACKAGE" "$STATIC_PACKAGE"
SHA256="$(shasum -a 256 "$STATIC_PACKAGE" | awk '{ print $1 }')"

node - "$VERSION" "$RELATIVE_URL" "$SHA256" "$RELEASED_AT" "$STATIC_DIR/chrome_release.json" <<'NODE'
const fs = require('fs');

const [version, url, sha256, releasedAt, outPath] = process.argv.slice(2);
const payload = {
  current_version: version,
  current_zip_url: url,
  zip_sha256: sha256,
  released_at: releasedAt,
};

fs.writeFileSync(outPath, `${JSON.stringify(payload, null, 2)}\n`);
NODE

for old in "$STATIC_DIR"/WallpaperExchangeChrome-*.zip; do
    [ -e "$old" ] || continue
    [ "$(basename "$old")" = "$PACKAGE_NAME" ] && continue
    echo "==> Removing superseded Chrome package: $(basename "$old")"
    git -C "$REPO_ROOT" rm -q --ignore-unmatch \
        "frontend/public/downloads/chrome/$(basename "$old")" || true
    rm -f "$old"
done

cat <<HINT

==> Chrome extension release packaged.

Local upload package:
  $LOCAL_PACKAGE

Website static package:
  $STATIC_PACKAGE
  URL: $RELATIVE_URL
  SHA-256: $SHA256

Next steps:
  1. Upload the local package to Chrome Web Store when publishing.
  2. Deploy frontend so the website download is live.
HINT
