// swift-tools-version:5.9
// macOS dev-preview target for the iOS client. The canonical product is
// the XcodeGen iOS app (project.yml); this package compiles the same
// sources against the macOS SDK so the app can be type-checked and run
// as a desktop window on machines without full Xcode:
//
//   cd ios && swift run
//
// Platform divergence lives in Views/Components/PlatformShims.swift.
import PackageDescription

let package = Package(
    name: "WallpaperExchangeIOS",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    targets: [
        .executableTarget(
            name: "WallpaperExchangeIOS",
            path: "WallpaperExchange/Sources"
        ),
    ]
)
