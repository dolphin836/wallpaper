# Wallpaper Exchange Chrome Extension

First installable version of the Wallpaper Exchange new tab extension.

## Install locally

1. Open `chrome://extensions`.
2. Enable `Developer mode`.
3. Click `Load unpacked`.
4. Select this `chrome-extension` folder.

## What this version does

- Replaces the Chrome new tab page with a wallpaper-first experience.
- Keeps the canvas clean. Only the bottom-right settings button is always visible.
- Supports Weekly Picks by default.
- Supports sign in or registration in a modal.
- After sign in, supports My Favorites and one selected My Collection.
- Lets users pick a specific wallpaper from the active source.
- Supports random rotation from the active source, with an optional interval.
- Supports browser-following language, Simplified Chinese, Traditional Chinese, English, and Japanese.
- Supports clock, search, and user-managed quick link widgets, all enabled by default.
- Reports Chrome extension analytics events through the existing `/events` API.

## Notes

- This version is plain Manifest V3 HTML, CSS, and JavaScript. No build step is required.
- The backend CORS allow-list accepts `chrome-extension://` origins so the installed extension can call the existing API.
