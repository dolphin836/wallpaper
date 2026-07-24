# Design QA — macOS Wallpaper Detail and Fullscreen Preview

## Source visual truth

- Web detail action bar: `/var/folders/gk/yd1p23gs65zb8z0nl7sczxq40000gn/T/codex-clipboard-26e6c9e5-20e7-4969-b217-e2dd2f04ff45.png`
- Fullscreen viewer controls: `/var/folders/gk/yd1p23gs65zb8z0nl7sczxq40000gn/T/codex-clipboard-6922634a-e559-48df-b180-055ba5c290f1.png`
- Plain / Home / Lock picker: `/var/folders/gk/yd1p23gs65zb8z0nl7sczxq40000gn/T/codex-clipboard-9e2356a9-be65-4181-acb8-b24692e4c3d0.png`

## Implementation evidence

- Detail page: `/Users/eric/.codex/visualizations/2026/07/24/019f92cc-939f-7371-a94f-e1e4c65cd93f/mac-detail-action-bar.png`
- Fullscreen plain mode, final: `/Users/eric/.codex/visualizations/2026/07/24/019f92cc-939f-7371-a94f-e1e4c65cd93f/mac-fullscreen-plain-final.png`
- Fullscreen home mode: `/Users/eric/.codex/visualizations/2026/07/24/019f92cc-939f-7371-a94f-e1e4c65cd93f/mac-fullscreen-home.png`
- Fullscreen lock mode: `/Users/eric/.codex/visualizations/2026/07/24/019f92cc-939f-7371-a94f-e1e4c65cd93f/mac-fullscreen-lock.png`

## Viewport and state

- Native macOS app window: `1203 × 768` points in the Computer Use capture.
- State: Chinese (Simplified), authenticated detail view, static 8K JPEG (`8792 × 4928`), action bar visible; fullscreen plain, home, and lock modes checked.
- Source pixels: action bar `1734 × 228`; viewer `800 × 370`; mode picker `542 × 160`.
- Implementation pixels: each full native capture `1203 × 768`.
- The provided references are component crops at mixed densities rather than a full matching viewport. Focused comparisons normalize both sides to the same output width (`1200 px` for the action bar/viewer and `900 px` for the picker); no assumed `@2x` downsampling was applied.

## Comparison evidence

### Full view

- `/Users/eric/.codex/visualizations/2026/07/24/019f92cc-939f-7371-a94f-e1e4c65cd93f/compare-fullscreen-final.png`
- The implementation preserves the reference hierarchy: image-first canvas, compact metadata/zoom readout, one grouped zoom/rotate/reset dock, and an explicit close control. The extra three-mode selector is centered at the top and remains visually separate from viewer controls.

### Focused regions

- Action bar: `/Users/eric/.codex/visualizations/2026/07/24/019f92cc-939f-7371-a94f-e1e4c65cd93f/compare-action-bars.png`
  - Matches the web ordering and contrast: two-line metadata, divider, social actions, divider, fullscreen, primary download. The macOS-only Download & Set action is retained as a dark secondary pill.
- Mode picker: `/Users/eric/.codex/visualizations/2026/07/24/019f92cc-939f-7371-a94f-e1e4c65cd93f/compare-mode-picker.png`
  - Matches the white capsule / black selected capsule treatment and the Plain / Home / Lock order.

## Findings

- No remaining actionable P0, P1, or P2 visual differences.
- Native interaction checks passed: open/close, Plain/Home/Lock switching, zoom `100% → 125%`, rotate, reset, and Escape closing only the fullscreen preview while keeping the detail page open.
- Browser console checks are not applicable because this is a native SwiftUI surface. `swift build` and the universal `.app` build both pass.

## Comparison history

1. Initial fullscreen comparison found a P2 visual issue: the dominant-color placeholder remained visible in letterboxed areas, which read as two extra brown UI bands.
2. Replaced fullscreen letterboxing with neutral black and rebuilt the native app.
3. Post-fix evidence: `mac-fullscreen-plain-final.png` and `compare-fullscreen-final.png`; the extra colored bands are gone and no P0/P1/P2 findings remain.

final result: passed
