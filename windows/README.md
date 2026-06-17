# Wallpaper Exchange Windows Client

Windows desktop client built with React + Tauri 2. The UI mirrors the current
macOS client structure as closely as practical:

- Home, Discover, Weekly Picks, Collections, Downloads, Library, Upload, Settings.
- Full-screen wallpaper detail overlay with preview-first loading, similar wallpapers,
  info menu, like/favorite, add-to-collection, download, and set-wallpaper actions.
- Local download cache under the Tauri app data directory.
- Windows static wallpaper support through `SystemParametersInfoW`.
- macOS dynamic HEIC and video wallpapers are displayed in-app, downloaded normally,
  and downgraded to a static preview when setting the Windows desktop wallpaper.
- My Collections can be selected as the preferred autoplay source. Missing collection
  wallpapers are downloaded before the autoplay source is activated.

## Development

```bash
cd windows
npm install
npm run tauri:dev
```

## Verification

```bash
cd windows
npm run build
npm run lint
cd src-tauri && cargo check
```

## Packaging

The Tauri config targets Windows MSI and NSIS installers:

```bash
cd windows
npm run tauri:build
```

Run the packaging command on a Windows machine or Windows CI runner to produce
the `.msi` / `.exe` installers. Running the same command on macOS validates the
frontend and Rust app and emits a current-platform release binary, but it cannot
produce Windows installers.
