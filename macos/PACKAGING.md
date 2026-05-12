# Packaging the macOS Client

The Swift Package builds a CLI-style executable, not a `.app`. Use `build-app.sh`
to wrap it into a redistributable bundle.

```bash
cd macos
./build-app.sh            # produces ./Wallpaper Exchange.app
./build-app.sh --dmg      # also produces ./Wallpaper Exchange.dmg
```

What the script does, in order:

1. `swift build -c release` — compiles an optimized binary at
   `WallpaperExchange/.build/release/WallpaperExchange`.
2. Creates `Wallpaper Exchange.app/Contents/{MacOS,Resources}/`.
3. Copies the executable into `MacOS/`.
4. Copies the on-disk `Info.plist` into `Contents/`. (The binary also has a
   linker-embedded copy for CLI-style runs; macOS only reads the on-disk one
   when launching a `.app`.)
5. Copies the SwiftPM resource bundle (`WallpaperExchange_WallpaperExchange.bundle`,
   contains `StatusBarIcon.png`) into `Contents/Resources/` so `Bundle.module`
   can find it at runtime.
6. Optionally drops in `AppIcon.icns` if you've placed one at `macos/AppIcon.icns`.
7. Code-signs the bundle. Defaults to **ad-hoc** signing (`-` identity), which is
   enough for the bundle to launch but **does not** clear Gatekeeper on machines
   that didn't build it.
8. With `--dmg`, wraps the `.app` in a compressed UDZO disk image via `hdiutil`.

## Distribution levels (pick one)

### Level 0 — local-only

What you get from a plain `./build-app.sh`. The `.app` runs on your machine
because Gatekeeper trusts what you just built. **On any other Mac**, double-click
gives:

> "Wallpaper Exchange.app" cannot be opened because the developer cannot be verified.

Recipient workarounds (no setup on your side, but ugly):

- Right-click the `.app` → **Open** → click **Open** in the dialog. macOS adds it
  to the user's per-app allowlist. Future launches are silent.
- Or strip the quarantine attribute from terminal:
  `xattr -d com.apple.quarantine "/Applications/Wallpaper Exchange.app"`
- Or System Settings → **Privacy & Security** → click **Open Anyway** after the
  first failed double-click.

Fine for friends/dogfood. Not fine for public distribution.

### Level 1 — Developer ID signed (no notarization)

Requires an Apple Developer Program membership ($99/year) and a **Developer ID
Application** certificate installed in your login keychain (Xcode → Settings →
Accounts → Manage Certificates can create one).

```bash
./build-app.sh --sign "Developer ID Application: Your Name (ABCDE12345)"
```

Improves the situation slightly — Gatekeeper recognizes a valid Apple-issued
signature — but **macOS 10.15+** still demands notarization for anything
downloaded via browser/AirDrop/iCloud. Without notarization, recipients still
see the warning and need the right-click → Open workaround. Useful as an
intermediate step, but in practice Level 2 is what you want.

### Level 2 — Developer ID signed + notarized + stapled

The only way to get a frictionless install on third-party Macs.

```bash
# 1. Build + sign as in Level 1.
./build-app.sh --sign "Developer ID Application: Your Name (ABCDE12345)"

# 2. Zip the .app for submission (notarytool requires .zip / .dmg / .pkg).
ditto -c -k --keepParent "Wallpaper Exchange.app" "Wallpaper Exchange.zip"

# 3. Submit to Apple. They scan + return verdict in 5-30min usually.
xcrun notarytool submit "Wallpaper Exchange.zip" \
    --apple-id you@example.com \
    --team-id ABCDE12345 \
    --password "<app-specific-password>" \
    --wait

# 4. Once accepted, staple the ticket so the .app works offline (otherwise it
#    only works on machines that can phone home to Apple at first launch).
xcrun stapler staple "Wallpaper Exchange.app"

# 5. Build the final DMG from the now-stapled .app.
./build-app.sh --dmg --sign "Developer ID Application: Your Name (ABCDE12345)"
```

App-specific passwords are created at https://appleid.apple.com → Sign-In and
Security → App-Specific Passwords. Do not use your AppleID password directly.

One-time `notarytool` setup (lets you skip the `--password` / `--apple-id` /
`--team-id` flags after first run):

```bash
xcrun notarytool store-credentials "wallpaper-notarize-profile" \
    --apple-id you@example.com \
    --team-id ABCDE12345 \
    --password "<app-specific-password>"
```

Then later: `xcrun notarytool submit ... --keychain-profile wallpaper-notarize-profile --wait`.

## Adding an AppIcon

The menubar (status bar) icon ships from `Sources/Resources/StatusBarIcon.png`
and that's the only icon the running app uses (it's a menubar app, no dock
icon). But the Finder + drag-to-Applications experience uses `CFBundleIconFile`
from `Contents/Resources/AppIcon.icns`. To set one:

```bash
# 1. Make a 1024×1024 PNG of the logo. Then build the .icns:
mkdir AppIcon.iconset
sips -z 16 16    logo-1024.png --out AppIcon.iconset/icon_16x16.png
sips -z 32 32    logo-1024.png --out AppIcon.iconset/icon_16x16@2x.png
sips -z 32 32    logo-1024.png --out AppIcon.iconset/icon_32x32.png
sips -z 64 64    logo-1024.png --out AppIcon.iconset/icon_32x32@2x.png
sips -z 128 128  logo-1024.png --out AppIcon.iconset/icon_128x128.png
sips -z 256 256  logo-1024.png --out AppIcon.iconset/icon_128x128@2x.png
sips -z 256 256  logo-1024.png --out AppIcon.iconset/icon_256x256.png
sips -z 512 512  logo-1024.png --out AppIcon.iconset/icon_256x256@2x.png
sips -z 512 512  logo-1024.png --out AppIcon.iconset/icon_512x512.png
cp logo-1024.png AppIcon.iconset/icon_512x512@2x.png
iconutil -c icns AppIcon.iconset -o macos/AppIcon.icns

# 2. Re-run build-app.sh — it picks up macos/AppIcon.icns automatically.
```

## Verifying the bundle

After building:

```bash
# Confirm it's a valid bundle, signed correctly.
codesign --verify --deep --strict --verbose=2 "Wallpaper Exchange.app"
spctl --assess --type execute --verbose "Wallpaper Exchange.app"

# Inspect entitlements + signing identity.
codesign -dv --verbose=4 "Wallpaper Exchange.app" 2>&1 | head -20
```

For notarized builds:

```bash
xcrun stapler validate "Wallpaper Exchange.app"
```

If `spctl` rejects an ad-hoc-signed app with "source=Unnotarized Developer ID",
that's expected — it's how Gatekeeper reports the missing notarization.
