# Changelog

All notable changes to the macOS client are recorded here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The canonical machine-readable copy of this file is
`backend/internal/handler/mac_release.json` — keep the two in sync when you
ship a release. The web `/download/mac` page reads from the JSON.

## [Unreleased]

### Added

- Downloaded list now shows a **Redownload** action on rows whose local
  file is missing — typically wallpapers paid for on another device, or
  files deleted out from under the app. Visible alongside Set Wallpaper
  in the hover stack.
- An **Active** chip surfaces on whichever Downloaded wallpaper is
  currently applied to the desktop, regardless of whether it was set
  manually, via Set & download, or by the auto-shuffle rotation. The
  chip persists across relaunches.
- A live **shuffle status banner** appears under the Downloaded heading
  whenever auto-shuffle is on, with a countdown to the next rotation
  tick that refreshes once a minute.

### Changed

- **Popover redesign** to match the new editorial "Archive" aesthetic
  used on the web — paper-tinted frosted-glass backdrop, 720 × 700 px
  surface, hairline-divided 2-column body. Latest and Downloaded sit
  side-by-side, each with its own filter pills (Dynamic / Shuffle).
- Wallpaper rows became 16:10 **tiles** with hover-revealed pill
  actions over a bottom-up gradient. Top-left chips show resolution
  and Mac dynamic; top-right shows Active or Local missing state.
- Header is now an editorial cluster: 36 px avatar + nickname + mono
  handle, an accent-orange coin pill in the center, and a circular
  logout button on the right.
- Footer carries Quit · Open in browser links and a mono version label.

## [1.1.1] - 2026-05-16

### Fixed

- App now ships as a **universal binary** (arm64 + x86_64). Previous
  builds were arm64-only and silently failed to launch on Intel Macs.
- Bundle now carries an **app icon** in Finder / Launchpad / the DMG
  window. Prior releases fell back to the generic macOS app icon
  because no `AppIcon.icns` was included.

## [1.1.0] - 2026-05-14

### Added

- Auto-rotate desktop wallpaper from the local downloads list every 4 hours.
  Persists across app launches. Toggle from the Downloaded column header.
- One-tap **Download & Set as Wallpaper** action on discover-feed rows.
- Download progress bar with percentage for large dynamic HEIC files,
  driven by KVO on the underlying URLSessionDownloadTask.
- Per-column **macOS dynamic only** filter — independent toggles on the
  Latest and Downloaded columns.
- Resolution-aware Downloaded list — only shows wallpapers that have a
  variant matching the current screen's physical pixel dimensions.
- Brand logo as the menubar status item (bundled via SwiftPM resources).

### Changed

- Wallpaper row layout aligns with the web: resolution + dynamic chips
  pinned top-left (always visible), action buttons stacked bottom-right
  (hover reveal).
- Progressive image loading — blurred 400px thumb shows immediately,
  then the 1600px preview fades in. Loading the preview at the same
  size the detail page uses means navigating into a wallpaper feels
  instant (HTTP + in-memory cache hit).
- Auth token storage moved from Keychain to UserDefaults — removes the
  "allow Keychain access" prompt on every launch of an ad-hoc-signed
  build.
- **Set Wallpaper** in the Downloaded column now auto-downloads the
  file when it isn't on this Mac yet (e.g. you downloaded via web
  earlier). The backend's `HasDownloaded` check skips the coin charge
  for already-paid wallpapers, so this is free.

### Fixed

- User info (avatar, nickname, coin balance) didn't populate after a
  fresh sign-in — refreshProfile now calls `/users/me` and assigns the
  full user payload unconditionally.
- Sign-in flashed open and closed without the menubar updating when
  the stored web token was expired — the LoginPage now pre-validates
  before handing the token to the desktop client.
- Hover button stack disappeared as the cursor approached on macOS.
  Fixed by always-mounting the stack (toggling via opacity +
  hit-testing) and pinning the row's hover hit-test region with
  `.contentShape(Rectangle())`.
- Downloaded list kept stale data after Sign Out — added an
  `.onChange(of: auth.isLoggedIn)` reload.
- "Untitled" placeholder text dropped from rows (the upload flow
  removed the title field a while back).

## [1.0.0] - 2026-05-12

### Added

- Menubar status bar app for browsing the Wallpaper Exchange feed.
- Single-sign-on against the web session via `wallxch://` URL scheme.
- Per-row hover actions: **Download** and **Download & Set as Wallpaper**
  on the discover list, **Set Wallpaper** on the local downloads list.
- In-row progress indicator while a download is in flight.
- "Open Web" shortcut in the footer for jumping back to the full site.
- Brand logo as the menubar status item icon (matches the web favicon).
