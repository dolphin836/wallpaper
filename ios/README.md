<!-- [skill: go-team-standards · 接口文档示例] iOS client build & architecture notes -->
# WallpaperExchange iOS Client

SwiftUI iOS app (iOS 17+) for the Wallpaper Exchange platform, sharing its
API surface and conventions with the macOS client in `macos/`.

## Features

Bottom tabs: **Home / Discover / Make / Me**, plus a shared top toolbar
(collections full-screen drawer on the left, serif page title in the
middle, global lock-screen-preview toggle on the right — when on, every
tile renders the iOS lock mock: clock, date, flashlight/camera pills).

- **Home** — curated shelf mirroring web/Mac: weekly picks rail (with
  past-weeks archive behind "See all"), collections rail, AI rail, Live
  rail.
- **Discover** — the full archive: in-page search, Latest / Popular /
  For You / Live / AI feed pills, category chips, infinite two-column grid.
- **Make** — mobile-only wallpaper workshop: pick a local photo, apply
  one of the archive looks (Mono / Film / Dusk / Ink Wash / Vivid /
  Frost, CoreImage pipelines), judge it behind the lock-screen mock,
  save the full-resolution render to Photos.
- **Collections** — full-screen drawer with paged public collections.
- **Detail** — hero image, stats, palette, tags, uploader card, like /
  favorite (optimistic with rollback), add-to-collection, similar grid,
  and the 1-coin download flow which saves the full-resolution file to
  the photo library (iOS offers no public set-wallpaper API).
- **Upload** — PhotosPicker → multipart `POST /wallpapers`, with the
  review-queue status messaging.
- **Account** — native login/register, profile header, coin balance +
  ledger, the four library tabs (uploads / likes / favorites /
  downloads), edit profile (incl. avatar), change password, sign out.
- JWT lives in the Keychain (same `KeychainTokenStore` as the Mac
  client). Image loading uses the shared decoded-memory + SHA-256 disk
  cache design ported from the Mac client.

## Running on a Mac without Xcode (dev preview)

`Package.swift` compiles the same sources against the macOS SDK — full
type checking plus a runnable desktop window, CommandLineTools only:

```bash
cd ios && swift run
```

Platform divergence (UIKit/AppKit colors, iOS-only modifiers, UIImage vs
NSImage, UIScreen vs NSScreen) is bridged in
`Views/Components/PlatformShims.swift`; everything else is shared.

## Building the real iOS app

This needs **full Xcode** (iOS SDK + simulators) — CommandLineTools
alone, as installed on the repo's dev box, can parse and macOS-build but
not compile the iOS target.

```bash
brew install xcodegen            # once
cd ios
xcodegen generate                # produces WallpaperExchange.xcodeproj
open WallpaperExchange.xcodeproj # build & run on a simulator
```

CLI build against a simulator:

```bash
xcodebuild -project WallpaperExchange.xcodeproj \
  -scheme WallpaperExchange \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Device / TestFlight builds additionally need `DEVELOPMENT_TEAM` filled
in `project.yml` (then re-run `xcodegen generate`).

## Layout

```
ios/
├── project.yml                  # XcodeGen definition (bundle id com.wallpaperexchange.ios)
└── WallpaperExchange/Sources/
    ├── App/                     # @main entry + root TabView
    ├── Models/                  # copied verbatim from macos/ (Foundation-only)
    ├── Services/                # APIClient (UIKit-adapted), AuthService,
    │                            # KeychainTokenStore, PhotoSaver
    └── Views/
        ├── Components/          # CachedAsyncImage, WallpaperGrid, shared states
        ├── Discover/ Weekly/ Collections/ Detail/ Auth/ Account/ Upload/
```

## Relationship to the macOS client

`Models/*.swift` and `APIClient+Endpoints.swift` are byte-identical
copies of the Mac sources; `KeychainTokenStore.swift` differs only in
its service name (`com.wallpaperexchange.ios` — sharing the Mac service
triggers a cross-app Keychain prompt when the dev-preview runs on the
same Mac as the real client); `APIClient.swift` drops the Mac-only surface (NSScreen
enumeration, DMG release manifest, file-URL uploads, tus video upload)
and adds a `Data`-based upload for PhotosPicker. If an endpoint changes,
update both clients — there is intentionally no shared SwiftPM package
yet to keep the Mac build untouched; extracting one is the natural next
refactor once both clients stabilize.
