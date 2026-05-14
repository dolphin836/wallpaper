#!/usr/bin/env bash
# One-click macOS release: build .app + .dmg, upload to MinIO, ready for
# /download/mac.
#
# This is a thin wrapper around macos/build-app.sh so the release flow lives
# at the same level as deploy.sh. After bumping the version + CHANGELOG +
# mac_release.json and committing, run:
#
#   ./release-mac.sh
#
# Then `./deploy.sh` (or just `./deploy.sh backend`) to make the new manifest
# visible on the web /download/mac page.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/macos/build-app.sh" --release "$@"
