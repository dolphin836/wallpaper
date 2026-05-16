# Handoff: macOS menu-bar app redesign

> A redesign of the **Wallpaper Exchange** macOS menu-bar app to match the new editorial "Archive" aesthetic used on the web. The app stays a single dropdown popover — no main window — and everything (browse latest · download · set as wallpaper · manage local downloads · auto-shuffle) happens in that one surface.

## About these files

The files in `prototype/` are **design references** — JSX + CSS prototypes showing intended look, layout, and interaction. They are NOT meant to be copy-pasted into production. Your job is to recreate this design inside the existing macOS app codebase at `macos/WallpaperExchange/`, which is a SwiftPM SwiftUI project targeting macOS 14+.

Open `prototype/The Archive.html` in a browser to see the live design canvas; the relevant artboards are in the **"09 · macOS menu-bar app"** section.

## Fidelity

**High-fidelity.** Pixel-perfect intent. All colors, type, spacing, hover behaviors, and button compositions are final. Lift exact values from the tokens section in the main README (Part 1) and from the **macOS specifics** below.

---

## Goals

1. **Don't interrupt.** Everything is a dropdown popover hanging from the menu-bar icon. No modals, no separate windows, no full-screen takeovers. Click the W icon → see the latest + your downloads → act → click out.
2. **Match the web language.** Paper + ink + the single accent orange reserved for value/action moments. Instrument Serif for headings, JetBrains Mono for numbers + metadata, Geist Sans for body. The popover should feel like a piece of the web archive that broke off and floats next to the menu bar.
3. **Two parallel surfaces in one view.** Latest (browse new specimens) and Downloaded (manage what you have) sit side-by-side, separated by a hairline, with the same vocabulary on each tile but different actions.

---

## What's changing

| Surface | Current | New |
|---|---|---|
| Popover chrome | Default `NSPopover` with system rounded rect | Frosted-glass paper background, hairline 1px ink-tinted border, soft outer shadow + inner highlight |
| Header | (Existing user info) | 36px avatar + display nickname + mono handle on the left; ink-pill coin chip in the middle; circular logout button on the right |
| Browse / wallpaper grid | Single column | **Two columns**: Latest (left) and Downloaded (right), hairline vertical divider |
| Tile chrome | (Existing) | Always-on top-left tags `4K` + `Mac` (for dynamic wallpapers); hover reveals action buttons over a bottom-up dark gradient |
| Set wallpaper / download actions | (Existing buttons inside a list row) | Hover-revealed pill buttons on top of the tile: paper-glass secondary + accent-orange primary |
| Filters | (None / system menu) | Per-column inline toggle pills above each list: `🍎 Dynamic` on both; **Shuffle** additionally on Downloaded |
| Auto-shuffle | New feature | When enabled on Downloaded, surface a status banner under the column header with "Auto-shuffle is on. Pulling from your downloads every 4 hours. Next · 2 h 34 m" |
| File-missing handling | New | Detect when a downloaded wallpaper's local file is no longer on disk; render a `[Re-download]` button next to `[Set as wallpaper]` and a `Local missing` chip on the tile |
| Currently-applied wallpaper | New | Show an `Active` chip in accent orange on whichever downloaded wallpaper is currently set as the desktop |

---

## Tile composition

Tiles use the same visual vocabulary on both columns; only the action buttons differ. Tile aspect is **16:10**, corner radius **8 px**, background `var(--color-paper-2)` while the image loads.

### Always-on chips

```
┌─────────────────────────────────────┐
│ [4K] [🍎 Mac]              [Active] │  ← top row
│                                     │
│                                     │
│       (image)                       │
│                                     │
│                                     │
│                                     │
└─────────────────────────────────────┘
```

**Top-left (always):**
- Resolution chip: `4K` / `5K` / `8K`, etc. — mono caps, 9.5 px, `bg-rgba(0,0,0,0.55)` with backdrop blur, white text, 3 px radius.
- `🍎 Mac` chip if the wallpaper is a macOS dynamic wallpaper. Same styling.

**Top-right (state, conditional):**
- `Active` chip — orange `--color-accent` bg, white text, paired with a check glyph. Only on the **currently applied** wallpaper in the Downloaded column.
- `🔒 Local missing` chip — amber-warn `#9a6a18` bg, white text. Only when the local file is missing (e.g. user emptied the trash, app's Downloads folder was cleaned). Implies the `[Re-download]` button is shown.

These two are mutually exclusive: a wallpaper can't be both active and locally missing (if it's active, the file exists).

