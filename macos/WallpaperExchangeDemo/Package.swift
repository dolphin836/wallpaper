// swift-tools-version: 5.10
import PackageDescription

// Standalone preview app for the Mac client redesign. Lives outside
// the production WallpaperExchange package so iterating on the new
// look doesn't risk breaking the menu-bar app that's already shipping.
//
// Run:  cd macos/WallpaperExchangeDemo && swift run
let package = Package(
    name: "WallpaperExchangeDemo",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "WallpaperExchangeDemo",
            path: "Sources"
        ),
    ]
)
