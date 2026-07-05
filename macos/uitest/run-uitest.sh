#!/bin/bash
# Wallpaper Exchange macOS UI smoke test runner.
#
# Builds the app + the AX-based test driver, then walks the real UI
# like a human would (launch, nav tabs, collection detail, back button,
# wallpaper detail, ESC). Screenshots land in macos/uitest/artifacts/.
#
# The process running this script needs:
#   • Accessibility permission  (required — driving the UI)
#   • Screen Recording          (optional — step screenshots)
# Grant both to your terminal app in System Settings → Privacy & Security.
#
# Usage: ./run-uitest.sh [--skip-build]
set -euo pipefail
cd "$(dirname "$0")/.."   # → macos/

if [[ "${1:-}" != "--skip-build" ]]; then
  echo "── building app (debug)…"
  (cd WallpaperExchange && swift build)
fi

echo "── building test driver…"
mkdir -p uitest/artifacts
swiftc -O uitest/UITestRunner.swift -o uitest/artifacts/uitest-runner

echo "── running UI smoke test…"
rm -f uitest/artifacts/*.png
pkill -f 'WallpaperExchange/.build/debug/WallpaperExchange' 2>/dev/null || true
sleep 1
uitest/artifacts/uitest-runner "WallpaperExchange/.build/debug/WallpaperExchange" "uitest/artifacts"
STATUS=$?

echo "── artifacts: $(ls uitest/artifacts/*.png 2>/dev/null | wc -l | tr -d ' ') screenshots in macos/uitest/artifacts/"
exit $STATUS