### Hover actions

When the user mouses over a tile, a bottom-aligned dark gradient fades in (0 → 1 over 220 ms) and an action row slides up from the bottom-right. The buttons sit at `bottom: 10 px; right: 10 px`.

Buttons are pill-shaped `rgba(255,255,255,0.18)` with a 1 px `rgba(255,255,255,0.28)` border, white text, `backdrop-filter: blur(10px)`. Primary buttons use `--color-accent` background, transparent border. Padding `7 × 11 px`, font sans 11 px medium, icon 11 px.

| Column | Buttons (right-to-left, primary closest to corner) |
|---|---|
| Latest | `[⬇ Download]` (secondary, glass) · `[⬇📺 Set & download]` (primary, accent) |
| Downloaded — file present | `[📺 Set as wallpaper]` (primary, accent) |
| Downloaded — file missing | `[🔄 Re-download]` (secondary, glass) · `[📺 Set as wallpaper]` (primary, accent) |

### Image transform on hover

Slow scale 1.035, brightness +4%, 600 ms cubic-bezier(.22, .61, .36, 1). Same easing as the web salon tile but a touch less aggressive — this is a small popover, not a wall.

---

## Popover layout

Total popover width: **720 px**. Height: **700 px** (or `min(700, screenAvailableHeight - 100)` so it never gets clipped at the bottom of small screens).

The popover is a 3-row layout: header (64 px), body (fills), footer (44 px). The body is itself a 2-column grid with a hairline vertical divider.

### Container

```css
.mac-popover {
  background: rgba(245,243,238,0.94);            /* paper at 94% with vibrancy */
  backdrop-filter: blur(28px) saturate(1.4);
  border: 1px solid rgba(0,0,0,0.08);
  border-radius: 14px;
  box-shadow:
    0 1px 0 rgba(255,255,255,0.6) inset,         /* top highlight */
    0 18px 60px rgba(0,0,0,0.22),                /* big drop shadow */
    0 4px 12px rgba(0,0,0,0.06);
  overflow: hidden;
}
```

Above the popover, anchored to the menu-bar icon, sits a small triangle "tail":

```css
.mac-tail {
  position: absolute;
  top: -8px; left: 50%; transform: translateX(-50%) rotate(45deg);
  width: 16px; height: 16px;
  background: rgba(245,243,238,0.94);
  backdrop-filter: blur(28px) saturate(1.4);
  border-top: 1px solid rgba(0,0,0,0.08);
  border-left: 1px solid rgba(0,0,0,0.08);
}
```

In SwiftUI, this is `NSPopover` configured with the default arrow and `behavior = .transient`. Don't roll your own arrow unless you must — the system one is good. The mock shows what it should look like.

### Header

3-column grid `1fr | auto | auto`, gap 14 px, padding `14 × 18 px`.

**Left:** small profile cluster.
- 36 px circle avatar (paper-2 bg, hair border, falls back to first letter in Instrument Serif 18 px).
- Display 17 px nickname (`{user.nickname}`).
- Mono 10 px `@{user.username}` in muted color, letter-spacing 0.06 em.

**Middle:** the coin balance pill — *the only place the accent orange appears in the popover at rest*, signaling the value moment.
- Pill: `bg-ink`, `border-radius: 999px`, padding `5 × 11 × 5 × 5 px` (extra-left for the coin glyph).
- Coin glyph: 18 px circle, accent fill, with a subtle inset shadow (`inset 0 -2px 0 darker-accent, inset 0 1px 0 lighter-accent`) to look like a minted coin.
- Number: mono **semibold** 13 px, paper color, letter-spacing 0.02 em.

**Right:** a quiet sign-out button. 32 px circle, transparent bg, hair border, ink-2 logout icon.

### Body — 2 columns

Each column has the same internal structure (`<MacColumn />`):

```
┌──────────────────────────────────────┐
│ ⚡ Latest                  [🍎 Dynamic]│  ← heading row
│                                      │
│ (optional shuffle banner)            │  ← only on Downloaded
│                                      │
│ ┌──────┐                             │
│ │ tile │                             │  ← list
│ └──────┘                             │
│ ┌──────┐                             │
│ │ tile │                             │
│ └──────┘                             │
│                                      │
└──────────────────────────────────────┘
```

