# Changelog

All notable changes to the macOS client are recorded here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The canonical machine-readable copy of this file is
`backend/internal/handler/mac_release.json` — keep the two in sync when you
ship a release. The web `/download/mac` page reads from the JSON.

## [Unreleased]

## [1.3.6] - 2026-05-27

### Fixed

- **Set as wallpaper now works in the Latest column for already-downloaded
  wallpapers.** When a Latest tile was already on disk its action row
  collapsed to a single "Set as wallpaper" button, but that button was
  wired to a no-op, so clicking it did nothing. It now applies the
  wallpaper to the desktop.
- **Video wallpapers no longer appear in the Downloaded column.** The mac
  client can't render video wallpapers, and the Latest list already hid
  them, but downloads are cross-platform so a video pulled on the web or
  Windows still surfaced in Downloaded. It's now filtered out there too.

## [1.3.5] - 2026-05-23

### Fixed

- **Auto-rotate now reaches every display, including ones that were
  asleep at the rotation tick.** Previously, when the 4-hour timer
  fired while a secondary monitor was in display-sleep, that screen
  was missing from `NSScreen.screens` so `setDesktopImageURL` never
  ran for it — when the monitor woke up, macOS restored the previous
  wallpaper from its plist. The manager now listens for
  `didChangeScreenParametersNotification` (display connect / wake /
  mode change) and `NSWorkspace.didWakeNotification` (system wake),
  and re-applies the current wallpaper to every connected screen
  when either fires.

## [1.3.4] - 2026-05-23

### Changed

- **Wallpaper-apply now logs per-screen results.** Both manual Set
  Wallpaper and the 4-hour auto-rotate route through a single helper
  that records each connected display's localized name, frame, and
  setDesktopImageURL outcome to the unified log (subsystem
  `com.wallpaperexchange.mac`, category `wallpaper`). Investigating
  reports of "secondary monitors didn't get the new wallpaper" needs
  the per-screen log; the previous code silently swallowed errors
  with `try?`.

## [1.3.3] - 2026-05-23

### Added

- **AI badge on wallpaper tiles.** AI-generated wallpapers now carry a
  violet "AI" chip in the top-left corner alongside the resolution /
  Mac chips, matching the badge introduced on the web.

## [1.3.2] - 2026-05-20

### Changed

- **Self-update now shows real download progress.** Replaced the static
  "Downloading…" alert with a floating panel that streams real bytes
  + percentage as the .dmg comes in, plus a working Cancel button.
  Also surfaces an "Installing…" stage while the new bundle is being
  moved into place.

### Fixed

- Updater no longer feels frozen on slow networks — the previous build
  ran the download inside a modal alert with no visible feedback, so
  users couldn't tell whether the transfer was making progress.

## [1.3.1] - 2026-05-20

### Added

- **Launch at Login** toggle in the status-bar right-click menu. Uses
  the modern ServiceManagement framework — no LaunchAgent plist files
  to clean up if you change your mind. If you've moved the app
  somewhere transient (e.g. ~/Downloads) the toggle will surface a
  warning explaining why the system refused.

## [1.3.0] - 2026-05-20

### Added

- **Self-update.** The app now checks for new releases on every launch
  and offers a one-click upgrade. A right-click on the status-bar icon
  opens a menu with **Check for Updates…** and **Quit**. When an
  update is found you'll be shown a prompt at most once per discovered
  version — clicking "Later" silences the alert until the next release
  ships.
- When you accept an update, the new build downloads, replaces the
  running app in place, and relaunches automatically. No more dragging
  a .dmg into /Applications by hand to get the latest version.

## [1.2.2] - 2026-05-18

### Fixed

- App failed to launch on any Mac other than the build machine. The
  SwiftPM-generated `Bundle.module` accessor looks for the resource
  bundle at the `.app` root, but `build-app.sh` was copying it into
  `Contents/Resources/` instead — so every fresh install fell through
  to the hard-coded compile-time absolute path and trapped on startup
  with "could not load resource bundle". The 1.2.1 build is effectively
  broken on all non-developer machines; users should re-download.
- `build-app.sh` now hard-fails if the resource bundle isn't where it
  expects, instead of silently shipping an unrunnable .app.

## [1.2.1] - 2026-05-18

### Changed

- Installer DMG now opens as a standard drag-to-install window —
  the app icon on the left, an Applications shortcut on the right.
  Previous builds shipped a bare DMG that just listed the .app and
  expected the user to know they had to move it into /Applications
  themselves.

## [1.2.0] - 2026-05-17

### Added

- **Editorial Archive redesign** of the popover — paper-tinted
  frosted-glass backdrop, 720 × 700 px surface, hairline-divided
  two-column body. Latest and Downloaded sit side-by-side, each
  with its own filter pills.
- **Redownload** action on Downloaded rows whose local file is
  missing — typically wallpapers paid for on another device, or
  files deleted out from under the app.
- **Active** chip on whichever Downloaded wallpaper is currently
  applied to the desktop, regardless of whether it was set manually,
  via Set & download, or by the auto-shuffle rotation. Persists
  across relaunches.
- Live **shuffle status banner** under the Downloaded heading
  whenever auto-shuffle is on, with a countdown to the next
  rotation tick.
- **Reveal in Finder** button next to the Dynamic filter — opens
  the local downloads folder.
- **Infinite scroll** on both columns — the next page is prefetched
  when you've scrolled within three tiles of the end, with a "Load
  more" fallback and an "End" marker when the list is exhausted.
- **Local disk usage** indicator in the footer next to the version
  number — auto-updates after each download or delete.
- Hover affordance on the filter toggles — icons darken on hover
  and surface a system tooltip describing each action.

### Changed

- Wallpaper rows became **16:10 tiles** with hover-revealed pill
  actions over a bottom-up gradient. Top-left chips show resolution
  and Mac dynamic; top-right shows Active or Local missing state.
- Latest tiles whose file is already on this Mac collapse to a
  single Set as wallpaper button — the Download / Set & download
  pair was misleading when the file was already local.
- Header is now an editorial cluster: 36 px avatar + nickname +
  mono handle, an accent-orange coin pill in the center, and a
  circular logout button on the right.
- Filter toggles are icon-only 24 px circular buttons. The
  human-readable label moved to a hover tooltip.

### Fixed

- Latest list returns the full wallpaper catalogue. Previous builds
  silently filtered by device resolution and excluded wallpapers
  without a variant matching the user's screen.
- Downloaded list shows wallpapers immediately after a successful
  download. Same device-resolution filter was hiding new entries
  whose resolution didn't match this Mac.

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
