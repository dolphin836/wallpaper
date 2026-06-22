# Wallpaper Exchange Chrome Extension

First installable version of the Wallpaper Exchange new tab extension.

## Install locally

1. Open `chrome://extensions`.
2. Enable `Developer mode`.
3. Click `Load unpacked`.
4. Select this `chrome-extension` folder.

## What this version does

- Replaces the Chrome new tab page with a wallpaper-first experience.
- Uses Weekly Picks by default.
- Supports sign in with the existing Wallpaper Exchange account.
- After sign in, supports My Favorites and one selected My Collection.
- Keeps controls quiet so the wallpaper stays the main focus.

## Notes

- This version is plain Manifest V3 HTML, CSS, and JavaScript. No build step is required.
- The backend CORS allow-list accepts `chrome-extension://` origins so the installed extension can call the existing API.