**Heading row** — flex-between, margin-bottom 12 px.
- Left: column icon (14 px, stroke 1.5) + display 18 px title. Latest uses a "bolt" glyph; Downloaded uses the download glyph. Keep these subtle — they're navigational hints, not loud decoration.
- Right: inline toggle pills, gap 6 px.

**Toggle pills (`.mac-toggle`)** are 1 px hair border, paper bg (transparent), mono 10 px muted text with a small icon. Hover ink-2's the border + text. **Active state**: `bg-accent`, white text, no border. Letter-spacing 0.06 em, padding `5 × 8 px`.

Available toggles:
- `🍎 Dynamic` — both columns. Filters to macOS dynamic wallpapers only.
- `🔀 Shuffle 4h` — Downloaded only. When on, the label changes from `Shuffle` to `Shuffle 4h` so the user can see at a glance whether it's enabled.

**Item list** — vertical stack, gap 10 px. In production, this scrolls with `overflow-y: auto`. We don't show an explicit scrollbar — let the system handle it.

### Shuffle status banner

When `shuffle === true` on the Downloaded column, render an `.mac-banner` between the heading and the tile list:

```
┌──────────────────────────────────────────────────────┐
│ [🔀]  Auto-shuffle is on. Pulling from your        │
│       downloads every 4 hours.       NEXT · 2 H 34 M │
└──────────────────────────────────────────────────────┘
```

Styling:
- Container: `bg-accent-soft` (warm cream), 1 px border in `oklch(80% 0.08 60)`, 6 px radius, padding `10 × 12 px`.
- 22 px circle glyph on the left in `bg-accent`, white shuffle icon.
- Sans 12 px body in `var(--color-accent-ink)` (dark warm orange-brown). Bold the first sentence ("Auto-shuffle is on.").
- Right-aligned mono caps 10 px countdown to the next rotation: `NEXT · 2 H 34 M`. The H/M values come from `nextShuffleAt - now`; refresh once a minute.

### Footer

44 px, padding `11 × 18 px`, `border-top: 1px solid var(--color-hair)`, slightly translucent background `rgba(255,255,255,0.45)` to differentiate from the body.

- Left: two text-only buttons in a horizontal flex with gap 16 px:
  - `[⏻ Quit]` — sans 12 px, ink-2, gap 6 px between icon and label.
  - `[↗ Open in browser]` — same styling.
- Right: mono caps 10 px version `v 2.4.0` in muted color.

No primary button in the footer — the popover doesn't need one. Everything actionable lives on the tiles.

---

## Component map for SwiftUI

The prototype is HTML/CSS; the real implementation is SwiftUI. Map:

| Prototype JSX | Suggested SwiftUI |
|---|---|
| `MacPopover` | `PopoverContentView` — already exists in `macos/WallpaperExchange/Sources/App/`. Rewrite its body. |
| `MacHeader` | `PopoverHeaderView` (new) — `HStack` with the avatar/identity, coin pill, logout button. |
| `MacColumn` | `WallpaperColumnView` (new) — generic over a `WallpaperKind` enum that selects which actions to render on hover. |
| `MacTile` | `WallpaperTileView` (new) — `ZStack` with the image, chips, gradient overlay, and action row. |
| Hover actions | SwiftUI lacks "hover" natively in popover children pre macOS 14, but is fine on 14+; use `.onHover { isHover in withAnimation(.easeOut(duration: 0.22)) { ... } }` to drive the gradient + actions opacity. |
| Toggle pill (`.mac-toggle`) | `FilterTogglePill` (new) — `Button` with custom `ButtonStyle`. Use `@Binding var isOn: Bool` so it's a controlled component. |
| Shuffle banner (`.mac-banner`) | `ShuffleStatusBanner` (new) — only present when `shuffleEnabled` is true. Wrap a `Timer.publish(every: 60, ...)` to update the countdown. |
| Footer | `PopoverFooterView` (new) — text buttons + version label. |

Place new views under `macos/WallpaperExchange/Sources/Views/Popover/`.

---

## Tokens for the macOS side

Because the macOS app doesn't share CSS with the web, declare these once in Swift as `Color` and `Font` extensions:

