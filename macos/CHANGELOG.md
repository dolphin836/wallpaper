# Changelog

All notable changes to the macOS client are recorded here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The canonical machine-readable copy of this file is
`backend/internal/handler/mac_release.json` — keep the two in sync when you
ship a release. The web `/download/mac` page reads from the JSON.

## [Unreleased]

## [1.0.0] - 2026-05-12

### Added

- Menubar status bar app for browsing the Wallpaper Exchange feed.
- Single-sign-on against the web session via `wallxch://` URL scheme.
- Per-row hover actions: **Download** and **Download & Set as Wallpaper**
  on the discover list, **Set Wallpaper** on the local downloads list.
- In-row progress indicator while a download is in flight.
- "Open Web" shortcut in the footer for jumping back to the full site.
- Brand logo as the menubar status item icon (matches the web favicon).
