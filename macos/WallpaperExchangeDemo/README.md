# Mac Client Redesign — Preview

Standalone SwiftPM app used to evaluate the redesigned macOS surface
without touching the production WallpaperExchange package.

## Run

```bash
cd macos/WallpaperExchangeDemo
swift run
```

A main window opens at 1280 × 820 with sample data baked in. The
preview tiles fetch from `picsum.photos` so the layout is reviewable
offline of our own API.

## What's in scope

- **Sidebar** — Discover / Weekly / For Your Device / Categories /
  Downloads / Collections / Liked / Uploaded · footer profile cell +
  coin pill + settings shortcut
- **Discover grid** — editorial header (kicker + serif headline +
  intro), filter pills, adaptive 16:9 tiles with palette strip + hover
  Quick-Set / Save chips + resolution chip
- **Detail inspector** — slides in from the right when a tile is
  clicked. Blurred wallpaper backdrop, big hero, Plain / Home / Lock
  preview toggle, specs strip, palette grid, dark Coin CTA, multi-
  display quick actions, mini "More like this" grid
- **Search / shuffle / coin pill / profile** — wired into the unified
  toolbar at the top
- **Settings** — opens from ⌘, , preview only

## Out of scope (intentionally)

- Real API plumbing (no auth, no downloads, no coin spend)
- Menu-bar popover — the redesigned popover is part of the production
  package once direction is locked
- Multi-monitor wallpaper actually being applied — the chip ships
  click handlers but no `NSWorkspace.setDesktopImageURL` call
- Sign-in / register flows — assume signed-in

## Picking a direction

The demo represents Direction **A** (Sidebar split) from the proposal.
If we'd prefer Direction B (Toolbar tabs) or C (Editorial single
window) it's cheap to rebuild this scaffold — the theme tokens and
sample-data layer in `Sources/Theme.swift` + `Sources/SampleData.swift`
stay put.

Once a direction is approved, the next step is porting the structure
into the production package (`macos/WallpaperExchange/`) and wiring
the real `APIClient` / `WallpaperManager` calls.