```swift
extension Color {
    static let paper     = Color(red: 0.972, green: 0.964, blue: 0.945) // oklch(97.8% 0.008 80)
    static let paper2    = Color(red: 0.948, green: 0.940, blue: 0.921)
    static let hair      = Color(red: 0.872, green: 0.862, blue: 0.846)
    static let ink       = Color(red: 0.176, green: 0.170, blue: 0.164)
    static let ink2      = Color(red: 0.286, green: 0.278, blue: 0.270)
    static let muted     = Color(red: 0.524, green: 0.516, blue: 0.504)
    static let accent    = Color(red: 0.886, green: 0.491, blue: 0.282) // oklch(64% 0.21 42)
    static let accentSoft = Color(red: 0.957, green: 0.911, blue: 0.866) // oklch(94% 0.05 60)
    static let accentInk  = Color(red: 0.553, green: 0.293, blue: 0.149) // oklch(38% 0.15 42)
    static let warn       = Color(red: 0.604, green: 0.416, blue: 0.094) // amber for missing
    static let success    = Color(red: 0.184, green: 0.420, blue: 0.243)
}

extension Font {
    static let displayLg   = Font.custom("Instrument Serif", size: 18) // column / nickname
    static let displayMd   = Font.custom("Instrument Serif", size: 17)
    static let monoCaps    = Font.system(.caption2, design: .monospaced).weight(.medium)
    static let monoLabel   = Font.system(.footnote, design: .monospaced).weight(.semibold)
    static let sans12      = Font.system(size: 12, weight: .regular)
    static let sans11      = Font.system(size: 11, weight: .medium)
}
```

Bundle **Instrument Serif** and **JetBrains Mono** as a resource (TTF) — link via the existing `Package.swift` `resources:` block. Fall back to system serif / monospaced if the font fails to load. **Don't** download fonts at runtime.

---

## Interactions

### Loading states

- **Latest**: When the popover opens, immediately render skeleton tiles (paper-2 fill, no image) for the column heights you expect — usually 4 tiles. Replace each with a real tile as `getWallpapers` returns. The skeleton uses the same `.mac-tile` chrome so layout doesn't shift.
- **Downloaded**: Always shows the local list (which is computed from `~/Library/Application Support/WallpaperExchange/Downloads`), so no network skeleton needed. If empty, show an inline empty-state in the column body: a muted display 17 px line "No downloads yet." + sans 12 px subtitle "Try a wallpaper from Latest. Use `Set & download` to apply it instantly." Centered, padding 40 px.

### Set & download

Clicking `[Set & download]` on a Latest tile chains two actions:
1. Trigger the existing download path (deducts the coin balance server-side, downloads to the Downloads folder).
2. On success, immediately call the existing wallpaper-apply path with the freshly-downloaded file.

Show the button in a loading state during step 1 (spinner replaces the download icon; button stays visible, disabled). On step 2 success, replace the tile briefly with a checkmark + "Applied" before reverting to normal. On failure of step 1 (insufficient coins → 402), revert and show the same "Insufficient coins" toast that the web uses, with an inline link to "Open archive to earn coins" (opens the web app via the `wallxch://` scheme or directly to the in-app browser, your call).

### Set as wallpaper

On Downloaded, `[Set as wallpaper]` is a single action — no network. After the call completes, update the `Active` chip on the new tile and remove it from the previously-active one. Optimistic update is fine.

### Re-download

If a tile has the `Local missing` chip and the user clicks `[Re-download]`, hit the download endpoint **without** deducting another coin. The server already records that this user has this wallpaper; just refetch the original file. Coin balance unchanged. On success, the `Local missing` chip and `Re-download` button both disappear.

