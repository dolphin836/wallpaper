# Wallpaper Exchange Design System

## Product Read

Wallpaper Exchange is a high-quality wallpaper archive, creator queue, and desktop wallpaper control surface. The interface should feel quiet, precise, image-led, and trustworthy. The product is not a dashboard, not a marketing landing page, and not a generic image grid.

## Design Direction

- Keep the current architecture: web top navigation, image-led home/discover pages, web-style wallpaper detail modal, and macOS sidebar + toolbar shell.
- Raise quality through consistency: shared tokens, unified card language, stateful controls, restrained motion, and platform-aware macOS behavior.
- Use the wallpaper image as the visual star. Chrome should frame, clarify, and respond to content, not compete with it.
- Favor a restrained editorial archive feel: tinted paper, ink, warm exchange accent, hairline borders, and precise media framing.

## Tokens

### Color

- `paper`: main content surface, never pure white.
- `paper-2`: toolbars, chips, secondary panels, drop zones, skeleton fills.
- `paper-3`: deeper placeholders and card floors.
- `ink`: primary text and selected controls.
- `ink-2`: secondary text and inactive controls.
- `muted`: metadata, counters, disabled labels, low-emphasis helper text.
- `hair`: one-pixel borders and dividers.
- `accent`: exchange, trade, upload, coin, and primary action moments.
- `accent-soft`: progress tracks, warnings, selected soft backgrounds.
- `like`, `favorite`, `downloaded`: persistent social/action states only.

Avoid legacy purple, indigo, slate, and pure grayscale tokens on public product surfaces. Admin tools may keep their operational slate vocabulary.

### Typography

- Product UI uses one strong sans family for labels, body, buttons, tabs, and data.
- Editorial display type is allowed for page titles and section headings only.
- Monospace uppercase is reserved for metadata labels: resolution, status, section kickers, and technical file details.
- Do not use display fonts in controls, navigation labels, form labels, or dense status rows.

### Shape

- Media cards: 10-14px radius.
- Detail panels and major modal shells: 22-24px radius.
- Buttons and chips: pill when the action is compact, 8px radius for menus and form controls.
- Avoid mixing square, pill, and large-rounded treatments without a clear role.

### Elevation

- Default surfaces rely on hairline borders and spacing.
- Media cards may lift on hover with a tinted shadow.
- Detail modals may use a strong shadow because they sit above a dimmed page.
- Avoid decorative glass. Material and blur are valid only for macOS chrome, modal scrims, and image-derived preview backgrounds.

## Components

### Wallpaper Cards

- Image fills the card.
- Top-left chips show resolution and content tags (`LIVE`, `AI`, review state, local missing).
- Actions reveal on hover/focus and keep the same order: favorite, like, download, set/open.
- Downloaded, liked, and favorited states must be visible before hover when space allows.
- Processing/pending/rejected tiles use the same media dimensions as published tiles.

### Detail Views

- The preview image is the hero. Controls sit below or beside it, never on top unless they are viewer controls.
- Download/trade progress is a horizontal bar below the preview/action area.
- Similar wallpapers always show complete rows based on available width.
- Notices use a shared inline alert vocabulary: success, set, insufficient coins, unavailable, failed.
- Fullscreen viewing is an image tool, not a separate page style.

### Upload

- Upload is a page, not a modal.
- Selected files sit above the upload action.
- Progress stays near the queue it controls.
- Pending and processing uploads use the same tile sizing as uploaded wallpapers.
- Review messaging should explain status once, then let tiles carry per-item state.

### Navigation

- Web: keep the top navigation lightweight and sticky.
- macOS: keep sidebar navigation stable and move global actions to the top toolbar.
- Back/forward actions belong near the content origin, not next to unrelated system controls.
- Upload is a primary action; settings, refresh, and theme are utilities.

## Motion

- Most UI transitions: 150-250ms ease-out.
- Large image reveal or modal entrance: 260-380ms, still ease-out.
- Palette mesh changes may be slower, but must not move layout.
- Avoid animated layout shifts. Animate opacity, transform, and color.
- Respect reduced motion by removing nonessential transforms and long-running mesh motion.

## States

Every remote-data surface needs loading, success, empty, error, retry, and pagination/end states where relevant.

Every user action needs a disabled/loading state and a clear failure state:

- Download/trade: disabled buttons, horizontal progress, insufficient coin warning, success/done state.
- Upload: per-file status, aggregate progress, retry failed rows.
- Like/favorite: optimistic state is okay, but failed requests must revert or notify.
- Set wallpaper: distinguish normal image, macOS dynamic wallpaper, and video wallpaper.

## Platform Notes

### Web

- Use the archive tokens consistently across public surfaces.
- Prefer accessible React primitives or simple native controls over custom behavior.
- Keep CSS utilities and component classes small enough that future changes do not require editing a 5k-line global stylesheet for every detail.

### macOS

- Respect macOS expectations: visible traffic lights, native cursor behavior, menu/toolbar grouping, compact controls, and system focus behavior.
- Use SwiftUI system fonts for dense UI. Editorial serif is for content headings, not every title.
- Material should feel like macOS chrome, not web glassmorphism.
- Fullscreen and windowed layouts must share alignment rules and content density.