If the server insists on re-charging (because it doesn't track who has downloaded what — verify this with the backend team), surface a confirmation dialog: "This will spend another coin to re-download. Continue?" — sticky paper card with accent confirm and ghost cancel.

### Dynamic filter

Pure client-side filter on the items in each column. Doesn't refetch. When enabled on Latest, also pass the `dynamic_only=true` query parameter so subsequent fetches stay filtered.

### Shuffle

When the user enables Shuffle on Downloaded:
1. Persist `shuffleEnabled = true` + `shuffleIntervalSec = 14400` (4 hours) + `nextShuffleAt = now + 4h` to `UserDefaults`.
2. Schedule a `DispatchSourceTimer` (or `Timer.scheduledTimer` if your event-loop allows it) firing at `nextShuffleAt`.
3. On fire: pick a random downloaded wallpaper (excluding the currently-applied one if possible) and call the apply path. Update `nextShuffleAt += 4h` and reschedule.
4. The status banner countdown updates once per minute.

When the popover is closed, the timer keeps running — that's the whole point of the menu-bar app. When the user disables Shuffle, cancel the timer and clear the persisted state.

If macOS is asleep when `nextShuffleAt` passes, fire on next wake; the system delivers the missed timer at wake time, which is fine. Don't try to be clever about catching up multiple missed intervals.

---

## States to verify

The prototype canvas has three artboards under "09 · macOS menu-bar app":

| Artboard | Tests |
|---|---|
| **Default** | Header + 2 columns + footer; two tiles pinned-hovered so you can see the action rails (Latest's №004 shows Download + Set & download; Downloaded's №006 shows Re-download + Set as wallpaper because file is missing) |
| **Dynamic filter** | Both `Dynamic` toggle pills are in accent-orange active state; the list updates to show only dynamic wallpapers (in the prototype the existing data already includes dynamic items; in production the filter applies) |
| **Shuffle on** | The shuffle banner appears under the Downloaded heading with `NEXT · 2 H 34 M`; Shuffle toggle is accent-orange |

---

## Files

| Prototype | Real codebase target |
|---|---|
| `prototype/macos.jsx` → `MacPopover` | `macos/WallpaperExchange/Sources/App/PopoverContentView.swift` (rewrite) |
| `prototype/macos.jsx` → `MacHeader`, `MacColumn`, `MacTile`, `MacFooter` | New SwiftUI views under `macos/WallpaperExchange/Sources/Views/Popover/` |
| `prototype/tokens.css` → `.mac-popover`, `.mac-tile`, `.mac-toggle`, `.mac-banner`, etc. | New Swift `Color` and view modifier extensions |
| `prototype/shared.jsx` → `I.shuffle`, `I.refresh`, `I.set`, `I.power`, `I.bolt`, etc. | New SF Symbols mapping: shuffle, arrow.clockwise, display, power, bolt.fill |

---

## Out of scope

- Settings / preferences pane — defer to a separate handoff.
- Onboarding (first launch, sign-in flow via `wallxch://`) — out of scope. Keep the existing flow but apply the new typography + chip styling once it lands.
- A separate "Sign in" view when unauthenticated — show the same popover chrome but replace the body with an editorial "sign in to load specimens" prompt + a paper-styled `[Sign in via web]` button that triggers the OAuth flow. A polished design for that empty state is a follow-up.
- Anything outside the popover — Dock icon (the app stays `LSUIElement = true`), main window (none), preferences window (none in v2).

---

## Verification

- [ ] Popover is 720 × 700 px, anchored under the menu-bar W icon
- [ ] Frosted-glass paper background, 14 px radius, soft outer shadow + 1 px inset highlight
- [ ] Tail/triangle visible at the top, centered under the menu-bar icon
- [ ] Header: avatar + nickname + handle (left), ink-pill coin balance with orange coin glyph (center), circular logout (right)
- [ ] 2-column body separated by a vertical hairline
- [ ] Latest column has only the `Dynamic` toggle; Downloaded has `Shuffle` + `Dynamic`
- [ ] Tile chrome: 4K + Mac chips top-left, Active or Local missing chip top-right when applicable
- [ ] Hover dark gradient + action buttons fade in from the bottom
- [ ] Latest hover: `Download` (glass) + `Set & download` (accent primary)
- [ ] Downloaded hover (file present): `Set as wallpaper` (accent primary, single button)
- [ ] Downloaded hover (file missing): `Re-download` (glass) + `Set as wallpaper` (accent primary)
- [ ] Toggle pill active state: accent-orange background + white text + no border
- [ ] Shuffle banner shows accent-soft bg, dark accent-ink text, orange shuffle glyph, mono countdown right-aligned
- [ ] Footer: Quit + Open in browser (left), mono version label (right)
- [ ] Sign-out behavior: closes popover and returns to auth flow
- [ ] Set wallpaper from Downloaded: optimistically moves the `Active` chip
- [ ] Set & download from Latest: chains download → apply, shows a brief `Applied` state, reverts to normal
- [ ] Re-download skips coin charge (verify with backend)
- [ ] Shuffle keeps running when the popover is closed; timer survives popover dismissal
